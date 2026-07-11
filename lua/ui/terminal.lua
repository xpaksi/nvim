local M = {}

local function window_config()
	local max_width = math.max(1, vim.o.columns - 2)
	local max_height = math.max(1, vim.o.lines - vim.o.cmdheight - 2)
	local width = math.max(1, math.floor(max_width * 0.9))
	local height = math.max(1, math.floor(max_height * 0.9))

	return {
		relative = "editor",
		style = "minimal",
		border = vim.o.winborder ~= "" and vim.o.winborder or "rounded",
		width = width,
		height = height,
		col = math.floor((vim.o.columns - width) / 2),
		row = math.floor((vim.o.lines - vim.o.cmdheight - height) / 2),
	}
end

function M.setup(opts)
	local state = {
		buf = nil,
		win = nil,
	}

	local executable = opts.command[1]
	local label = table.concat(opts.command, " ")

	local function open(args)
		if state.win and vim.api.nvim_win_is_valid(state.win) then
			vim.api.nvim_set_current_win(state.win)
			return
		end

		if vim.fn.executable(executable) ~= 1 then
			vim.notify(executable .. " executable not found", vim.log.levels.ERROR)
			return
		end

		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
		local win = vim.api.nvim_open_win(buf, true, window_config())
		state.buf = buf
		state.win = win

		local command = vim.list_extend(vim.deepcopy(opts.command), args)
		local job = vim.fn.jobstart(command, {
			term = true,
			cwd = vim.fn.getcwd(),
			on_exit = function()
				vim.schedule(function()
					if state.buf ~= buf then
						return
					end
					if vim.api.nvim_win_is_valid(win) then
						vim.api.nvim_win_close(win, true)
					end
					state.buf = nil
					state.win = nil
				end)
			end,
		})

		if job <= 0 then
			vim.api.nvim_win_close(win, true)
			state.buf = nil
			state.win = nil
			vim.notify("Unable to start " .. label, vim.log.levels.ERROR)
			return
		end

		vim.cmd.startinsert()
	end

	vim.api.nvim_create_user_command(opts.name, function(command_opts)
		open(command_opts.fargs)
	end, {
		nargs = opts.nargs or 0,
		complete = opts.complete,
		desc = opts.desc,
	})

	vim.api.nvim_create_autocmd("VimResized", {
		desc = "Resize the " .. label .. " floating terminal",
		group = vim.api.nvim_create_augroup(opts.name .. "-float", { clear = true }),
		callback = function()
			if state.win and vim.api.nvim_win_is_valid(state.win) then
				vim.api.nvim_win_set_config(state.win, window_config())
			end
		end,
	})
end

return M
