import("core.base.tty")
import("core.base.colors")

-- try to match xmake's own conditions for coloring
color = tty.has_color8() and colors.theme():name() ~= "plain"

local cached_pager, cached_pager_args

function get_pager()
	if not cached_pager then
		if find_program("less") then
			cached_pager, cached_pager_args = "less", {"-R"}
		elseif find_program("more") then
			cached_pager, cached_pager_args = "more", {}
		end
	end
	return cached_pager, cached_pager_args
end

function execv_paged(program, args)
	-- try to page the output nicely, but only if invoked manually in a terminal
	if io.isatty() then
		print("running: " .. objdump .. " " .. os.args(args))

		local stdout = os.iorunv(program, args)
		if not stdout then
			return false
		end

		local pager, pager_args = get_pager()
		if pager then
			local read_pipe, write_pipe = pipe.openpair()
			write_pipe:write(stdout)
			write_pipe:close()
			return os.execv(pager, pager_args, {stdin = read_pipe}) and true or false
		end
		-- falthrough to execute normally if no pager is installed
	end
	return os.execv(objdump, args) and true or false
end
