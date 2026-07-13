local M = {}

local float = require("ui.float")

local defaults = {
	width = 0.8,
	height = 0.8,
}

local opts = vim.deepcopy(defaults)
local namespace = vim.api.nvim_create_namespace("OpenCodeSessionList")
local cursor_namespace = vim.api.nvim_create_namespace("OpenCodeSessionListCursor")
local initialized = false
local active_timer
local spinner_index = 1
local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local state = {
	items = {},
}
local render

local highlight_links = {
	OpenCodeSessionNormal = "NormalFloat",
	OpenCodeSessionBorder = "FloatBorder",
	OpenCodeSessionTitle = "FloatTitle",
	OpenCodeSessionName = "Identifier",
	OpenCodeSessionActive = "DiagnosticOk",
	OpenCodeSessionDetail = "Comment",
	OpenCodeSessionCursor = "CursorLine",
}

local function apply_highlights()
	for name, target in pairs(highlight_links) do
		vim.api.nvim_set_hl(0, name, { link = target, default = true })
	end
end

local function valid_buf(buf)
	return buf and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function has_active_session()
	for _, item in ipairs(state.items) do
		if item.active then
			return true
		end
	end
	return false
end

local function sync_active_timer()
	if not has_active_session() then
		if active_timer then
			active_timer:stop()
		end
		return
	end
	if not active_timer then
		active_timer = vim.uv.new_timer()
	end
	if not active_timer:is_active() then
		active_timer:start(0, 120, vim.schedule_wrap(function()
			spinner_index = spinner_index % #spinner + 1
			render()
		end))
	end
end

local function close_active_timer()
	if active_timer and not active_timer:is_closing() then
		active_timer:stop()
		active_timer:close()
	end
	active_timer = nil
end

local function border()
	local configured = vim.o.winborder
	return configured ~= "" and configured or "rounded"
end

local function window_config(title)
	local columns = math.max(1, vim.o.columns)
	local lines = math.max(1, vim.o.lines - vim.o.cmdheight - 1)
	local max_width = math.max(1, columns - 2)
	local max_height = math.max(1, lines - 2)
	local width = math.min(max_width, math.max(math.min(30, max_width), math.floor(columns * opts.width)))
	local height = math.min(max_height, math.max(math.min(8, max_height), math.floor(lines * opts.height)))

	return {
		relative = "editor",
		style = "minimal",
		row = math.max(0, math.floor((lines - height) / 2)),
		col = math.max(0, math.floor((columns - width) / 2)),
		width = width,
		height = height,
		border = border(),
		title = " " .. title .. " ",
		title_pos = "left",
		zindex = 52,
	}
end

local function timestamp(milliseconds)
	if not milliseconds then
		return nil
	end
	return os.date("%Y-%m-%d %H:%M", math.floor(milliseconds / 1000))
end

