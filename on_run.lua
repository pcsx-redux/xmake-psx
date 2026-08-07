import("lib.detect.find_program")

function main(target)
	if target:kind() ~= "binary" then
		return nil
	end
	local redux = get_config("pcsx-redux")
	if not redux or redux == "auto" or redux == "" then
		redux = os.getenv("PCSX_REDUX")
		if redux then
			redux = assert(find_program(redux), "specified pcsx-redux path (from PCSX_REDUX env var) is invalid: " .. redux)
		else
			redux = find_program("pcsx-redux")
			if not redux then
				local env_home = os.getenv("HOME")
				if env_home then
					import("lib.detect.find_file")
					local appimages_dir = path.join(env_home, "AppImages")
					local applications_dir = path.join(env_home, "Applications")
					local downloads_dir = path.join(env_home, "Downloads")
					local search_paths = {appimages_dir, applications_dir, downloads_dir, "$(env PATH)"}
					redux = find_file("pcsxredux*", search_paths)
						or find_file("PCSX-Redux*", search_paths)
						or find_file("pcsx-redux*", search_paths)
				end
			end
		end
		assert(redux, "could not find pcsx-redux, please use 'xmake f --pcsx-redux=...' or PCSX_REDUX=...")
	else
		redux = assert(find_program(redux), "specified pcsx-redux path (from --pcsx-redux=... option) is invalid: " .. redux)
	end
	print("pcsx-redux located at: " .. redux)

	import("core.project.config")
	local redux_dir = path.join(config.builddir(), ".gens", "pcsx-redux-config")
	os.mkdir(redux_dir)

	os.runv(redux, {
		"-8mb",
		"-interpreter",
		"-softgpu",
		"-debugger",
		"-fastboot",
		"-gdb",
		"-run",
		"-exe", target:targetfile(),
		"-portable", redux_dir,
	})
end
