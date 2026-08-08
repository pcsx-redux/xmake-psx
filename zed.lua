import("core.project.project")
import("core.project.task")

local zed_debug_prologue = [[
// Project-local debug tasks
//
// For more documentation on how to configure debug tasks,
// see: https://zed.dev/docs/debugger
[
]]
local zed_debug_pattern = [[
	{
		"label": "Debug %s with PCSX-Redux",
		"request": "attach",
		"adapter": "GDB",
		"target": "localhost:%s",
		"program": "%s",
		"build": {
			"command": "xmake run %s --detach",
		},
	},
]]

function main()
	task.run("config")

	local zed_dir = path.join(os.projectdir(), ".zed")
	os.mkdir(zed_dir)

	local zed_debug_file = path.join(zed_dir, "debug.json")
	if os.exists(zed_debug_file) then
		if utils.confirm({default = true, description = "your project already has debug configurations for Zed, overwrite them?"}) then
			os.rm(zed_debug_file)
		else
			print("Canceled")
			return
		end
	end

	local value = zed_debug_prologue
	for name, target in pairs(project.targets()) do
		if target:kind() == "binary" and target:rule("psx") then
			local elf = target:targetfile()
			value = value .. zed_debug_pattern:format(name, get_config("gdb-port"), elf, name)
		end
	end
	value = value .. "]"

	io.writefile(zed_debug_file, value)
end
