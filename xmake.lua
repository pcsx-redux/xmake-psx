add_moduledirs("modules")

rule("psx", function()
	before_config("before_config")
end)

-- you can add the psx.psexe rule into a build target directly, or create a separate target for it

rule("psx.psexe", function()
	on_load(function(target)
		target:set("kind", "binary")
		target:set("plat", "psx")
		target:set("arch", "mipsel")
	end)

	after_config(function(target)
		import("psexe")
		psexe.after_config(target)
	end)

	after_link(function(target)
		import("psexe")
		psexe.after_link(target)
	end)
end)

rule("psx.psexe._standalone_target", function()
	on_build(function(target)
		import("psexe")
		psexe.on_build(target)
	end)
end)
