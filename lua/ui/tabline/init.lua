local highlights = require("ui.tabline.highlights")
local float = require("ui.float")

local M = {}

local defaults = {
	enabled = true,
	width = 0.8,
	height = 0.8,
	preview_size = 0.5,
	flex_width = 130,
	keymaps = {
		toggle = "<leader>bt",
		buffers = "<leader>bb",
		close_all = "<leader>bD",
		close_others = "<leader>bo",
	},
}

local opts = vim.deepcopy(defaults)
local namespace = vim.api.nvim_create_namespace("native_buffer_manager")
local cursor_namespace = vim.api.nvim_create_namespace("native_buffer_manager_cursor")
local popup_winhighlight = "Normal:BufferManagerNormal,FloatBorder:BufferManagerBorder,FloatTitle:BufferManagerTitle"
local enabled = false
local last_buffer
local state = { items = {} }

local function valid_buf(bufnr)
	return bufnr and vim.api.nvim_buf_is_valid(bufnr)
end

local function valid_win(winid)
	return winid and vim.api.nvim_win_is_valid(winid)
end

local function is_managed_buffer(bufnr)
	if not valid_buf(bufnr) or not vim.bo[bufnr].buflisted then
		return false
	end
	return vim.bo[bufnr].filetype ~= "NvimTree"
end