local function item_metadata(item)
	local metadata = {}
	if item.agent then
		metadata[#metadata + 1] = item.agent
	end
	if item.model then
		metadata[#metadata + 1] = item.provider and (item.provider .. "/" .. item.model) or item.model
	end
	metadata[#metadata + 1] = timestamp(item.updated or item.created)
	return table.concat(vim.tbl_filter(function(value)
		return value and value ~= ""
	end, metadata), "  ")
end

local function update_cursor()
	if not valid_buf(state.buf) or not valid_win(state.win) then
		return
	end
	vim.api.nvim_buf_clear_namespace(state.buf, cursor_namespace, 0, -1)
	local row = vim.api.nvim_win_get_cursor(state.win)[1]
	if state.items[row] then
		vim.api.nvim_buf_set_extmark(state.buf, cursor_namespace, row - 1, 0, {
			end_row = row,
			hl_group = "OpenCodeSessionCursor",
			hl_eol = true,
			priority = 100,
		})
	end
end

render = function()
	if not valid_buf(state.buf) or not valid_win(state.win) then
		return
	end
	local width = vim.api.nvim_win_get_width(state.win)
	local lines = {}
	local spans = {}
	for index, item in ipairs(state.items) do
		local prefix = item.active and (spinner[spinner_index] .. " ") or "  "
		local metadata = item_metadata(item)
		local metadata_width = vim.fn.strdisplaywidth(metadata)
		local title_width = math.max(1, width - vim.fn.strdisplaywidth(prefix) - metadata_width - 2)
		local title = float.truncate(item.title, title_width)
		local padding = math.max(2, width - vim.fn.strdisplaywidth(prefix .. title) - metadata_width)
		lines[index] = float.truncate(prefix .. title .. string.rep(" ", padding) .. metadata, width)
		spans[index] = {
			active = item.active,
			name_start = #prefix,
			name_end = #prefix + #title,
			detail_start = #prefix + #title + padding,
		}
	end
	if #lines == 0 then
		lines = { "No sessions" }
	end

	vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })
	vim.api.nvim_buf_clear_namespace(state.buf, namespace, 0, -1)
	for row, span in ipairs(spans) do
		if span.active then
			vim.api.nvim_buf_set_extmark(state.buf, namespace, row - 1, 0, {
				end_col = span.name_start,
				hl_group = "OpenCodeSessionActive",
			})
		end
		vim.api.nvim_buf_set_extmark(state.buf, namespace, row - 1, span.name_start, {
			end_col = span.name_end,
			hl_group = "OpenCodeSessionName",
		})
		if span.detail_start < #lines[row] then
			vim.api.nvim_buf_set_extmark(state.buf, namespace, row - 1, span.detail_start, {
				end_col = #lines[row],
				hl_group = "OpenCodeSessionDetail",
			})
		end
	end
	update_cursor()
end

function M.close()
	local win, buf = state.win, state.buf
	local on_close = state.on_close
	close_active_timer()
	state.win = nil
	state.buf = nil
	state.items = {}
	state.on_select = nil
	state.on_close = nil
	if on_close then
		on_close()
	end
	if valid_win(win) then
		pcall(vim.api.nvim_win_close, win, true)
	end
	if valid_buf(buf) then
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
	end
	pcall(vim.api.nvim_del_augroup_by_name, "OpenCodeSessionListWindow")
end

local function select_session()
	if not valid_win(state.win) then
		return
	end
	local item = state.items[vim.api.nvim_win_get_cursor(state.win)[1]]
	if not item then
		return
	end
	local callback = state.on_select
	M.close()
	if callback then
		callback(item)
	end
end

local function set_keymaps()
	local map_opts = { buffer = state.buf, silent = true, nowait = true }
	vim.keymap.set("n", "<CR>", select_session, vim.tbl_extend("force", map_opts, { desc = "Select OpenCode session" }))
	vim.keymap.set("n", "q", M.close, vim.tbl_extend("force", map_opts, { desc = "Close OpenCode sessions" }))
	vim.keymap.set("n", "<Esc>", M.close, vim.tbl_extend("force", map_opts, { desc = "Close OpenCode sessions" }))
end

---@param items OpenCodeSession[]
---@param options? { directory?: string, on_select?: fun(session: OpenCodeSession), on_close?: fun() }
function M.open(items, options)
	if not initialized then
		M.setup()
	end
	M.close()
	options = options or {}
	state.items = items or {}
	state.on_select = options.on_select
	state.on_close = options.on_close
	state.title = "OpenCode Sessions"
	if options.directory then
		state.title = state.title .. ": " .. vim.fs.basename(options.directory)
	end

	state.buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(state.buf, "opencode://sessions")
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = state.buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = state.buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = state.buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })
	vim.api.nvim_set_option_value("filetype", "opencode-sessions", { buf = state.buf })

	state.win = vim.api.nvim_open_win(state.buf, true, window_config(state.title))
	float.set_window_options(
		state.win,
		"Normal:OpenCodeSessionNormal,FloatBorder:OpenCodeSessionBorder,FloatTitle:OpenCodeSessionTitle",
		false
	)
	set_keymaps()
	render()

	local group = vim.api.nvim_create_augroup("OpenCodeSessionListWindow", { clear = true })
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group,
		buffer = state.buf,
		callback = update_cursor,
	})
	vim.api.nvim_create_autocmd("WinLeave", {
		group = group,
		buffer = state.buf,
		callback = function()
			vim.schedule(function()
				if valid_win(state.win) and vim.api.nvim_get_current_win() ~= state.win then
					M.close()
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = function()
			if valid_win(state.win) then
				vim.api.nvim_win_set_config(state.win, window_config(state.title))
				render()
			end
		end,
	})
end

---@param active table<string, table>
function M.update_active(active)
	if not valid_buf(state.buf) or not valid_win(state.win) then
		return
	end
	for _, item in ipairs(state.items) do
		item.active = active[item.id] ~= nil
	end
	sync_active_timer()
	render()
end

function M.setup(user_opts)
	opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_opts or {})
	apply_highlights()
	initialized = true
	local group = vim.api.nvim_create_augroup("OpenCodeSessionList", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		desc = "Restore OpenCode session list highlights",
		callback = apply_highlights,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		desc = "Close OpenCode session list",
		callback = M.close,
	})
end

return M
