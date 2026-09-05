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
