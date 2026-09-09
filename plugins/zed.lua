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
		import("core.project.project")
		import("ide_gen")

		ide_gen("debug configurations for Zed", ".zed/debug.json", function()
			local value = zed_debug_prologue
			for name, target in pairs(project.targets()) do
				if target:kind() == "binary" and target:plat() == "psx" then
					local elf = target:targetfile()
					value = value .. zed_debug_pattern:format(name, get_config("gdb-port"), elf, name)
				end
			end
			return value .. "]"
		end)
end
