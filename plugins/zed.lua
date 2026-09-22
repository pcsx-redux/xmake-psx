local zed_debug_prologue = [[
// Project-local debug tasks
//
// For more documentation on how to configure debug tasks,
// see: https://zed.dev/docs/debugger
[
]]
local zed_debug_pattern = [[
	{
		"label": "Attach GDB on port %s for %s",
		"request": "attach",
		"adapter": "GDB",
		"target": "localhost:%s",
		"program": "%s",
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
				local gdb_port = get_config("gdb-port")
				if gdb_port == "auto" or gdb_port == "" then
					gdb_port = "3333"
				end
				value = value .. zed_debug_pattern:format(gdb_port, name, gdb_port, elf)
			end
		end
		return value .. "]"
	end)
end
