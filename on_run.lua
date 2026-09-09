import("lib.detect.find_program")
import("core.project.config")
import("core.base.option")
import("core.base.process")

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
					local search_paths = {
						"$(env PATH)",
						path.join(env_home, "AppImages"),
						path.join(env_home, "Applications"),
						path.join(env_home, "Downloads"),
					}
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
	cprint("${magenta bright}psx: <" .. target:name() .. "> ${clear}running with pcsx-redux (" .. redux .. ")")

	local redux_config_dir = path.join(config.builddir(), ".gens", "pcsx-redux-config")
	os.mkdir(redux_config_dir)

	local args = option.get("arguments") or {}
	local detach = table.contains(args, "--detach")
	local gdb = table.contains(args, "--gdb")

	local redux_process = process.openv(redux, {
		"-softgpu",
		"-8mb",
		"-interpreter",
		"-debugger",
		"-gdb",
		"-gdb-port", get_config("gdb-port"),
		"-fastboot",
		"-exe", target:targetfile(),
		"-portable", redux_config_dir,
		"-run",
	}, {detach = true})
	if gdb then
		os.execv("gdb", {target:targetfile(), "-ex", "set remotetimeout 5", "-ex", "target remote localhost:" .. get_config("gdb-port")})
	elseif not detach then
		redux_process:wait()
	end
	redux_process:close()
end
