import("lib.detect.find_program")
import("lib.detect.find_file")
import("lib.detect.has_flags")
import("core.cache.memcache")
import("core.base.option")
import("core.project.project")

local psx_dir = os.scriptdir()

local warned_about_gcc_not_found = false
local warned_about_llvm = false

local function print_for(target, msg)
	cprint("${magenta bright}psx: <" .. target:name() .. "> ${clear}" .. tostring(msg))
end

local function warn(msg)
	cprint("${magenta bright}psx: ${yellow bright}warning: " .. tostring(msg))
end

local function raise_for(target, msg)
	raise("${magenta bright}psx: <" .. target:name() .. "> ${clear}" .. tostring(msg))
end

local function get_any_config(target, name)
	local value = target:values(name) or os.getenv(name:upper()) or get_config(name)
	if value ~= "" then
		return value
	end
end

-- detect an appropriate gcc from the system
local function detect_gcc()
	local env_path = os.getenv("PATH")
	local gcc = memcache.get2("psx", "detected_gcc", env_path)
	if gcc then
		if option.get("verbose") then
			print("[verbose] gcc detection was cached")
		end
	else
		-- check for a few known toolchains first
		local known = {
			"mipsel-sony-psx-gcc", -- hypothetical patched gcc with special tuning (following upstreamed mipsel-sony-psp naming convention)
			"mipsel-psx-elf-gcc", -- alternate possible name (following the weirder mips64r5900el-ps2-elf/mipsel-ps2-elf naming convention)
			"mipsel-none-elf-gcc", -- generic toolchain for mipsel, likely self built and thus up to date
			"mips64-linux-gnu-gcc", -- distributed by Fedora, works the same as mipsel-none-elf but cannot provide a libgcc
		}
		for i = 1, #known do
			local checked_gcc = known[i]
			if find_program(checked_gcc) then
				gcc = checked_gcc
				break
			end
		end

		-- when at a loss, just search for any mips gcc
		if not gcc then
			gcc = find_file("mips*-gcc", path.splitenv(env_path))
			assert(find_program(gcc)) -- sanity check
		end

		memcache.set2("psx", "detected_gcc", env_path, gcc)
	end
	return gcc
end

local function probe_gcc_info(target, gcc)
	local mtime = os.mtime(find_program(gcc))
	local gcc_info = memcache.get2("psx", "gcc_info", gcc)
	if gcc_info and gcc_info.mtime == mtime then
		if option.get("verbose") then
			print("[verbose] probed gcc info was cached")
		end
	else
		local prefix = assert(gcc:match("(.*)gcc[-.0-9]*$"))

		local version = assert(os.iorunv(gcc, {"-dumpversion"})):trim()
		local major_version = tonumber(version:match("^%d+"))
		if major_version < 16 then
			-- while GCC 14 recognizes C23, it doesn't fully support it (for example, #embed is missing)
			-- it's also supposed to support C++ modules, but it crashes all the time when trying to deal with them
			-- in my experience GCC 15 crashes often with modules, and also with LTO, but 16 is much more stable
			warn(gcc .. " is outdated (version " .. version .. "), so modern C and C++ features may be missing or broken")
		end

		local gxx = prefix .. "g++"
		if not find_program(gxx) then
			gxx = nil
			warn("could not find " .. gxx .. ", C++ may not work properly")
		end

		local arch
		if has_flags(gcc, "-mabi=32 -march=psx", {program = gcc}) then
			arch = "psx"
		elseif has_flags(gcc, "-mabi=32 -march=mips1", {program = gcc}) then
			arch = "mips1"
		else
			raise_for(target, "no appropriate -march option supported by " .. gcc .. " (psx or mips1 is required)")
		end

		gcc_info = {
			mtime = mtime,
			version = version,
			major_version = major_version,
			prefix = prefix,
			gcc = gcc,
			gxx = gxx,
			arch = arch,
		}
		memcache.set2("psx", "gcc_info", gcc, gcc_info)
	end
	return gcc_info
end

