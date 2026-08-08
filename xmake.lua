add_moduledirs("modules")

option("pcsx-redux", {default = "auto"})
option("gdb-port", {default = "3333"})

rule("psx", function()
	on_load(function(target)
		target:set("plat", "psx")
		target:set("arch", "mipsel")
	end)

	before_config("before_config")
	on_run("on_run")
end)

-- you can either add the psx.psexe rule into a project directly, or create a separate target for it
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

-- editor support

task("zed", function()
	set_category("plugin")
	set_menu({
		description = "Generate debug configurations for Zed (using PCSX-Redux)",
		options = {
			{"y", "yes", "k", nil, "Always overwrite"},
		},
	})
	on_run("zed")
end)

-- override the autoupdate rule to avoid issues
rule("plugin.compile_commands.autoupdate", function()
	set_kind("project")

	after_build(function()
		import("core.project.config")
		import("core.project.depend")
		import("core.project.project")
		import("core.base.task")

		local tmp_dir = path.join(config.builddir(), ".gens", "rules")
		local depend_file = path.join(tmp_dir, "plugin.compile_commands.autoupdate.d")
		local lock = io.openlock(path.join(tmp_dir, "plugin.compile_commands.autoupdate.lock"))
		if lock:trylock() then
			local sourcefiles = {}
			local out_dir, lsp

			for _, target in pairs(project.targets()) do
				table.join2(sourcefiles, target:sourcefiles(), target:headerfiles())
				local extraconf = target:extraconf("rules", "plugin.compile_commands.autoupdate")
				if extraconf then
					out_dir = extraconf.outputdir
					lsp = extraconf.lsp
				end
			end
			local function run()
                task.run("project", {kind = "compile_commands", outputdir = out_dir, lsp = lsp})
                print("compile_commands.json updated!")
            end
            local out_file = out_dir and path.join(out_dir, "compile_commands.json") or "compile_commands.json"
            if not os.exists(out_file) then
                run()
            else
				local all_files = table.join(project.allfiles(), config.filepath())
				table.sort(all_files)
				depend.on_changed(run, {
					dependfile = depend_file,
					files = all_files,
				})
			end
			lock:close()
		end
	end)
end)
