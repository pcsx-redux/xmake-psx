-- clang-only flags
-- for some reason, this function can't see os.iorunv, so i passed it through an argument
local function add_clang_flags_to(target, cross, iorunv)
	local flags = {
		"--target=mipsel-none-elf", "-march=mips1", "-G32", "-mfloat-abi=soft",
		"-B" .. cross .. "-", "-fno-integrated-as",
		"-falign-loops=1", "-falign-functions=16",
		"-nostdinc", "-nostdinc++",
		-- clang doesn't support -mdivide-breaks, it can only use the 'teq' instruction which is not supported on PS1
		"-mno-check-zero-division",
	}
	for _, value in ipairs(flags) do
		target:add("cxflags", value, {force = true})
		target:add("ldflags", value, {force = true})
	end
	-- clang appears to assume loads from scratchpad values are always 0?
	target:add("defines", "SCRATCHPAD=")

	-- clang's freestanding support is poor, so make it use gcc's standard headers
	local _, stderr = iorunv(cross .. "-g++", {"-ffreestanding", "-xc++", "/dev/null", "-E", "-Wp,-v"})
	for _, line in ipairs(stderr:split("\n")) do
		if line:startswith(" ") then
			target:add("sysincludedirs", line:trim())
		end
	end
end

local parent_dir = path.directory(os.scriptdir())

