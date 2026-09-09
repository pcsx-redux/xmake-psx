task("asm", function()
	set_category("plugin")
	set_menu({
		description = "Show the assembly for a function",
		options = {
			{nil, "symbol", "vs", nil, "Symbol to disassemble"},
			{"t", "target", "kv", nil, "Target(s) to use"},
			{nil, "objdump", "kv", nil, "objdump to use"},
		},
	})
	on_run("asm")
end)

task("zed", function()
	set_category("plugin")
	set_menu({
		description = "Generate debug configurations for Zed (using PCSX-Redux)",
		options = {},
	})
	on_run("zed")
end)
