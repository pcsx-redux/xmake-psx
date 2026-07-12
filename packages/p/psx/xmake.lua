package("psx", function()
	set_kind("binary")
	add_deps("python")

	on_install(function(package)
		os.cp(path.join(os.scriptdir(), "files"), path.join(package:installdir(), "files"))
	end)
end)
