includes("psexe")

local psx_dir = os.scriptdir()
local psx_compiler_cache = {
	auto_cross = {},
	gcc_info = {},
}

local function detect_auto_cross(find_program)
	local cache_key = table.concat({os.getenv("PATH") or "", os.getenv("CROSS") or "", os.getenv("CC") or ""}, "\31")
	local cached = psx_compiler_cache.auto_cross[cache_key]
	if cached ~= nil then
		return cached, true
	end

	local detected_cross = ""
	local arch_possibilities = {"mipsel", "mips", "mips64"}
	local vendor_possibilities = {"psx", "none", "linux", "", "unknown"}
	local abi_possibilities = {"elf", "gnu"}
	for _, arch in ipairs(arch_possibilities) do
		for _, vendor in ipairs(vendor_possibilities) do
			for _, abi in ipairs(abi_possibilities) do
				local checked_cross
				if vendor == "" then -- account for toolchains missing the vendor part
					checked_cross = arch .. "-" .. abi .. "-"
				else
					checked_cross = arch .. "-" .. vendor .. "-" .. abi .. "-"
				end
				if find_program(checked_cross .. "gcc") then
					detected_cross = checked_cross
					if detected_cross ~= "" then
						psx_compiler_cache.auto_cross[cache_key] = detected_cross
					end
					return detected_cross, false
				end
			end
		end
	end

	return nil, false
end

local function get_gcc_info(os, find_program, cross)
	local gcc_info = psx_compiler_cache.gcc_info[cross]
	if gcc_info then
		return gcc_info
	end

	local gcc_version_output = os.iorunv(cross .. "gcc", {"-dumpversion"})
	local gcc_version = gcc_version_output and gcc_version_output:trim() or ""
	local gcc_major_version = tonumber(gcc_version:match("^%d+"))
	local has_gxx = find_program(cross .. "g++")

	gcc_info = {
		version = gcc_version,
		major_version = gcc_major_version,
		has_gxx = has_gxx,
	}
	psx_compiler_cache.gcc_info[cross] = gcc_info
	return gcc_info
end

-- prepend to certain flag groups in the target
-- this is needed because compilers favor the last set flags, and we want the user's flags to override ours
local function prepend(target, groups, new_flags)
	for group_i = 1, #groups do
		local group_name = groups[group_i]

		local old_flags = {target:get(group_name)} -- backup the existing values
		target:set(group_name) -- erase the existing values

		-- put the new flags in first, then add the old flags back
		-- note we need {force = true} because many of our flags are not recognized by xmake
		for i = 1, #new_flags do
			target:add(group_name, new_flags[i], {force = true})
		end
		for i = 1, #old_flags do
			target:add(group_name, old_flags[i], {force = true})
		end
	end
end

-- clang-only flags
local function prepend_clang_flags(os, target, cross, has_gxx)
	-- clang unfortunately does not support eabi, register struct returns, nor configuring arbitrary registers like gcc
	local clang_flags = {
		"--target=mipsel-none-elf", "-march=mips1", "-mfloat-abi=soft",
		"-falign-functions=16", "-falign-loops=1",
		"-mno-check-zero-division", -- clang doesn't support -mdivide-breaks, it can only use the 'teq' instruction which is not supported on PS1
		"-fuse-ld=lld", -- for some reason, clang doesn't use the right linker by default, making LTO fail

		-- for some reason, when ThinLTO is on, the linker forgets some things
		"-Wl,-mllvm=-mattr=+soft-float",
		"-Wl,-mllvm=-mattr=+noabicalls",

		-- clang appears to assume loads from scratchpad values are always 0? (TODO: check if this still happens in clang 22 and/or 23)
		"-DSCRATCHPAD=",
	}

	if not target:has_cflags("-mno-gpopt") then
		table.append(clang_flags, "-membedded-data", "-mno-extern-sdata")
	end

	-- clang's freestanding support is poor, so make it use gcc's standard headers
	if cross ~= "" then
		table.append(clang_flags, "-nostdinc", "-nostdinc++")
		local _, stderr = os.iorunv(cross .. (has_gxx and "g++" or "gcc"), {"-ffreestanding", "-xc++", path.join(psx_dir, "files/empty.c"), "-E", "-Wp,-v"})
		for _, line in ipairs(stderr:split("\n")) do
			if line:startswith(" ") then
				target:add("sysincludedirs", line:trim())
			end
		end
	end

	-- TODO: try using the freestanding C++ STL and check if it needs a similar workaround

	prepend(target, {"cxflags", "ldflags", "asflags"}, clang_flags)
end

