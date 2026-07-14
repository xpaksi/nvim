local M = {}

local state = {
	buf = nil,
	win = nil,
	job = nil,
	terminal_pending = "",
}

local terminal_queries = {
	"\27]11;?\7",
	"\27]11;?\27\\",
	"\27[?996n",
}

local needs_theme_query_fallback = vim.fn.has("nvim-0.12") == 0

local function normal_background()
	local highlight = vim.api.nvim_get_hl(0, { name = "Normal", link = false })
	local background = highlight.bg
	if type(background) ~= "number" then
		background = vim.o.background == "light" and 0xffffff or 0x000000
	end
	return math.floor(background / 0x10000) % 0x100, math.floor(background / 0x100) % 0x100, background % 0x100
end

local function background_reply(terminator)
	local r, g, b = normal_background()
	return string.format("\27]11;rgb:%02x%02x/%02x%02x/%02x%02x%s", r, r, g, g, b, b, terminator)
end

local function color_scheme_reply()
	return vim.o.background == "light" and "\27[?997;2n" or "\27[?997;1n"
end

local function pending_query_suffix(chunk)
	local pending = ""
	for _, query in ipairs(terminal_queries) do
		for length = 1, math.min(#chunk, #query - 1) do
			local suffix = chunk:sub(-length)
			if query:sub(1, length) == suffix and length > #pending then
				pending = suffix
			end
		end
	end
	return pending
end

-- Neovim 0.12 answers these queries natively. Older versions need a
-- fallback so Pi does not wait for query timeouts or select the wrong theme.
local function answer_terminal_queries(job, chunk)
	local replies = {}
	local bel_queries = select(2, chunk:gsub("\27%]11;%?\7", ""))
	local st_queries = select(2, chunk:gsub("\27%]11;%?\27\\", ""))
	local scheme_queries = select(2, chunk:gsub("\27%[%?996n", ""))
	for _ = 1, bel_queries do
		replies[#replies + 1] = background_reply("\7")
	end
	for _ = 1, st_queries do
		replies[#replies + 1] = background_reply("\27\\")
	end
	for _ = 1, scheme_queries do
		replies[#replies + 1] = color_scheme_reply()
	end
	if #replies > 0 then
		vim.fn.chansend(job, table.concat(replies))
	end
	state.terminal_pending = pending_query_suffix(chunk)
end

local function valid_buf()
	return state.buf and vim.api.nvim_buf_is_valid(state.buf)
end

local function valid_win()
	return state.win and vim.api.nvim_win_is_valid(state.win)
end

local function buffer_window()
	if not valid_buf() then
		return nil
	end
	if valid_win() and vim.api.nvim_win_get_buf(state.win) == state.buf then
		return state.win
	end
	for _, win in ipairs(vim.fn.win_findbuf(state.buf)) do
		if vim.api.nvim_win_is_valid(win) then
			return win
		end
	end
	return nil
end

local function exit_message(buf, code)
	local message = "Pi exited with code " .. code
	if not vim.api.nvim_buf_is_valid(buf) then
		return message
	end
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local output = {}
	for index = #lines, 1, -1 do
		local line = vim.trim(lines[index])
		if line ~= "" and not line:match("^%[Process exited") then
			table.insert(output, 1, line)
			if #output == 5 then
				break
			end
		elseif #output > 0 then
			break
		end
	end
	if #output > 0 then
		return message .. ": " .. table.concat(output, " ")
	end
	return message
end

local function open_window(width)
	vim.cmd("botright vsplit")
	state.win = vim.api.nvim_get_current_win()
	vim.api.nvim_win_set_width(state.win, math.max(1, math.floor(vim.o.columns * width)))
	vim.api.nvim_set_option_value("winfixwidth", true, { win = state.win })
	vim.api.nvim_win_set_buf(state.win, state.buf)
end

local function show(width)
	local win = buffer_window()
	if win then
		state.win = win
		vim.api.nvim_set_current_win(win)
	else
		state.win = nil
		open_window(width)
	end
	vim.cmd.startinsert()
end

---@param command string[]
---@param options? { cwd?: string, width?: number, replace?: boolean }
function M.open(command, options)
	options = options or {}
	local width = options.width or 0.3
	local running = state.job ~= nil
	local same = running and vim.deep_equal(state.command, command) and state.cwd == options.cwd

	if running and (same or not options.replace) and valid_buf() then
		show(width)
		return
	end

	local old_buf = valid_buf() and state.buf or nil
	local old_win = buffer_window()
	local old_job = state.job
	state.job = nil
	state.buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = state.buf })
	if old_win then
		state.win = old_win
		vim.api.nvim_set_current_win(old_win)
		vim.api.nvim_win_set_buf(old_win, state.buf)
	else
		state.win = nil
		open_window(width)
	end
	if old_job then
		pcall(vim.fn.jobstop, old_job)
	end
	if old_buf then
		pcall(vim.api.nvim_buf_delete, old_buf, { force = true })
	end
	state.command = vim.deepcopy(command)
	state.cwd = options.cwd
	state.terminal_pending = ""

	local buf = state.buf
	local ok, job = pcall(vim.fn.jobstart, command, {
		term = true,
		cwd = options.cwd,
		on_stdout = needs_theme_query_fallback and function(job_id, data)
			if state.buf ~= buf or state.job ~= job_id then
				return
			end
			answer_terminal_queries(job_id, state.terminal_pending .. table.concat(data, "\n"))
		end or nil,
		on_exit = function(job_id, code)
			vim.schedule(function()
				if state.buf ~= buf or state.job ~= job_id then
					return
				end
				state.job = nil
				if code ~= 0 then
					vim.notify(exit_message(buf, code), vim.log.levels.ERROR)
				end
				local win = buffer_window()
				if win then
					pcall(vim.api.nvim_win_close, win, true)
				end
				if valid_buf() then
					pcall(vim.api.nvim_buf_delete, buf, { force = true })
				end
				state.buf = nil
				state.win = nil
				state.command = nil
				state.cwd = nil
				state.terminal_pending = ""
			end)
		end,
	})

	if not ok or type(job) ~= "number" or job <= 0 then
		local win = buffer_window()
		if win then
			pcall(vim.api.nvim_win_close, win, true)
		end
		if valid_buf() then
			pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
		end
		state.buf = nil
		state.win = nil
		state.job = nil
		state.command = nil
		state.cwd = nil
		state.terminal_pending = ""
		local detail = ok and "" or ": " .. tostring(job)
		vim.notify("Unable to start Pi" .. detail, vim.log.levels.ERROR)
		return
	end
	state.job = job

	local win = state.win
	vim.api.nvim_create_autocmd("WinClosed", {
		once = true,
		pattern = tostring(win),
		desc = "Forget the closed Pi terminal window",
		callback = function()
			if state.win == win then
				state.win = nil
			end
		end,
	})
	vim.cmd.startinsert()
end

return M