local function buffer_name(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		return "[No Name]"
	end
	return vim.fn.fnamemodify(name, ":t")
end

local function buffer_icon(bufnr)
	if vim.bo[bufnr].buftype == "terminal" then
		return ""
	end
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name == "" then
		return "󰈙"
	end
	local ok, icons = pcall(require, "mini.icons")
	if ok then
		local icon = icons.get("file", name)
		if icon and icon ~= "" then
			return icon
		end
	end
	return "󰈔"
end

local function display_path(bufnr)
	local path = vim.api.nvim_buf_get_name(bufnr)
	if path == "" or vim.bo[bufnr].buftype ~= "" then
		return ""
	end
	local relative = vim.fs.relpath(vim.fn.getcwd(), path) or path
	local parent = vim.fn.fnamemodify(relative, ":h")
	return parent == "." and "" or parent
end

local function buffers()
	local items = {}
	for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
		if is_managed_buffer(bufnr) then
			items[#items + 1] = {
				bufnr = bufnr,
				name = buffer_name(bufnr),
				icon = buffer_icon(bufnr),
				path = display_path(bufnr),
				modified = vim.bo[bufnr].modified,
			}
		end
	end
	table.sort(items, function(a, b)
		return a.bufnr < b.bufnr
	end)
	return items
end

local function statusline_escape(text)
	return (text or ""):gsub("%%", "%%%%"):gsub("[\r\n]", " ")
end


local function active_buffer()
	local current = vim.api.nvim_get_current_buf()
	if is_managed_buffer(current) then
		return current
	end
	return is_managed_buffer(last_buffer) and last_buffer or nil
end

local function tree_width()
	for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
		local bufnr = vim.api.nvim_win_get_buf(winid)
		if valid_buf(bufnr) and vim.bo[bufnr].filetype == "NvimTree" then
			return vim.api.nvim_win_get_width(winid)
		end
	end
	return 0
end

local function tree_offset(width)
	if width <= 0 then
		return "", 0
	end
	if width < vim.o.columns then
		width = width + 1
	end
	local label = float.truncate(" 󰉋 Explorer ", width)
	local left = math.max(0, math.floor((width - vim.fn.strdisplaywidth(label)) / 2))
	local right = math.max(0, width - left - vim.fn.strdisplaywidth(label))
	return "%#BufferlineTree#" .. string.rep(" ", left) .. label .. string.rep(" ", right), width
end

local function show_buffer(bufnr, preferred_win, add_jump)
	local target = preferred_win
	if valid_win(target) then
		local target_buf = vim.api.nvim_win_get_buf(target)
		if vim.bo[target_buf].filetype == "NvimTree" then
			target = nil
		end
	end
	if not target then
		for _, winid in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
			local win_buf = vim.api.nvim_win_get_buf(winid)
			if vim.bo[win_buf].filetype ~= "NvimTree" then
				target = winid
				break
			end
		end
	end
	if target then
		vim.api.nvim_set_current_win(target)
	else
		vim.cmd("vsplit")
	end
	if add_jump then
		vim.cmd("normal! m'")
	end
	vim.api.nvim_win_set_buf(0, bufnr)
end

local function delete_buffer(bufnr)
	local ok, err = pcall(vim.api.nvim_buf_delete, bufnr, { force = false })
	if not ok then
		vim.notify("Buffer not closed: " .. tostring(err), vim.log.levels.WARN)
	end
	return ok
end

local modified_marker = " "

function M.render()
	if not enabled then
		return ""
	end
	local items = buffers()
	local current = active_buffer()
	local offset_text, offset_width = tree_offset(tree_width())
	local count = string.format(" %d %s ", #items, #items == 1 and "buffer" or "buffers")

	local entries = {}
	local current_index = 1
	for index, item in ipairs(items) do
		local highlight = item.bufnr == current and "BufferlineActive" or "BufferlineInactive"
		local label = item.icon .. " " .. item.name
		if item.bufnr == current then
			current_index = index
		end
		entries[index] = {
			text = string.format("%%%d@v:lua.require'ui.tabline'.select@%%#%s# ", item.bufnr, highlight)
				.. statusline_escape(label)
				.. (item.modified and "%#BufferlineModified#" .. modified_marker or "")
				.. " %#" .. highlight .. "#%X",
			width = vim.fn.strdisplaywidth(" " .. label .. " ")
				+ (item.modified and vim.fn.strdisplaywidth(modified_marker) or 0),
		}
	end

	local first, last = 1, #entries
	if #entries > 0 then
		local available = vim.o.columns - offset_width - vim.fn.strdisplaywidth(count)
		local total = 0
		for _, entry in ipairs(entries) do
			total = total + entry.width
		end
		if total > available then
			available = math.max(entries[current_index].width, available - 6)
			first, last = current_index, current_index
			local used = entries[current_index].width
			local grew = true
			while grew do
				grew = false
				if last < #entries and used + entries[last + 1].width <= available then
					last = last + 1
					used = used + entries[last].width
					grew = true
				end
				if first > 1 and used + entries[first - 1].width <= available then
					first = first - 1
					used = used + entries[first].width
					grew = true
				end
			end
		end
	end

	local parts = { offset_text }
	if first > 1 then
		parts[#parts + 1] = "%#BufferlineFill# ‹ "
	end
	for index = first, last do
		parts[#parts + 1] = entries[index].text
	end
	if last < #entries then
		parts[#parts + 1] = "%#BufferlineFill# › "
	end
	parts[#parts + 1] = "%<%=%#BufferlineFill#" .. count
	return table.concat(parts)
end

function M.select(bufnr, _, button)
	bufnr = tonumber(bufnr)
	if not is_managed_buffer(bufnr) then
		return
	end
	if button == "m" then
		if delete_buffer(bufnr) then
			vim.cmd("redrawtabline")
		end
		return
	end
	show_buffer(bufnr, vim.api.nvim_get_current_win(), true)
end


local function create_preview_buffer()
	local bufnr = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(bufnr, "buffer-manager://preview")
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = bufnr })
	vim.api.nvim_set_option_value("swapfile", false, { buf = bufnr })
	vim.api.nvim_set_option_value("modifiable", false, { buf = bufnr })
	vim.api.nvim_set_option_value("filetype", "buffer-manager-preview", { buf = bufnr })
	state.preview_buf = bufnr
	return bufnr
end

local function set_preview_title(title)
	if not valid_win(state.preview_win) then
		return
	end
	local config = vim.api.nvim_win_get_config(state.preview_win)
	config.title = " " .. title .. " "
	config.title_pos = "left"
	vim.api.nvim_win_set_config(state.preview_win, config)
end

local function set_preview_buffer(bufnr)
	if not valid_win(state.preview_win) then
		return false
	end
	local current = vim.api.nvim_win_get_buf(state.preview_win)
	if current == bufnr then
		return true
	end
	local restore_bufhidden
	if valid_buf(current) and current ~= state.preview_buf then
		restore_bufhidden = vim.bo[current].bufhidden
		vim.bo[current].bufhidden = "hide"
	end
	local ok = pcall(vim.api.nvim_win_set_buf, state.preview_win, bufnr)
	if restore_bufhidden and valid_buf(current) then
		vim.bo[current].bufhidden = restore_bufhidden
	end
	return ok
end

local function reset_preview()
	if not valid_win(state.preview_win) then
		return
	end
	if not valid_buf(state.preview_buf) then
		create_preview_buffer()
	end
	set_preview_buffer(state.preview_buf)
	vim.api.nvim_set_option_value("number", false, { win = state.preview_win })
	set_preview_title("󰈙 Preview")
end

local function update_preview()
	if not valid_win(state.win) or not valid_win(state.preview_win) then
		return
	end
	local item = state.items[vim.api.nvim_win_get_cursor(state.win)[1]]
	if not item or not valid_buf(item.bufnr) then
		reset_preview()
		return
	end
	if not vim.api.nvim_buf_is_loaded(item.bufnr) then
		pcall(vim.fn.bufload, item.bufnr)
	end
	if not vim.api.nvim_buf_is_loaded(item.bufnr) then
		reset_preview()
		return
	end
	if not set_preview_buffer(item.bufnr) then
		reset_preview()
		return
	end
	vim.api.nvim_set_option_value("number", true, { win = state.preview_win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = state.preview_win })
	vim.api.nvim_set_option_value("cursorline", false, { win = state.preview_win })
	local title = item.path ~= "" and item.path .. "/" .. item.name or item.name
	set_preview_title(item.icon .. " " .. title)
end

local function add_highlight(row, start_col, end_col, highlight)
	if end_col <= start_col then
		return
	end
	vim.api.nvim_buf_set_extmark(state.buf, namespace, row, start_col, {
		end_col = end_col,
		hl_group = highlight,
	})
end

local function update_cursor()
	if not valid_buf(state.buf) or not valid_win(state.win) then
		return
	end
	vim.api.nvim_buf_clear_namespace(state.buf, cursor_namespace, 0, -1)
	if #state.items > 0 then
		local row = math.min(vim.api.nvim_win_get_cursor(state.win)[1], #state.items)
		vim.api.nvim_win_set_cursor(state.win, { row, 0 })
		vim.api.nvim_buf_set_extmark(state.buf, cursor_namespace, row - 1, 0, {
			end_row = row,
			hl_group = "BufferManagerCursor",
			hl_eol = true,
			priority = 100,
		})
	end
	update_preview()
end

local function render_popup()
	if not valid_buf(state.buf) or not valid_win(state.win) then
		return
	end
	state.items = buffers()
	local width = vim.api.nvim_win_get_width(state.win)
	local lines = {}
	local spans = {}
	for index, item in ipairs(state.items) do
		local prefix = string.format("%3d  ", item.bufnr)
		local suffix = item.modified and "  " or ""
		local fixed = vim.fn.strdisplaywidth(prefix) + vim.fn.strdisplaywidth(suffix)
		local name = float.truncate(item.icon .. " " .. item.name, math.max(1, width - fixed))
		local metadata = ""
		if item.path ~= "" then
			local remaining = width - fixed - vim.fn.strdisplaywidth(name) - 2
			if remaining >= 4 then
				metadata = "  " .. float.truncate_left(item.path, remaining)
			end
		end
		local line = prefix .. name .. metadata .. suffix
		lines[index] = line
		local name_end = #prefix + #name
		local path_end = name_end + #metadata
		spans[index] = {
			{ 0, #prefix, "BufferManagerNumber" },
			{ #prefix, name_end, "BufferManagerName" },
			{ name_end, path_end, "BufferManagerPath" },
			{ path_end, #line, "BufferManagerModified" },
		}
	end
	if #lines == 0 then
		lines = { "󰈙  No buffers" }
	end

	vim.api.nvim_set_option_value("modifiable", true, { buf = state.buf })
	vim.api.nvim_buf_set_lines(state.buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })
	vim.api.nvim_buf_clear_namespace(state.buf, namespace, 0, -1)
	for row, row_spans in ipairs(spans) do
		for _, span in ipairs(row_spans) do
			add_highlight(row - 1, span[1], span[2], span[3])
		end
	end
	update_cursor()
end

function M.close()
	if valid_win(state.win) then
		pcall(vim.api.nvim_win_close, state.win, true)
	end
	if valid_win(state.preview_win) then
		local previewed = vim.api.nvim_win_get_buf(state.preview_win)
		local restore_bufhidden
		if valid_buf(previewed) and previewed ~= state.preview_buf then
			restore_bufhidden = vim.bo[previewed].bufhidden
			vim.bo[previewed].bufhidden = "hide"
		end
		pcall(vim.api.nvim_win_close, state.preview_win, true)
		if restore_bufhidden and valid_buf(previewed) then
			vim.bo[previewed].bufhidden = restore_bufhidden
		end
	end
	if valid_buf(state.buf) then
		pcall(vim.api.nvim_buf_delete, state.buf, { force = true })
	end
	if valid_buf(state.preview_buf) then
		pcall(vim.api.nvim_buf_delete, state.preview_buf, { force = true })
	end
	state.win = nil
	state.buf = nil
	state.preview_win = nil
	state.preview_buf = nil
	state.items = {}
	pcall(vim.api.nvim_del_augroup_by_name, "NativeBufferManagerPopup")
end

local function selected_item()
	if not valid_win(state.win) then
		return nil
	end
	return state.items[vim.api.nvim_win_get_cursor(state.win)[1]]
end

local function open_selected()
	local item = selected_item()
	if not item then
		return
	end
	if not is_managed_buffer(item.bufnr) then
		render_popup()
		return
	end
	local target_win = valid_win(state.source_win) and state.source_win or nil
	M.close()
	show_buffer(item.bufnr, target_win, true)
end

local function delete_selected()
	local item = selected_item()
	if item and delete_buffer(item.bufnr) then
		render_popup()
		vim.cmd("redrawtabline")
	end
end

local function setup_popup_keymaps()
	local map_opts = { buffer = state.buf, silent = true, nowait = true }
	vim.keymap.set("n", "<CR>", open_selected, vim.tbl_extend("force", map_opts, { desc = "Open buffer" }))
	vim.keymap.set("n", "d", delete_selected, vim.tbl_extend("force", map_opts, { desc = "Close buffer" }))
	vim.keymap.set("n", "q", M.close, vim.tbl_extend("force", map_opts, { desc = "Close buffer manager" }))
	vim.keymap.set("n", "<Esc>", M.close, vim.tbl_extend("force", map_opts, { desc = "Close buffer manager" }))
end

function M.open()
	M.close()
	state.source_win = vim.api.nvim_get_current_win()
	state.buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(state.buf, "buffer-manager://buffers")
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = state.buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = state.buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = state.buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = state.buf })
	vim.api.nvim_set_option_value("filetype", "buffer-manager", { buf = state.buf })
	create_preview_buffer()
	local layout, configs = float.window_configs(opts, "Buffers | <CR> open | d close", "Preview")
	state.layout = layout
	state.preview_win = vim.api.nvim_open_win(state.preview_buf, false, configs.preview)
	state.win = vim.api.nvim_open_win(state.buf, true, configs.list)
	float.set_window_options(state.preview_win, popup_winhighlight, true)
	float.set_window_options(state.win, popup_winhighlight, false)
	setup_popup_keymaps()
	render_popup()

	local group = vim.api.nvim_create_augroup("NativeBufferManagerPopup", { clear = true })
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group,
		buffer = state.buf,
		callback = update_cursor,
	})
	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = function()
			if valid_win(state.win) and valid_win(state.preview_win) then
				local new_layout, new_configs = float.window_configs(opts, "Buffers | <CR> open | d close", "Preview")
				state.layout = new_layout
				vim.api.nvim_win_set_config(state.preview_win, new_configs.preview)
				vim.api.nvim_win_set_config(state.win, new_configs.list)
				render_popup()
			end
		end,
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
end

function M.close_others()
	local current = active_buffer()
	if not is_managed_buffer(current) then
		vim.notify("No active user buffer to keep", vim.log.levels.INFO)
		return
	end
	for _, item in ipairs(buffers()) do
		if item.bufnr ~= current then
			delete_buffer(item.bufnr)
		end
	end
	vim.cmd("redrawtabline")
end

function M.close_all()
	local items = buffers()
	if #items == 0 then
		return
	end
	if is_managed_buffer(vim.api.nvim_get_current_buf()) then
		local replacement = vim.api.nvim_create_buf(true, false)
		vim.api.nvim_win_set_buf(0, replacement)
	end
	for _, item in ipairs(items) do
		delete_buffer(item.bufnr)
	end
	vim.cmd("redrawtabline")
end

local saved_options

function M.enable()
	if not enabled then
		saved_options = { tabline = vim.o.tabline, showtabline = vim.o.showtabline }
	end
	enabled = true
	vim.o.tabline = "%!v:lua.require'ui.tabline'.render()"
	vim.o.showtabline = 2
	vim.cmd("redrawtabline")
end

function M.disable()
	enabled = false
	if saved_options then
		vim.o.tabline = saved_options.tabline
		vim.o.showtabline = saved_options.showtabline
		saved_options = nil
	else
		vim.o.showtabline = 0
	end
end

function M.toggle()
	if enabled then
		M.disable()
	else
		M.enable()
	end
end

local function create_command()
	vim.api.nvim_create_user_command("TablineUI", function(command)
		local action = command.args ~= "" and command.args or "toggle"
		if action == "enable" then
			M.enable()
		elseif action == "disable" then
			M.disable()
		else
			M.toggle()
		end
	end, {
		nargs = "?",
		force = true,
		desc = "Enable, disable, or toggle the native buffer tabline",
		complete = function(arglead)
			return vim.tbl_filter(function(action)
				return vim.startswith(action, arglead)
			end, { "enable", "disable", "toggle" })
		end,
	})
end

function M.setup(user_opts)
	M.close()
	opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_opts or {})
	highlights.apply()
	create_command()

	local group = vim.api.nvim_create_augroup("NativeBufferline", { clear = true })
	vim.api.nvim_create_autocmd({ "BufAdd", "BufDelete", "BufModifiedSet", "BufWinEnter", "WinClosed" }, {
		group = group,
		desc = "Refresh the native buffer tabline",
		callback = function(event)
			vim.schedule(function()
				vim.cmd("redrawtabline")
				if valid_win(state.win) and event.event ~= "BufWinEnter" and event.event ~= "WinClosed" then
					render_popup()
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("BufEnter", {
		group = group,
		desc = "Track the active user buffer",
		callback = function(event)
			if is_managed_buffer(event.buf) then
				last_buffer = event.buf
			end
			vim.cmd("redrawtabline")
		end,
	})
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		desc = "Restore native buffer UI highlights",
		callback = function()
			highlights.apply()
			vim.cmd("redrawtabline")
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		desc = "Close the buffer manager",
		callback = M.close,
	})

	local maps = opts.keymaps
	vim.keymap.set("n", maps.toggle, M.toggle, { desc = "Toggle buffer tabline" })
	vim.keymap.set("n", maps.buffers, M.open, { desc = "Show active buffers" })
	vim.keymap.set("n", maps.close_all, M.close_all, { desc = "Close all buffers" })
	vim.keymap.set("n", maps.close_others, M.close_others, { desc = "Close all buffers except current" })

	if opts.enabled then
		M.enable()
	else
		M.disable()
	end
end

function M.is_enabled()
	return enabled
end

return M