rule("psx", function()
	before_config(function(target)
		import("lib.detect.find_program")

		local target_kind = target:kind()
		if target_kind == "binary" then
			target:set("extension", ".elf")
		end

		local cross = target:values("cross") or os.getenv("CROSS") or ""
		local configvar = target:get("configvar")
		local using_clang = configvar and configvar.clang or os.getenv("XMAKE_IN_COMPILE_COMMANDS_PROJECT_GENERATOR")
		local clang_prefix

		local configured_cc = target:values("cc") or os.getenv("CC")
		if configured_cc then
			if configured_cc:endswith("clang") then
				using_clang = true
				clang_prefix = configured_cc:sub(1, -6)
			elseif configured_cc:endswith("gcc") then
				if not find_program(configured_cc) then
					raise(configured_cc .. " was specified as the C compiler, but it was not found")
				end
				cross = configured_cc:sub(1, -4)
			else
				raise("unrecognized " .. configured_cc .. " was specified as the C compiler, it must be a version of gcc or clang")
			end
		end

		local cached = false
		if cross == "" then
			cross, cached = detect_auto_cross(find_program)
			if cross == "" and not using_clang then
				raise("could not find an appropriate compiler (try installing an up to date mipsel, mips, or mips64 gcc toolchain)")
			end
		elseif cross == "none" then
			cross = ""
		end
		target:set("plat", "psx")
		target:set("arch", "mipsel")

		target:set("configvar", "cross", cross or "")
		target:set("toolchains", "cross")
		local gcc_version, gcc_major_version, has_gxx
		if cross ~= "" then
			local gcc_info = get_gcc_info(os, find_program, cross)
			gcc_version = gcc_info.version
			gcc_major_version = gcc_info.major_version
			has_gxx = gcc_info.has_gxx
			if gcc_major_version and gcc_major_version < 16 then
				-- while GCC 14 recognizes C23, it doesn't fully support it (for example, #embed is missing)
				-- it's also supposed to support C++ modules, but it crashes all the time when trying to deal with them
				-- in my experience GCC 15 crashes often with modules, and also with LTO, but 16 is much more stable
				print("warning: the installed " .. cross .. "gcc is outdated (version " .. gcc_version .. "), so modern C and C++ features may be missing or broken")
			end
			if not has_gxx then
				print("warning: could not find " .. cross .. "g++, C++ may not work properly")
			end
		end
		cached = cached and "(cached) " or ""

		if using_clang then
			print("using " .. cached .. "clang for target " .. target:name())
			print("note that LLVM's support for MIPS-I is experimental!")
			if cross == "" then
				print("warning: you can use clang without gcc, but may face issues with the standard headers (try installing an up to date mipsel, mips, or mips64 gcc toolchain)")
			end
			target:set("toolset", "cc", clang_prefix .. "clang")
			target:set("toolset", "cxx", clang_prefix .. "clang++")
			target:set("toolset", "as", clang_prefix .. "clang")
			target:set("toolset", "mm", clang_prefix .. "clang")
			target:set("toolset", "mxx", clang_prefix .. "clang++")
			target:set("toolset", "ld", clang_prefix .. "clang")
			target:set("toolset", "ar", clang_prefix .. "llvm-ar")
			target:set("toolset", "ex", clang_prefix .. "llvm-ar")
			target:set("toolset", "strip", clang_prefix .. "llvm-strip")
		else
			print("using " .. cached .. cross .. "gcc for target " .. target:name())
			target:set("toolset", "cc", cross .. "gcc")
			target:set("toolset", "cxx", cross .. (has_gxx and "g++" or "gcc"))
			target:set("toolset", "as", cross .. "gcc")
			target:set("toolset", "ld", cross .. "gcc")
			target:set("toolset", "mm", cross .. "gcc")
			target:set("toolset", "mxx", cross .. (has_gxx and "g++" or "gcc"))
			target:set("toolset", "ar", cross .. "ar")
			target:set("toolset", "ex", cross .. "ar")
			target:set("toolset", "strip", cross .. "strip")
		end

		for _, toolchain in ipairs(target:toolchains()) do
			toolchain:check()
		end

		local flags = {
			"-EL", "-msoft-float", "-mstrict-align", "-mno-mt", "-mno-abicalls",
			target:values("psx.no_gpopt") and "-mgpopt" or "-mno-gpopt", "-G8",

			"-ffreestanding", "-nostdlib", "-fno-pic", "-fno-PIC",
			"-fno-fat-lto-objects", "-fomit-frame-pointer", "-fno-stack-protector",

			"-fsigned-char", "-fno-common", "-fzero-initialized-in-bss",
			"-fstrict-aliasing", "-fstrict-overflow", "-fno-exceptions",

			-- since floats have to be emulated, might as well optimize them as much as possible
			"-ffast-math", "-ffp-contract=fast",

			-- splitting functions and data into sections allows the linker to garbage collect them
			"-ffunction-sections", "-fdata-sections",

			"-nodefaultlibs", "-no-pie", "-Wl,--gc-sections",
		}

		if is_mode("debug") then
			table.append(flags, "-g", "-Og")
			target:add("defines", "DEBUG")
		else
			table.append(flags, "-O2")
			target:add("defines", "NDEBUG")
		end

		prepend(target, {"cxxflags"}, {"-fno-rtti", "-fno-unwind-tables", "-fno-threadsafe-statics", "-fno-use-cxa-atexit"})
		target:add("defines", "__STDC_NO_ATOMICS__")

		if target:get("kind") == "binary" then
			if not target:values("psx.no_crt") then
				target:add("files", path.join(psx_dir, "files/crt/*.S"), path.join(psx_dir, "files/crt/*.s"))
			end
			if not target:values("psx.no_ldscript") then
				target:add("files", path.join(psx_dir, "files/psx.ld"))
			end
		end

		if using_clang then
			prepend_clang_flags(os, target, cross, has_gxx)
			prepend(target, {"cxflags", "ldflags", "asflags"}, flags)
		else
			-- compile_commands must use clang commands, so when using gcc, disable compile_commands for this target
			target:set("policy", "generator.compile_commands", false)

			-- and add an impostor clangified version of the target which will generate compile_commands on its behalf
			local clangified = target:clone()
			clangified:name_set(target:name() .. "-clangified")
			clangified:set("kind", "headeronly") -- headeronly makes xmake ignore building it, while still logging the commands
			clangified:set("toolset", "cc", "clang")
			clangified:set("toolset", "mm", "clang")
			clangified:set("toolset", "cxx", "clang++")
			clangified:set("toolset", "mxx", "clang++")
			clangified:set("toolset", "ld", "clang")
			clangified:set("policy", "generator.compile_commands", true)
			clangified:set("policy", "build.c++.modules", true)
			prepend_clang_flags(os, clangified, cross, has_gxx)
			prepend(target, {"cxflags", "ldflags", "asflags"}, flags)
			import("core.project.project")
			project.target_add(clangified)
			for _, toolchain in ipairs(clangified:toolchains()) do
				toolchain:check()
			end

			-- gcc-only flags
			table.append(flags,
				"-march=r3000", "-mtune=r3000", "-fdelayed-branch",
				"-mgp32", -- mips64 toolchains would default to 64-bit without this
				"-mno-llsc", "-fallow-store-data-races", "-mno-fp-exceptions",
				"-falign-functions=16:8", "-falign-loops=16:8", "-fno-align-labels", "-fno-align-jumps",
				"-flimit-function-alignment",
				"--param=l1-cache-line-size=0", "--param=l1-cache-size=0", "--param=l2-cache-size=0",
				"-mno-shared",

				"-mno-extern-sdata", "-membedded-data",

				-- optimization
				"-Wa,--strip-local-absolute", "-fsection-anchors", "-fno-semantic-interposition"
			)

			-- these are objective improvements, but obviously it breaks the abi
			-- so if your code depends on the classic o32 abi for some reason, set psx.abi to o32 to change it back
			local abi = target:values("psx.abi")
			if abi == "o32" then
				table.append(flags, "-mabi=32", "-fno-reg-struct-return")
			else
				table.append(flags, "-mabi=eabi", "-freg-struct-return", "-fcall-saved-k0", "-fcall-saved-k1")
			end

			-- dev mode will be better optimized than debug, but skip the most aggressive optimizations to compile faster
			if is_mode("debug") or is_mode("dev") then
				table.append(flags,
					"-mdivide-breaks" -- all divisions will check for division by zero
				)
			else
				table.append(flags,
					"-mno-check-zero-division",
					-- experiment zone
					"-fisolate-erroneous-paths-attribute",
					"-free", "-fpredictive-commoning", "-fsched-pressure", "-fsched-spec-load",
					"-ftree-pre", "-ftree-partial-pre",
					"-fira-loop-pressure", "-ftree-loop-im", "-ftree-loop-distribution", "-floop-interchange",
					"-fno-prefetch-loop-arrays",
					"-fweb", "-frename-registers", "-fgcse-sm", "-fgcse-las", "-fgcse-after-reload",
					"-fipa-pta", "-fipa-icf", "-fipa-bit-cp", "-fipa-vrp",
					"-freorder-blocks-algorithm=simple", "-freorder-blocks-and-partition", "-freorder-functions",
					"-ffold-mem-offsets",
					"-fmodulo-sched", "-fmodulo-sched-allow-regmoves",
					"-fdevirtualize-speculatively",
					"-fschedule-insns", "-fschedule-insns2", "-fsched-pressure",
					"-fira-hoist-pressure", "-fira-loop-pressure", "-fno-ira-share-save-slots",
					"-fsched2-use-superblocks" -- apparently experimental!
				)
				if gcc_major_version and gcc_major_version >= 15 then
					table.append(flags,
						"-favoid-store-forwarding",
						"-fipa-reorder-for-locality",
						"-fext-dce"
					)
				end
			end

			prepend(target, {"cxflags", "ldflags", "asflags"}, flags)
			prepend(target, {"cxxflags"}, {"-fdeclone-ctor-dtor"})
			prepend(target, {"defines"}, {"SCRATCHPAD='[[gnu::section(\".scratchpad\")]]'"})
		end
	end)
end)
