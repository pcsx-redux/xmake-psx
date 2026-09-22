import("core.project.project")
import("core.project.config")
import("core.base.option")
import("core.base.process")
import("lib.detect.find_program")

local function find_emu(must, name, patterns)
	local emu = get_config(name)
	local env_name = name:upper():gsub("-", "_")
	if not emu or emu == "default" or emu == "" then
		emu = os.getenv(name)
		if emu then
			emu = assert(find_program(emu), "specified " .. name .. " path (from " .. env_name .. " env var) is invalid: " .. emu)
		else
			emu = find_program("pcsx-redux")
			if not emu then
				local env_home = os.getenv("HOME")
				if env_home then
					import("lib.detect.find_file")
					local search_paths = {
						"$(env PATH)",
						path.join(env_home, "AppImages"),
						path.join(env_home, "Applications"),
						path.join(env_home, "Downloads"),
						path.join(env_home, "Desktop"),
					}
					for _, pattern in ipairs(patterns) do
						emu = find_file(pattern, search_paths)
						if emu then
							break
						end
					end
				end
			end
		end
		if not emu then
			if must then
				raise("could not find " .. name .. ", please use 'xmake f --" .. name .. "=...' or '" .. env_name .. "=... xmake run'")
			else
				return
			end
		end
	else
		emu = assert(find_program(emu), "specified " .. name .. " path (from --" .. name .. " option) is invalid: " .. emu)
	end
	return emu
end

function find_pcsx_redux(must)
	return find_emu(must, "pcsx-redux", {"pcsxredux*", "PCSX-Redux*", "pcsx-redux*"})
end

local function try_redux(must, target, args, emu)
	if not emu then
		emu = find_pcsx_redux(must)
		if not emu then
			return
		end
	end
	cprint("${magenta bright}psx: <" .. target:name() .. "> ${clear}running with pcsx-redux (" .. emu .. ")")

	local redux_config_dir = path.join(config.builddir(), ".gens", "pcsx-redux-config")
	os.mkdir(redux_config_dir)

	local detach = table.contains(args, "--detach") or table.contains(args, "-d")
	local gdb = table.contains(args, "--gdb") or table.contains(args, "-g")
	local gdb_port = get_config("gdb-port")
	if not gdb_port or gdb_port == "default" or gdb_port == "" then
		gdb_port = "3333"
	end

	local process = process.openv(emu, {
		"-softgpu",
		"-8mb",
		"-interpreter",
		"-debugger",
		"-gdb",
		"-gdb-port", gdb_port,
		"-fastboot",
		"-exe", target:targetfile(),
		"-portable", redux_config_dir,
		"-run",
	}, {detach = detach or gdb})
	if gdb then
		os.execv("gdb", {target:targetfile(), "-ex", "set remotetimeout 5", "-ex", "target remote localhost:" .. gdb_port})
	elseif not detach then
		process:wait()
	end
	process:close()
	return true
end

function find_duckstation(must)
	return find_emu(must, "duckstation", {"duckstation*", "DuckStation*"})
end

local function try_duckstation(must, target, args, emu)
	if not emu then
		emu = find_duckstation(must)
		if not emu then
			return
		end
	end
	cprint("${magenta bright}psx: <" .. target:name() .. "> ${clear}running with duckstation (" .. emu .. ")")

	local detach = table.contains(args, "--detach") or table.contains(args, "-d")
	local gdb = table.contains(args, "--gdb") or table.contains(args, "-g")
	local gdb_port = get_config("gdb-port")
	if not gdb_port or gdb_port == "default" or gdb_port == "" then
		gdb_port = "2345"
	end

	local process = process.openv(emu, {
		"-fastboot",
		"-exe", target:targetfile(),
		target:targetfile(),
	}, {detach = detach or gdb})
	if gdb then
		os.execv("gdb", {target:targetfile(), "-ex", "set remotetimeout 5", "-ex", "target remote localhost:" .. gdb_port})
	elseif not detach then
		process:wait()
	end
	process:close()
	return true
end

local help_msg = [=[no emulator was automatically found, please specify one first:
- xmake f --pcsx-redux="path/to/pcsx-redux"
- xmake f --duckstation="path/to/duckstation"
if you have multiple, you can set your preferred one, for example:
- xmake f --psx-emu=pcsx-redux]=]

function launch(target, args)
	if not args then
		args = option.get("arguments") or {}
	end
	local specified_emu = get_config("psx-emu")

	if specified_emu == "pcsx-redux" then
		try_redux(true, target, args)
	elseif specified_emu == "duckstation" then
		try_duckstation(true, target, args)
	elseif specified_emu == "default" or specified_emu == "" or not specified_emu then
		if try_redux(false, target, args) then
			return true
		elseif try_duckstation(false, target, args) then
			return true
		end
		raise(help_msg)
	else
		if os.isexec(specified_emu) then
			local emu_filename = path.filename(specified_emu)
			if emu_filename:match("^[pP][cC][sS][xX]%-?[rR]edux.*$") then
				try_redux(true, target, args, specified_emu)
			elseif emu_filename:match("^[dD]uck[sS]tation.*$") then
				try_duckstation(true, target, args, specified_emu)
			else
				raise("emulator not recognized (from --psx-emu option): " .. specified_emu)
			end
		elseif os.isfile(specified_emu) then
			raise("emulator exists but is not executable (from --psx-emu option): " .. specified_emu)
		end
		raise("unknown emulator (from --psx-emu option): " .. specified_emu)
	end
end
