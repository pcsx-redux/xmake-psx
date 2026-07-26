local EXE_ALIGNMENT = 2048
local ELF_HEADER_SIZE = 52
local PROG_HEADER_SIZE = 32

local ELF_HEADER_MAGIC = "\127ELF"
local EXE_HEADER_MAGIC = "PS-X EXE"

local ELF_TYPE_EXECUTABLE = 2
local ELF_ARCH_MIPS = 8
local ELF_ENDIANNESS_LITTLE = 1

local PROG_HEADER_TYPE_LOAD = 1
local PROG_FLAG_EXECUTE = 1 << 0
local PROG_FLAG_WRITE = 1 << 1

local function trim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function pack_u32_le(n)
	return string.pack("<I4", n)
end

local function read_u16_le(data, pos)
	return string.unpack("<I2", data, pos)
end

local function read_u32_le(data, pos)
	return string.unpack("<I4", data, pos)
end

local function file_read_all(io, path)
	local f, err = io.open(path, "rb")
	if not f then
		return nil, err
	end

	local data = f:read("*a")
	f:close()
	return data
end

local function file_write_all(io, path, data)
	local f, err = io.open(path, "wb")
	if not f then
		return nil, err
	end

	f:write(data)
	f:close()

	return true
end

local function parse_elf(elf_data)
	if #elf_data < ELF_HEADER_SIZE then
		return nil, "file is not a valid ELF"
	end

	local magic = elf_data:sub(1, 4)
	local word_size = string.unpack("B", elf_data, 5)
	local endianness = string.unpack("B", elf_data, 6)
	local abi = string.unpack("B", elf_data, 8)

	local elf_type = read_u16_le(elf_data, 17)
	local architecture = read_u16_le(elf_data, 19)
	local entry_point = read_u32_le(elf_data, 25)
	local prog_header_offset = read_u32_le(elf_data, 29)
	local flags = read_u32_le(elf_data, 37)
	local elf_header_size = read_u16_le(elf_data, 41)
	local prog_header_size = read_u16_le(elf_data, 43)
	local prog_header_count = read_u16_le(elf_data, 45)

	if magic ~= ELF_HEADER_MAGIC then
		return nil, "file is not a valid ELF"
	end
	if word_size ~= 1 or endianness ~= ELF_ENDIANNESS_LITTLE then
		return nil, "ELF file must be 32-bit little-endian"
	end
	if elf_header_size ~= ELF_HEADER_SIZE or prog_header_size ~= PROG_HEADER_SIZE then
		return nil, "unsupported ELF format"
	end

	local segments = {}

	for i = 0, prog_header_count - 1 do
		local base = prog_header_offset + 1 + (i * PROG_HEADER_SIZE)
		if (base + PROG_HEADER_SIZE - 1) > #elf_data then
			return nil, "unsupported ELF format"
		end

		local header_type = read_u32_le(elf_data, base)
		local file_offset = read_u32_le(elf_data, base + 4)
		local address = read_u32_le(elf_data, base + 8)
		local file_length = read_u32_le(elf_data, base + 16)
		local length = read_u32_le(elf_data, base + 20)
		local seg_flags = read_u32_le(elf_data, base + 24)

		if header_type == PROG_HEADER_TYPE_LOAD and address ~= 0x1F800000 then
			local data_start = file_offset + 1
			local data_end = file_offset + file_length

			if data_start < 1 or data_end > #elf_data then
				return nil, "unsupported ELF format"
			end

			local seg_data = elf_data:sub(data_start, data_end)

			if length > #seg_data then
				seg_data = seg_data .. string.rep("\0", length - #seg_data)
			else
				seg_data = seg_data:sub(1, length)
			end

			segments[#segments + 1] = {
				address = address,
				data = seg_data,
				flags = seg_flags,
			}
		end
	end

	return {
		type = elf_type,
		architecture = architecture,
		abi = abi,
		entry_point = entry_point,
		flags = flags,
		segments = segments,
	}
end

local function flatten_segments(segments, strip_read_only)
	local start_address = nil
	local end_address = nil

	for _, seg in ipairs(segments) do
		if start_address == nil or seg.address < start_address then
			start_address = seg.address
		end

		local seg_end = seg.address + #seg.data
		if end_address == nil or seg_end > end_address then
			end_address = seg_end
		end
	end

	local total_size = end_address - start_address
	local out = {}
	for i = 1, total_size do
		out[i] = "\0"
	end

	for _, seg in ipairs(segments) do
		local is_read_only = ((seg.flags & (PROG_FLAG_WRITE | PROG_FLAG_EXECUTE)) == 0)
		if not (strip_read_only and is_read_only) then
			local offset = seg.address - start_address + 1
			for i = 1, #seg.data do
				out[offset + i - 1] = seg.data:sub(i, i)
			end
		end
	end

	local data = table.concat(out)

	local rem = #data % EXE_ALIGNMENT
	if rem ~= 0 then
		data = data .. string.rep("\0", EXE_ALIGNMENT - rem)
	end

	return start_address, data
end

local function make_exe_header(entry_point, set_gp, start_address, data_size, set_sp, region)
	local magic16 = EXE_HEADER_MAGIC .. string.rep("\0", 16 - #EXE_HEADER_MAGIC)

	local region_ascii = trim(region)
	for i = 1, #region_ascii do
		if region_ascii:byte(i) > 127 then
			return nil, "region string must contain only ASCII characters"
		end
	end

	if #region_ascii > 1972 then
		region_ascii = region_ascii:sub(1, 1972)
	end
	local region_field = region_ascii .. string.rep("\0", 1972 - #region_ascii)

	local header = table.concat({
		magic16,
		pack_u32_le(entry_point),
		pack_u32_le(set_gp),
		pack_u32_le(start_address),
		pack_u32_le(data_size),
		string.rep("\0", 16),
		pack_u32_le(set_sp),
		pack_u32_le(0),
		string.rep("\0", 20),
		region_field,
	})

	return header
end

--[[
opts:
  region_str: string
  set_sp: integer
  set_gp: integer
  strip_read_only: boolean
  input: string (input file path)
  output: string (output file path)
]]--

local function convert(io, opts)
	local elf_data, read_err = file_read_all(io, opts.input)
	if not elf_data then
		return false, "unable to read input file: " .. tostring(read_err)
	end

	local elf, elf_err = parse_elf(elf_data)
	if not elf then
		return false, elf_err
	end

	if elf.type ~= ELF_TYPE_EXECUTABLE then
		return false, "ELF file must be an executable"
	end
	if elf.architecture ~= ELF_ARCH_MIPS then
		return false, "ELF architecture must be MIPS"
	end
	if #elf.segments == 0 then
		return false, "ELF file must contain at least one segment"
	end

	local start_address, data = flatten_segments(elf.segments, opts.strip_read_only)
	local header, header_err = make_exe_header(
		elf.entry_point,
		opts.set_gp,
		start_address,
		#data,
		opts.set_sp,
		opts.region_str
	)

	if not header then
		return false, header_err
	end

	local ok, write_err = file_write_all(io, opts.output, header .. data)
	if not ok then
		print(type(ok))
		print(type(write_err))
		return false, "unable to write output file: " .. tostring(write_err)
	end

	return true
end

local function get_binary_dep(target)
	local deps = target:get("deps")
	if type(deps) == "string" then deps = {deps} end
	if not deps or #deps == 0 then
		return nil, "psx.psexe target must have at least one dependency"
	end
	local binary = nil
	for index, value in ipairs(deps) do
		if type(value) == "string" then
			local dep_target = target:dep(value)
			if not dep_target then
				return nil, "psx.psexe target dependency '" .. value .. "' does not exist"
			end
			if dep_target:get("kind") == "binary" and dep_target:get("plat") == "psx" and dep_target:get("arch") == "mipsel" then
				if binary then
					return nil, "psx.psexe target can only have one binary dependency, found '" .. binary:name() .. "' and '" .. dep_target:name() .. "'"
				end
				if dep_target:get("plat") ~= "psx" then
					return nil, "psx.psexe target dependency '" .. dep_target:name() .. "' must be a psx target"
				end
				binary = dep_target
			end
		else
			return nil, "psx.psexe target dependencies must be strings"
		end
	end
	if not binary then
		return nil, "psx.psexe target must have at least one binary dependency"
	end
	return binary
end

rule("psx.psexe", function()
	on_load(function(target)
		target:set("kind", "binary")
		target:set("plat", "psx")
		target:set("arch", "mipsel")
		local extension = target:get("extension")
		if not extension then
			target:set("extension", ".psexe")
		end
	end)
	before_config(function(target)
		local binary, err = get_binary_dep(target)
		if not binary then
			raise("psx.psexe target error: " .. err)
		end
		target:set("basename", binary:basename())
	end)
	on_build(function(target)
		import("core.project.depend")

		os.mkdir(target:targetdir())
		local binary, err = get_binary_dep(target)
		if not binary then
			raise("psx.psexe target error: " .. err)
		end
		local opts = {
			region_str = target:values("psexe_region_str") or "", -- useless, not checked by the bios
			set_sp = target:values("psexe_sp") or 0x807ffff0, -- generally useless, sp will be overridden by system.cnf and crt0
			set_gp = target:values("psexe_gp") or 0, -- generally useless, gp will be overridden by crt0
			strip_read_only = target:values("psexe_strip_read_only") or false, -- unknown purpose
			input = binary:targetfile(),
			output = target:targetfile(),
		}
		depend.on_changed(function ()
			print("psx.psexe converted %s into %s", opts.input, opts.output)
			local ok, err = convert(io, opts)
			if not ok then
				raise("psx.psexe error: " .. err)
			end
		end, {files = opts.input})
	end)
end)
