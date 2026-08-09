import("core.project.project")
import("core.project.task")
import("core.base.option")
import("lib.detect.find_program")
import("core.base.pipe")
import("core.base.tty")
import("core.base.colors")

local cached_pager, cached_pager_args

local function get_pager()
	if not cached_pager then
		if find_program("less") then
			cached_pager, cached_pager_args = "less", {"-R"}
		elseif find_program("more") then
			cached_pager, cached_pager_args = "more", {}
		end
	end
	return cached_pager, cached_pager_args
end

local function do_for_target(target, wanted_symbols, user_args)
	task.run("build", {target = target:name()})

	-- determine the objdump, letting the user override it
	local toolchain = target:toolchain("cross")
	local objdump = os.getenv("OBJDUMP") or option.get("objdump") or (toolchain and (toolchain:get("cross") .. "objdump") or "llvm-objdump")
	if not find_program(objdump) then
		raise("could not find " .. objdump)
	end
	local is_llvm_objdump = objdump:endswith("llvm-objdump")

	-- ensure the symbols even exist first
	-- -pjU means don't sort, output just plain symbol names, and skip undefined symbols
	local nm = objdump:match("(.*)objdump") .. "nm"
	local all_symbols = "\n" .. os.iorunv(nm, {"-pjU", target:targetfile()})
	for _, sym in ipairs(wanted_symbols) do
		if not all_symbols:match("\n" .. sym .. "[\r\n]") then
			print("skipping target '" .. target:name() .. "' because it doesn't have symbol '" .. sym .. "'")
			return false
		end
	end

	-- generate arguments for the objdump command
	-- -rwC means show relocations, wide output, and demangle symbol names
	local args = {target:targetfile(), "-rwC"}
	if is_llvm_objdump then
		table.append(args, "--triple=mipsel-none-elf", "--disassemble-symbols=" .. table.concat(wanted_symbols, ","))
	else
		for _, symbol in ipairs(wanted_symbols) do
			table.append(args, "--disassemble=" .. symbol)
		end
	end
	table.join2(args, user_args)

	-- try to match xmake's own conditions for coloring
	if tty.has_color8() and colors.theme():name() ~= "plain" then
		if is_llvm_objdump then
			table.append(args, "--disassembler-color=on")
		else
			table.append(args, "--disassembler-color=on", "--visualize-jumps=color")
		end
	end

	print("running: " .. objdump .. " " .. os.args(args))

	-- try to page the output nicely, but only when invoked manually in a terminal
	if io.isatty() then
		local stdout = os.iorunv(objdump, args)
		if not stdout then
			return false
		end

		local pager, pager_args = get_pager()
		if pager then
			local read_pipe, write_pipe = pipe.openpair()
			write_pipe:write(stdout)
			write_pipe:close()
			os.execv(pager, pager_args, {stdin = read_pipe})
		end
	else
		if not os.execv(objdump, args) then
			return false
		end
	end

	return true
end

function main()
	local wanted_target = option.get("target")
	local wanted_symbols = {}
	local user_args = {}

	-- a bit janky, the first arg must be a symbol, but then the user can add flags directly to objdump
	for _, arg in ipairs(option.get("symbol")) do
		if arg:startswith("-") then
			table.append(user_args, arg)
		else
			table.append(wanted_symbols, arg)
		end
	end

	if not wanted_symbols or #wanted_symbols == 0 then
		print("no symbols were requested")
		return
	end

	task.run("config")

	if wanted_target and wanted_target ~= "" then
		-- if the user specified a target, do that
		local target = project.target(wanted_target)
		if not target then
			raise("no such target: " .. wanted_target)
		end
		do_for_target(target, wanted_symbols, user_args)
	else
		-- if the user did not specify, try every applicable target until one works, prioritizing linked binaries
		for _, target in pairs(project.targets()) do
			if target:plat() == "psx" and target:kind() == "binary" and target:targetfile():endswith(".elf") then
				if do_for_target(target, wanted_symbols, user_args) then
					return
				end
			end
		end
		for _, target in pairs(project.targets()) do
			if target:plat() == "psx" and target:kind() == "static" then
				if do_for_target(target, wanted_symbols, user_args) then
					return
				end
			end
		end
		print("these symbols were not found in any target")
	end
end
