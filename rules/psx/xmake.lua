rule("psx", function()
	on_load(function(target)
		target:set("plat", "psx")
		target:set("arch", "mipsel")
	end)

	before_config("before_config")
	on_run("on_run")
end)