local function probe_gcc_include_paths(gcc_info)
	local gcc_include_paths = memcache.get2("psx", "gcc_include_paths", gcc_info.gcc)
	if gcc_include_paths and gcc_include_paths.mtime == gcc_info.mtime then
		if option.get("verbose") then
			print("[verbose] probed gcc include paths were cached")
		end
	else
		local _, stderr = os.iorunv(gcc_info.gxx or gcc_info.gcc, {"-ffreestanding", "-xc++", path.join(psx_dir, "files/empty.c"), "-E", "-Wp,-v"})
		gcc_include_paths = {}
		for _, line in ipairs(stderr:split("\n")) do
			if line:startswith(" ") then
				gcc_include_paths[#gcc_include_paths + 1] = line:trim()
			end
		end
		gcc_include_paths.mtime = gcc_info.mtime
		memcache.set2("psx", "gcc_include_paths", gcc_info.gcc, gcc_include_paths)
	end
	return gcc_include_paths
end

local function add_flags(object, flags, opt)
	object:add("cxflags", flags, opt)
	object:add("asflags", flags, opt)
	object:add("ldflags", flags, opt)
end

local function finish_with_clang(toolchain, flags, arch, gcc_info)
	--add_flags(toolchain, {"--target=mipsel-none-elf", "-nostdlib", "-march=" .. arch}, {force = true})
	-- that doesn't seem to allow the rest of the flags to be auto detected, so embed the flags into the command

	local forced_flags = "--target=mipsel-none-elf -nostdlib -march=" .. arch
	if gcc_info then
		forced_flags = forced_flags .. " -fno-integrated-as -B" .. gcc_info.prefix .. " -fuse-ld=bfd -Wl,--noinhibit-exec"
	end

	toolchain:set("toolset", "cc", "clang " .. forced_flags)
	toolchain:set("toolset", "cxx", "clang++ " .. forced_flags)
	toolchain:set("toolset", "ld", "clang++ " .. forced_flags)
	toolchain:set("toolset", "sh", "clang++ " .. forced_flags)
	toolchain:set("toolset", "mm", "clang " .. forced_flags)
	toolchain:set("toolset", "mxx", "clang++ " .. forced_flags)
	toolchain:set("toolset", "as", "clang " .. forced_flags)

	add_flags(toolchain, flags)
	add_flags(toolchain, "-flto=none")

	-- clang's freestanding support is poor, so make it use gcc's standard headers if available (cached)
	-- TODO: try using the freestanding C++ STL and check if it needs a similar workaround
	if gcc_info then
		toolchain:add("cxflags", "-nostdinc")
		toolchain:add("cxxflags", "-nostdinc++")
		local paths = probe_gcc_include_paths(gcc_info)
		for i = 1, #paths do
			toolchain:add("cxflags", "-isystem " .. paths[i])
		end
	elseif table.contains(toolchain:get("cxflags"), "-mabi=eabi") then
		add_flags(toolchain, {"-fdollars-in-identifiers", "-D$ta0=$8", "-D$ta1=$9", "-D$ta2=$10", "-D$ta3=$11"})
	else
		add_flags(toolchain, {"-fdollars-in-identifiers", "-D$ta0=$12", "-D$ta1=$13", "-D$ta2=$14", "-D$ta3=$15"})
	end
end

local function generate_ide_target(target, flags, using_clang, gcc_info)
	target:set("policy", "generator.compile_commands", false)

	-- the impostor will generate compile_commands on the original target's behalf
	local ide = target:clone()
	ide:name_set(target:name() .. "-ide")
	ide:set("kind", "headeronly") -- headeronly makes xmake ignore building it, while still logging the commands
	ide:set("policy", "generator.compile_commands", true)
	ide:add("defines", "IDE")
	ide:set("run", nil)

	if not using_clang then
		ide:set("toolchains", "clang")
		local ide_toolchain = ide:toolchain("clang")
		finish_with_clang(ide_toolchain, flags, "mips1", gcc_info)
		ide_toolchain:check()
	end

	project.target_add(ide)
end

local o32_flags = {"-mabi=32", "-fno-reg-struct-return"}
local eabi_flags = {"-mabi=eabi", "-freg-struct-return"}
local fast_flags = {"-mabi=eabi", "-freg-struct-return", "-fcall-saved-k0", "-fcall-saved-k1"}

local all_abi_flags = {
	o32 = o32_flags,
	eabi = eabi_flags,
	fast = fast_flags,
}

function main(target)
	target:set("targetdir", "$(builddir)/psx/$(mode)") -- turns build/psx/mipsel/release into build/psx/release, because psx should imply mipsel

	local target_kind = target:kind()
	if target_kind == "binary" then
		target:set("extension", ".elf")
		if not target:values("psx.no_crt") then
			target:add("files", path.join(psx_dir, "files/crt/*.S"), path.join(psx_dir, "files/crt/*.s"))
		end
		if not target:values("psx.no_ldscript") then
			target:add("files", path.join(psx_dir, "files/psx.ld"))
		end
	end

	local is_project_generator = os.getenv("XMAKE_IN_PROJECT_GENERATOR") ~= nil

	local gcc
	local using_clang = is_project_generator

	local specified_cross = get_any_config(target, "cross") or get_any_config(target, "cc")
	if specified_cross and specified_cross ~= "none" then
		if specified_cross:endswith("-") then
			gcc = specified_cross .. (specified_cross:endswith("-") and "gcc" or "-gcc")
			if not find_program(gcc) then
				raise("specified cross compiler " .. gcc .. " was not found")
			end
		elseif specified_cross:endswith("gcc") then
			gcc = specified_cross
			if not find_program(gcc) then
				raise("specified cross compiler " .. gcc .. " was not found")
			end
		elseif specified_cross:endswith("clang") then
			clang = specified_cross
			using_clang = true
			if specified_cross ~= "clang" then
				raise("specified clang must simply be 'clang'")
			end
		else
			raise("unrecognized '" .. specified_cross .. "' was specified as the cross compiler (must be a gcc prefix, gcc, or clang)")
		end
	end

	if is_project_generator then
		using_clang = true
	end
	-- when no gcc is otherwise specified, detect one (unless cross is set to none)
	if not gcc and specified_cross ~= "none" then
		gcc = detect_gcc()
	end

	if not gcc and not using_clang then
		if find_program("clang") then
			if specified_cross ~= "none" and not warned_about_gcc_not_found then
				warn("could not find an appropriate gcc, falling back to clang (try installing an up to date mipsel, mips, or mips64 gcc toolchain)")
				warned_about_gcc_not_found = true
			end
			using_clang = true
		else
			warn("could not find an appropriate compiler (try installing an up to date mipsel, mips, or mips64 gcc toolchain, or experimentally clang)")
		end
	end

	local is_debug = is_mode("debug")
	local flags = {
		"-EL", "-msoft-float", "-mno-abicalls", "-mno-mt", "-D__STDC_NO_ATOMICS__",
		"-ffreestanding", "-nostdlib", "-nodefaultlibs",
		target:values("psx.no_gpopt") and "-mno-gpopt" or "-mgpopt", "-G8",

		"-fno-pic",
		"-fno-fat-lto-objects", "-fomit-frame-pointer", "-fno-stack-protector",

		"-fno-common", "-fzero-initialized-in-bss",
		"-fstrict-aliasing", "-fstrict-overflow", "-fno-exceptions",

		-- since floats have to be emulated, might as well optimize them as much as possible
		"-ffast-math", "-ffp-contract=fast",

		-- splitting functions and data into sections allows the linker to garbage collect them
		"-ffunction-sections", "-fdata-sections",
		"-Wl,--gc-sections",

		"-g", -- always generate debug symbols, because they'll never be included in the psexe anyway
		is_debug and "-Og" or "-O2",
		is_debug and "-DDEBUG" or "-DNDEBUG",
	} ---@type string[]

	if not target:values("psx.no_gpopt") then
		table.append(flags, "-membedded-data", "-mno-extern-sdata")
	end

	local gcc_info = gcc and probe_gcc_info(target, gcc)
	local clang_arch = "mips1"
	local toolchain
	if using_clang then
		target:set("toolchains", "clang")
		toolchain = target:toolchain("clang")

		if has_flags("clang", "--target=mipsel-none-elf -nostdlib -march=psx") then
			clang_arch = "psx"
		end
	else
		target:set("configvar", "cross", path.filename(gcc_info.prefix))
		target:set("toolchains", "cross")
		toolchain = target:toolchain("cross")
		toolchain:set("cross", gcc_info.prefix)
	end

	toolchain:add("cxxflags", "-fno-rtti", "-fno-unwind-tables", "-fno-threadsafe-statics", "-fno-use-cxa-atexit")
	toolchain:add("ldflags", "-no-pie", "-fno-rtti", "-fno-unwind-tables", "-fno-threadsafe-statics", "-fno-use-cxa-atexit")

	local abi = target:values("psx.abi") or "o32"
	local abi_flags = all_abi_flags[abi]
	if abi_flags then
		if not using_clang then
			add_flags(toolchain, abi_flags)
		end
	else
		raise_for(target, "unrecognized psx.abi setting '" .. abi .. "', must be one of: " .. table.concat(table.keys(all_abi_flags), ", "))
	end

	if using_clang then
		finish_with_clang(target, flags, is_project_generator and "mips1" or clang_arch, gcc_info)

		target:set("policy", "build.optimization.lto", false)

		if is_project_generator then
			target:add("defines", "IDE")
		else
			if not warned_about_llvm then
				if not gcc then
					warn("using clang without gcc, this might not work")
				end
				warn("LLVM's support for MIPS-I is experimental, performance will be worse, and LTO will be disabled!")
				warned_about_llvm = true
			end
			print_for(target, "using clang, -march=" .. clang_arch)

			-- when using clang, the impostor is only to get the IDE define set
			generate_ide_target(target, flags, using_clang, gcc_info)
		end
	else
		-- when using gcc, we need an impostor because compile_commands must use clang commands
		generate_ide_target(target, flags, using_clang, gcc_info)

		-- gcc-only flags
		table.append(flags,
			"-march=" .. gcc_info.arch, "-mgp32",
			"-mno-llsc", "-fallow-store-data-races", "-mno-fp-exceptions",
			"-falign-functions=16:8", "-falign-loops=16:8", "-fno-align-labels", "-fno-align-jumps",
			"-flimit-function-alignment",
			"--param=l1-cache-line-size=0", "--param=l1-cache-size=0", "--param=l2-cache-size=0",
			"-mno-shared",

			"-mno-extern-sdata", "-membedded-data",

			-- optimization
			"-Wa,--strip-local-absolute", "-fsection-anchors", "-fno-semantic-interposition"
		)

		-- dev mode will be better optimized than debug, but skip the most aggressive optimizations to compile faster
		if is_mode("debug") or is_mode("dev") then
			table.append(flags,
				"-mdivide-breaks" -- all divisions will check for division by zero
			)
		else
			table.append(flags,
				"-mno-check-zero-division",
				-- experiment zone
				"-free", "-fpredictive-commoning", "-fsched-pressure", "-fsched-spec-load",
				"-ftree-pre", "-ftree-partial-pre",
				"-fira-loop-pressure", "-ftree-loop-im",
				"-fno-prefetch-loop-arrays",
				"-fweb", "-frename-registers", "-fgcse-sm", "-fgcse-las", "-fgcse-after-reload",
				"-fipa-pta", "-fipa-icf", "-fipa-bit-cp", "-fipa-vrp",
				"-freorder-blocks-algorithm=simple", "-freorder-blocks-and-partition",
				"-ffold-mem-offsets",
				"-fmodulo-sched", "-fmodulo-sched-allow-regmoves",
				"-fdevirtualize-speculatively",
				"-fschedule-insns", "-fschedule-insns2", "-fsched-pressure",
				"-fira-hoist-pressure", "-fira-loop-pressure", "-fno-ira-share-save-slots",
				"-fsched2-use-superblocks" -- apparently experimental!
			)
			if gcc_info.major_version >= 15 then
				table.append(flags,
					"-favoid-store-forwarding",
					"-fipa-reorder-for-locality",
					"-fext-dce"
				)
			else
				table.append(flags, "-freorder-functions")
			end

			toolchain:add("cxxflags", "-fdeclone-ctor-dtor")
			toolchain:add("ldflags", "-fdeclone-ctor-dtor")

			print_for(target, "using " .. gcc_info.prefix .. "gcc, -march=" .. gcc_info.arch)
		end
	end

	-- the clang and gcc paths merge again here

	add_flags(toolchain, flags)
	toolchain:check()
end
