import("core.project.project")
import("core.project.task")
import("core.base.option")
import("lib.detect.find_program")
import("human")

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

	if human.color then
		if is_llvm_objdump then
			table.append(args, "--disassembler-color=on")
		else
			table.append(args, "--disassembler-color=on", "--visualize-jumps=color")
		end
	end

	return human.execv_paged(objdump, args)
end

function main()
	local wanted_target_name = option.get("target")
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

	if wanted_target_name and wanted_target_name ~= "" then
		-- if the user specified a target, do that
		local target = project.target(wanted_target_name)
		if not target then
			raise("no such target: " .. wanted_target_name)
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