rule("psx", function()
	before_config(function(target)
		target:set("plat", "psx")
		target:set("arch", "mipsel")
		target:set("extension", ".elf")

		import("lib.detect.find_program")
		local arch_possibilities = {"mipsel", "mips"}
		local vendor_possibilities = {"none", "linux", "unknown", ""}
		local abi_possibilities = {"elf", "gnu"}
		local cross
		for _, arch in ipairs(arch_possibilities) do
			for _, vendor in ipairs(vendor_possibilities) do
				for _, abi in ipairs(abi_possibilities) do
					local checked_cross
					if vendor == "" then -- account for the oddly named "mipsel-elf-gcc" toolchain i saw once
						checked_cross = arch .. "-" .. abi
					else
						checked_cross = arch .. "-" .. vendor .. "-" .. abi
					end
					if find_program(checked_cross .. "-gcc") then
						cross = checked_cross
						break
					end
				end
			end
		end
		if not cross then
			error("could not find an appropriate cross compiler toolchain, try installing mipsel-none-elf-gcc")
		end

		target:set("configvar", "cross", cross .. "-")
		target:set("toolchains", "cross")

		local using_clang = get_config("cc") == "clang" or os.getenv("CC") == "clang" or target:get("configvar").clang or os.getenv("XMAKE_IN_COMPILE_COMMANDS_PROJECT_GENERATOR")
		if using_clang then
			print("compiling with clang, backed by " .. cross .. " binutils")
			print("note that clang's support for mips1 is experimental!")
			target:set("toolset", "cc", "clang")
			target:set("toolset", "cxx", "clang++")
			target:set("toolset", "ld", "clang")
			target:set("toolset", "mm", "clang")
			target:set("toolset", "mxx", "clang++")
		else
			print("compiling with " .. cross .. "-gcc")
			target:set("toolset", "cc", cross .. "-gcc")
			target:set("toolset", "cxx", cross .. "-g++")
			target:set("toolset", "ld", cross .. "-gcc")
			target:set("toolset", "mm", cross .. "-gcc")
			target:set("toolset", "mxx", cross .. "-g++")
		end
		target:set("toolset", "as", cross .. "-gcc")
		target:set("toolset", "ar", cross .. "-ar")
		target:set("toolset", "ex", cross .. "-ar")
		target:set("toolset", "strip", cross .. "-strip")
		for _, toolchain in ipairs(target:toolchains()) do
			toolchain:check()
		end

		local main_flags = {
			"-ffreestanding", "-nostdlib",
			"-EL", "-G32", "-mgpopt", "-mno-mt",
			"-msoft-float",
			"-mstrict-align", "-fstrict-overflow",
			"-mno-extern-sdata", "-fno-common", "-fzero-initialized-in-bss", "-fno-pic", "-fno-PIC", "-mno-abicalls",

			"-fno-fat-lto-objects",
			"-fno-pic", "-fno-PIC", "-fsigned-char",
			"-static", "-fomit-frame-pointer", "-fno-stack-protector",
			"-fstrict-aliasing", "-fstrict-overflow",
			"-ffast-math", "-ffp-contract=fast",

			-- splitting into sections allows the linker to discard unused functions and data
			"-ffunction-sections", "-fdata-sections"
		}

		if is_mode("debug") then
			table.append(main_flags, "-g", "-Og", "-fno-inline")
			target:add("defines", "DEBUG")
		else
			table.append(main_flags, "-O2")
			target:add("defines", "NDEBUG")
		end

		target:add("defines", "__STDC_NO_ATOMICS__")
		target:add("cxxflags",
			"-fno-exceptions", "-fno-rtti", "-fno-unwind-tables", "-fno-threadsafe-statics", "-fno-use-cxa-atexit"
		)
		target:add("ldflags", "-nodefaultlibs", "-no-pie", "-Wl,--gc-sections", {force = true})
		target:add("asflags", "-xassembler-with-cpp", "-msoft-float", {force = true})

		target:add("files", path.join(parent_dir, "files/**.s"))
		target:add("ldflags", "-T " .. path.join(parent_dir, "files/psx.ld"), {force = true})
		if target:has_tool("ld", "clang") or target:has_tool("ld", "clang++") then
			target:add("ldflags", "-fuse-ld=lld", "-Wl,-mllvm,-mattr=+noabicalls", "-Wl,-mllvm,-mattr=+soft-float", {force = true})
		end

		if using_clang then
			add_clang_flags_to(target, cross, os.iorunv)
		else
			-- compile_commands must use clang commands
			-- so when using gcc, disable compile_commands for this target
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
			add_clang_flags_to(clangified, cross, os.iorunv)
			import("core.project.project")
			project.target_add(clangified)
			for _, toolchain in ipairs(clangified:toolchains()) do
				toolchain:check()
			end

			-- gcc-only flags
			table.append(main_flags,
				"-march=r3000", "-mtune=r3000", "-fdelayed-branch",
				"-fcall-used-k0", "-fcall-used-k1", "-freg-struct-return",
				"-mno-fp-exceptions", "-mno-llsc", "-fallow-store-data-races", "-mno-shared",
				"-Wa,--strip-local-absolute", "-fsection-anchors", "-fno-semantic-interposition",
				"-flimit-function-alignment", "-falign-functions=16:8", "-fno-align-labels", "-fno-align-jumps",
				"-falign-loops=16:8",
				"--param=l1-cache-line-size=0", "--param=l1-cache-size=0", "--param=l2-cache-size=0"
			)
			target:add("cxxflags", "-fdeclone-ctor-dtor")
			target:add("defines", "SCRATCHPAD='[[gnu::section(\".scratchpad\")]]'")
			if is_mode("debug") or is_mode("dev") then
				table.append(main_flags, "-mdivide-breaks")
			else
				table.append(main_flags,
					"-mno-check-zero-division",
					-- experiment zone
					"-favoid-store-forwarding",
					"-fisolate-erroneous-paths-attribute",
					"-free", "-fpredictive-commoning", "-fsched-pressure", "-fsched-spec-load",
					"-ftree-pre", "-ftree-partial-pre",
					"-fira-loop-pressure", "-ftree-loop-im", "-ftree-loop-distribution", "-floop-interchange",
					"-fno-prefetch-loop-arrays",
					"-fweb", "-frename-registers", "-fgcse-sm", "-fgcse-las", "-fgcse-after-reload",
					"-fipa-pta", "-fipa-icf", "-fipa-reorder-for-locality", "-fipa-bit-cp", "-fipa-vrp",
					"-freorder-blocks-algorithm=simple", "-freorder-blocks-and-partition", "-freorder-functions",
					"-ffold-mem-offsets",
					"-fmodulo-sched", "-fmodulo-sched-allow-regmoves",
					"-fdevirtualize-speculatively",
					"-fext-dce",
					"-fschedule-insns", "-fschedule-insns2", "-fsched-pressure",
					"-fira-hoist-pressure", "-fira-loop-pressure", "-fno-ira-share-save-slots",
					"-fsched2-use-superblocks" -- apparently experimental!
				)
			end
		end
		for _, v in ipairs(main_flags) do
			target:add("cxflags", v, {force = true})
			target:add("ldflags", v, {force = true})
		end
	end)

	after_link(function(target)
		local elf = target:targetfile()
		local psexe
		if elf:endswith(".elf") then
			psexe = elf:sub(1, -5)
		else
			psexe = elf
		end
		psexe = psexe .. ".psexe"
		os.runv("python", {path.join(parent_dir, "files/convertExecutable.py"), elf, psexe})
		print("converted into " .. psexe)
	end)
end)
