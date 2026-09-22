import("core.project.project")
import("core.project.task")
import("core.base.option")

function main()
	task.run("config")

	local target_name = option.get("target")
	local target
	if target_name and target_name ~= "" then
		target = project.target(target_name)
		assert(target, "target not found: " .. target_name)
		assert(target:plat() == "psx", "target is not for psx: " .. target_name)
		assert(target:kind() == "binary", "target is not executable: " .. target_name)
		assert(target:targetfile():endswith(".elf"), "target does not output an ELF file: " .. target_name)
	else
		-- if the user did not specify, pick the first applicable target
		for i, v in pairs(project.targets()) do
			if v:plat() == "psx" and v:kind() == "binary" and v:targetfile():endswith(".elf") then
				target_name = i
				target = v
				break
			end
		end
		assert(target, "could not find an executable psx target")
	end

	task.run("build", {target = target:name()})

	local gdb_port = option.get("gdb-port")
	if not gdb_port or gdb_port == "default" or gdb_port == "" then
		gdb_port = get_config("gdb-port")
		if not gdb_port or gdb_port == "default" or gdb_port == "" then
			gdb_port = "3333"
		end
	end

	os.execv("gdb", {target:targetfile(), "-ex", "set remotetimeout 5", "-ex", "target remote localhost:" .. gdb_port})
end
