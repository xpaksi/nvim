local M = {}

local float = require("ui.float")
local highlights = require("ui.pack.highlights")

local defaults = {
	width = 0.8,
	height = 0.8,
	preview_size = 0.55,
	flex_width = 130,
}

local opts = vim.deepcopy(defaults)
local namespace = vim.api.nvim_create_namespace("native_pack_list")
local cursor_namespace = vim.api.nvim_create_namespace("native_pack_list_cursor")
local winhighlight = "Normal:PackListNormal,FloatBorder:PackListBorder,FloatTitle:PackListTitle"
local state = { items = {} }

local function valid_buf(buf)
	return buf and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function package_name(item)
	return item.spec.name or vim.fs.basename(item.path)
end

local function collect_packages()
	local packages = vim.pack.get(nil, { info = false })
	table.sort(packages, function(a, b)
		if a.active ~= b.active then
			return a.active
		end
		return package_name(a):lower() < package_name(b):lower()
	end)
	return packages
end

local function add_span(spans, start_col, text, hl)
	spans[#spans + 1] = { start_col = start_col, end_col = start_col + #text, hl = hl }
end

local function render_item(item, width)
	local status = item.active and "active  " or "inactive"
	local name = package_name(item)
	local display_name = float.truncate(name, 24)
	-- Pad by display width: a truncated name ends in a multibyte "…", so
	-- %-24s byte padding would shift the byte offsets of later spans.
	local name_pad = string.rep(" ", math.max(0, 24 - vim.fn.strdisplaywidth(display_name)))
	local revision = (item.rev or "unknown"):sub(1, 8)
	local prefix = string.format("%s  %s%s  %-8s  ", status, display_name, name_pad, revision)
	local source = item.spec.src or item.path
	local line = float.truncate(prefix .. source, width)
	local spans = {}
	add_span(spans, 0, status, item.active and "PackListActive" or "PackListInactive")
	add_span(spans, 10, display_name, "PackListName")
	add_span(spans, 12 + #display_name + #name_pad, revision, "PackListRevision")
	if #line > #prefix then
		add_span(spans, #prefix, line:sub(#prefix + 1), "PackListSource")
	end
	return line, spans
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

local function find_readme(item)
	if item.readme_checked then
		return item.readme
	end
	item.readme_checked = true
	item.readme = vim.fs.find({ "README.md", "README.mdx", "README.txt", "README" }, {
		path = item.path,
		type = "file",
		limit = 1,
	})[1]
	return item.readme
end

local function show_details(item)
	if not valid_buf(state.preview_buf) or not valid_win(state.preview_win) then
		return
	end
	local version = item.spec.version
	if type(version) == "table" then
		version = tostring(version)
	end
	local lines = {
		"# " .. package_name(item),
		"",
		"Status:   " .. (item.active and "active" or "inactive"),
		"Revision: " .. (item.rev or "unknown"),
		"Version:  " .. (version or "default branch"),
		"Source:   " .. (item.spec.src or "unknown"),
		"Path:     " .. item.path,
	}
	vim.api.nvim_set_option_value("modifiable", true, { buf = state.preview_buf })
	vim.api.nvim_buf_set_lines(state.preview_buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = state.preview_buf })
	vim.api.nvim_win_set_buf(state.preview_win, state.preview_buf)
	vim.api.nvim_set_option_value("number", false, { win = state.preview_win })
	set_preview_title("Details")
end

local function update_preview()
	if not valid_win(state.list_win) or not valid_win(state.preview_win) then
		return
	end
	local item = state.items[vim.api.nvim_win_get_cursor(state.list_win)[1]]
	if not item then
		if valid_buf(state.preview_buf) then
			vim.api.nvim_win_set_buf(state.preview_win, state.preview_buf)
		end
		set_preview_title("Preview")
		return
	end

	local readme = find_readme(item)
	if not readme then
		show_details(item)
		return
	end
	local bufnr = vim.fn.bufadd(readme)
	if not vim.api.nvim_buf_is_loaded(bufnr) then
		pcall(vim.fn.bufload, bufnr)
	end
	if not vim.api.nvim_buf_is_loaded(bufnr) then
		show_details(item)
		return
	end
	vim.api.nvim_win_set_buf(state.preview_win, bufnr)
	vim.api.nvim_set_option_value("number", false, { win = state.preview_win })
	pcall(vim.api.nvim_win_set_cursor, state.preview_win, { 1, 0 })
	set_preview_title(package_name(item))
end

local function update_cursor()
	if not valid_buf(state.list_buf) or not valid_win(state.list_win) then
		return
	end
	vim.api.nvim_buf_clear_namespace(state.list_buf, cursor_namespace, 0, -1)
	local row = vim.api.nvim_win_get_cursor(state.list_win)[1] - 1
	if state.items[row + 1] then
		vim.api.nvim_buf_set_extmark(state.list_buf, cursor_namespace, row, 0, {
			end_row = row + 1,
			hl_group = "PackListCursor",
			hl_eol = true,
			priority = 100,
		})
	end
	update_preview()
end

local function render()
	if not valid_buf(state.list_buf) or not valid_win(state.list_win) then
		return
	end
	local config = vim.api.nvim_win_get_config(state.list_win)
	config.title = string.format(" Packages (%d) ", #state.items)
	config.title_pos = "left"
	vim.api.nvim_win_set_config(state.list_win, config)
	local width = vim.api.nvim_win_get_width(state.list_win)
	local lines, spans = {}, {}
	for index, item in ipairs(state.items) do
		lines[index], spans[index] = render_item(item, width)
	end
	if #lines == 0 then
		lines = { "No packages installed" }
	end
	vim.api.nvim_set_option_value("modifiable", true, { buf = state.list_buf })
	vim.api.nvim_buf_set_lines(state.list_buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = state.list_buf })
	vim.api.nvim_buf_clear_namespace(state.list_buf, namespace, 0, -1)
	for row, row_spans in ipairs(spans) do
		for _, span in ipairs(row_spans) do
			if span.start_col < #lines[row] then
				vim.api.nvim_buf_set_extmark(state.list_buf, namespace, row - 1, span.start_col, {
					end_col = math.min(span.end_col, #lines[row]),
					hl_group = span.hl,
				})
			end
		end
	end
	update_cursor()
end

local function picker_window(win)
	return win == state.list_win or win == state.preview_win
end

function M.close()
	for _, win in ipairs({ state.list_win, state.preview_win }) do
		if valid_win(win) then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end
	for _, buf in ipairs({ state.list_buf, state.preview_buf }) do
		if valid_buf(buf) then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end
	state.list_win = nil
	state.preview_win = nil
	state.list_buf = nil
	state.preview_buf = nil
	state.source_win = nil
	state.items = {}
	pcall(vim.api.nvim_del_augroup_by_name, "NativePackListPicker")
end

local function open_readme(action)
	if not valid_win(state.list_win) then
		return
	end
	local item = state.items[vim.api.nvim_win_get_cursor(state.list_win)[1]]
	local readme = item and find_readme(item)
	if not readme then
		vim.notify("No README found for this package", vim.log.levels.INFO)
		return
	end
	local source_win = valid_win(state.source_win) and state.source_win or nil
	M.close()
	if source_win and valid_win(source_win) then
		vim.api.nvim_set_current_win(source_win)
	end
	vim.cmd("normal! m'")
	if action == "split" then
		vim.cmd("split")
	elseif action == "vsplit" then
		vim.cmd("vsplit")
	end
	vim.api.nvim_cmd({ cmd = "edit", args = { readme } }, {})
	vim.cmd("normal! ggzv")
end

local function delete_selected()
	if not valid_win(state.list_win) then
		return
	end
	local row = vim.api.nvim_win_get_cursor(state.list_win)[1]
	local item = state.items[row]
	if not item then
		return
	end
	local name = package_name(item)
	if vim.fn.confirm(string.format("Delete package %q?", name), "&Delete\n&Cancel", 2) ~= 1 then
		return
	end
	local ok, err = pcall(vim.pack.del, { name }, { force = true })
	if not ok then
		vim.notify(string.format("Failed to delete %s: %s", name, err), vim.log.levels.ERROR)
		return
	end
	table.remove(state.items, row)
	if valid_win(state.list_win) then
		vim.api.nvim_win_set_cursor(state.list_win, { math.max(1, math.min(row, #state.items)), 0 })
	end
	render()
	vim.notify(string.format("Deleted package %s", name), vim.log.levels.INFO)
end

local function setup_keymaps()
	local map_opts = { buffer = state.list_buf, silent = true, nowait = true }
	vim.keymap.set("n", "<CR>", function()
		open_readme("edit")
	end, vim.tbl_extend("force", map_opts, { desc = "Open package README" }))
	vim.keymap.set("n", "<C-s>", function()
		open_readme("split")
	end, vim.tbl_extend("force", map_opts, { desc = "Open package README in split" }))
	vim.keymap.set("n", "<C-v>", function()
		open_readme("vsplit")
	end, vim.tbl_extend("force", map_opts, { desc = "Open package README in vertical split" }))
	vim.keymap.set("n", "d", delete_selected, vim.tbl_extend("force", map_opts, { desc = "Delete package" }))
	vim.keymap.set("n", "q", M.close, vim.tbl_extend("force", map_opts, { desc = "Close package list" }))
	vim.keymap.set("n", "<Esc>", M.close, vim.tbl_extend("force", map_opts, { desc = "Close package list" }))
end

function M.open()
	if picker_window(vim.api.nvim_get_current_win()) then
		return
	end
	local source_win = vim.api.nvim_get_current_win()
	M.close()
	state.source_win = source_win
	state.items = collect_packages()
	state.list_buf = vim.api.nvim_create_buf(false, true)
	state.preview_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(state.list_buf, "pack-list://packages")
	vim.api.nvim_buf_set_name(state.preview_buf, "pack-list://details")
	for _, buf in ipairs({ state.list_buf, state.preview_buf }) do
		vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
		vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	end
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = state.list_buf })
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = state.preview_buf })
	vim.api.nvim_set_option_value("filetype", "pack-list", { buf = state.list_buf })
	vim.api.nvim_set_option_value("filetype", "markdown", { buf = state.preview_buf })

	local _, configs = float.window_configs(opts, string.format("Packages (%d)", #state.items), "Preview")
	state.preview_win = vim.api.nvim_open_win(state.preview_buf, false, configs.preview)
	state.list_win = vim.api.nvim_open_win(state.list_buf, true, configs.list)
	float.set_window_options(state.preview_win, winhighlight, false)
	float.set_window_options(state.list_win, winhighlight, false)
	setup_keymaps()
	render()

	local group = vim.api.nvim_create_augroup("NativePackListPicker", { clear = true })
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group,
		buffer = state.list_buf,
		callback = update_cursor,
	})
	vim.api.nvim_create_autocmd("WinLeave", {
		group = group,
		callback = function()
			if not picker_window(vim.api.nvim_get_current_win()) then
				return
			end
			vim.schedule(function()
				if valid_win(state.list_win) and not picker_window(vim.api.nvim_get_current_win()) then
					M.close()
				end
			end)
		end,
	})
	vim.api.nvim_create_autocmd("VimResized", {
		group = group,
		callback = function()
			if not valid_win(state.list_win) or not valid_win(state.preview_win) then
				return
			end
			local _, resized = float.window_configs(opts, string.format("Packages (%d)", #state.items), "Preview")
			vim.api.nvim_win_set_config(state.preview_win, resized.preview)
			vim.api.nvim_win_set_config(state.list_win, resized.list)
			render()
		end,
	})
end

function M.setup(user_opts)
	opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_opts or {})
	highlights.apply()
	local group = vim.api.nvim_create_augroup("NativePackList", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		desc = "Restore package list highlights",
		callback = highlights.apply,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		desc = "Close package list",
		callback = M.close,
	})
	vim.api.nvim_create_user_command("ShowPlugins", M.open, {
		desc = "Show installed plugins",
		force = true,
	})
end

return M
