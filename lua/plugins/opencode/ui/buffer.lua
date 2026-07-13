local M = {}

local state = {
	buf = nil,
	win = nil,
	job = nil,
	osc_pending = "",
}

-- Neovim's terminal emulator never answers OSC 4 palette queries, so
-- palette-adaptive TUIs (like opencode mini) fall back to their hardcoded
-- theme. Answer the queries ourselves from the colorscheme's terminal palette.
local function standard_color(index)
	if index < 16 then
		local base = {
			[0] = "#000000",
			"#cd0000",
			"#00cd00",
			"#cdcd00",
			"#0000ee",
			"#cd00cd",
			"#00cdcd",
			"#e5e5e5",
			"#7f7f7f",
			"#ff0000",
			"#00ff00",
			"#ffff00",
			"#5c5cff",
			"#ff00ff",
			"#00ffff",
			"#ffffff",
		}
		return base[index]
	end
	if index < 232 then
		local n = index - 16
		local function level(value)
			return value == 0 and 0 or value * 40 + 55
		end
		local r = level(math.floor(n / 36))
		local g = level(math.floor(n / 6) % 6)
		local b = level(n % 6)
		return string.format("#%02x%02x%02x", r, g, b)
	end
	local gray = (index - 232) * 10 + 8
	return string.format("#%02x%02x%02x", gray, gray, gray)
end

local function palette_reply(index, terminator)
	local color = index < 16 and vim.g["terminal_color_" .. index] or nil
	if type(color) ~= "string" or not color:match("^#%x%x%x%x%x%x$") then
		color = standard_color(index)
	end
	local r, g, b = color:match("^#(%x%x)(%x%x)(%x%x)$")
	return string.format("\27]4;%d;rgb:%s%s/%s%s/%s%s%s", index, r, r, g, g, b, b, terminator)
end

local function answer_palette_queries(job, chunk)
	if not chunk:find("\27]4;", 1, true) then
		state.osc_pending = ""
		return
	end

	local replies = {}
	for body, terminator in chunk:gmatch("\27%]4;([%d;%?]-)(\7)") do
		for index in body:gmatch("(%d+);%?") do
			replies[#replies + 1] = palette_reply(tonumber(index), terminator)
		end
	end
	for body in chunk:gmatch("\27%]4;([%d;%?]-)\27\\") do
		for index in body:gmatch("(%d+);%?") do
			replies[#replies + 1] = palette_reply(tonumber(index), "\27\\")
		end
	end
	if #replies > 0 then
		vim.fn.chansend(job, table.concat(replies))
	end

	-- Keep an unterminated trailing query so it can complete on the next chunk.
	local tail
	for position in chunk:gmatch("()\27%]4;") do
		tail = position
	end
	if tail and not chunk:find("\7", tail, true) and not chunk:find("\27\\", tail, true) and #chunk - tail < 256 then
		state.osc_pending = chunk:sub(tail)
	else
		state.osc_pending = ""
	end
end

local function valid_buf()
	return state.buf and vim.api.nvim_buf_is_valid(state.buf)
end

local function valid_win()
	return state.win and vim.api.nvim_win_is_valid(state.win)
end

local function exit_message(buf, code)
	local message = "OpenCode exited with code " .. code
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

---@param command string[]
---@param options? { cwd?: string, width?: number, replace?: boolean }
function M.open(command, options)
	options = options or {}
	local running = state.job ~= nil
	local same = running and vim.deep_equal(state.command, command) and state.cwd == options.cwd

	if running and (same or not options.replace) then
		if valid_win() then
			vim.api.nvim_set_current_win(state.win)
			vim.cmd.startinsert()
			return
		end
		if valid_buf() then
			open_window(options.width or 0.3)
			vim.cmd.startinsert()
			return
		end
	end

	-- Replace any existing pane: reuse its window, then drop the old
	-- terminal buffer (which also kills the old job).
	local old_buf = valid_buf() and state.buf or nil
	local old_win = valid_win() and state.win or nil
	state.buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = state.buf })
	if old_win then
		state.win = old_win
		vim.api.nvim_set_current_win(state.win)
		vim.api.nvim_win_set_buf(state.win, state.buf)
	else
		open_window(options.width or 0.3)
	end
	if old_buf then
		pcall(vim.api.nvim_buf_delete, old_buf, { force = true })
	end
	state.command = command
	state.cwd = options.cwd

	local buf = state.buf
	state.osc_pending = ""
	state.job = vim.fn.jobstart(command, {
		term = true,
		cwd = options.cwd,
		on_stdout = function(_, data)
			if state.buf ~= buf or not state.job then
				return
			end
			answer_palette_queries(state.job, state.osc_pending .. table.concat(data, ""))
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				if state.buf ~= buf then
					return
				end
				state.job = nil
				if code ~= 0 then
					vim.notify(exit_message(buf, code), vim.log.levels.ERROR)
				end
				if valid_win() then
					pcall(vim.api.nvim_win_close, state.win, true)
				end
				if valid_buf() then
					vim.api.nvim_buf_delete(state.buf, { force = true })
				end
				state.buf = nil
				state.win = nil
				state.command = nil
				state.cwd = nil
			end)
		end,
	})

	if state.job <= 0 then
		pcall(vim.api.nvim_win_close, state.win, true)
		vim.api.nvim_buf_delete(state.buf, { force = true })
		state.buf = nil
		state.win = nil
		state.job = nil
		state.command = nil
		state.cwd = nil
		vim.notify("Unable to start OpenCode", vim.log.levels.ERROR)
		return
	end

	vim.api.nvim_create_autocmd("WinClosed", {
		once = true,
		pattern = tostring(state.win),
		callback = function()
			state.win = nil
		end,
	})
	vim.cmd.startinsert()
end

return M
