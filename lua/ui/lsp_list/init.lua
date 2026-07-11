local M = {}

local highlights = require("ui.lsp_list.highlights")
local float = require("ui.float")

local defaults = {
	width = 0.8,
	height = 0.8,
	preview_size = 0.5,
	flex_width = 130,
	keymaps = {
		symbols = "ds",
		buffer_diagnostics = "dd",
		workspace_diagnostics = "dD",
		references = "dr",
	},
}

local opts = vim.deepcopy(defaults)
local namespace = vim.api.nvim_create_namespace("native_lsp_list")
local cursor_namespace = vim.api.nvim_create_namespace("native_lsp_list_cursor")
local list_winhighlight = "Normal:LspListNormal,FloatBorder:LspListBorder,FloatTitle:LspListTitle"
local state = {
	generation = 0,
	items = {},
}

local symbol_kinds = vim.lsp.protocol.SymbolKind
local severities = {
	[vim.diagnostic.severity.ERROR] = { label = "Error", hl = "LspListError" },
	[vim.diagnostic.severity.WARN] = { label = "Warn", hl = "LspListWarn" },
	[vim.diagnostic.severity.INFO] = { label = "Info", hl = "LspListInfo" },
	[vim.diagnostic.severity.HINT] = { label = "Hint", hl = "LspListHint" },
}

local function valid_buf(buf)
	return buf and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function normalize_message(message)
	return vim.trim((message or ""):gsub("%s+", " "))
end

local function display_path(path)
	if not path or path == "" then
		return ""
	end
	local relative = vim.fs.relpath(vim.fn.getcwd(), path)
	return relative or path
end

local function uri_to_path(uri)
	local ok, path = pcall(vim.uri_to_fname, uri)
	return ok and path or uri
end

local function item_path(item)
	if item.path then
		return item.path
	end
	if item.uri then
		return uri_to_path(item.uri)
	end
	if item.bufnr and valid_buf(item.bufnr) then
		return vim.api.nvim_buf_get_name(item.bufnr)
	end
	return ""
end

local function target_buffer(item)
	if item.bufnr and valid_buf(item.bufnr) then
		return item.bufnr
	end
	if not item.uri then
		return nil
	end
	local ok, bufnr = pcall(vim.uri_to_bufnr, item.uri)
	return ok and bufnr or nil
end

local function byte_col(item, bufnr)
	if item.byte_col then
		return item.col or 0
	end
	local line = item.line or 0
	local text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1] or ""
	local ok, col = pcall(vim.str_byteindex, text, item.encoding or "utf-16", item.col or 0, false)
	return ok and col or 0
end

local function add_part(parts, text, hl)
	local start_col = 0
	for _, part in ipairs(parts) do
		start_col = start_col + #part.text
	end
	parts[#parts + 1] = { text = text, hl = hl, start_col = start_col, end_col = start_col + #text }
end

local function render_item(item, width)
	local parts = {}
	local location = string.format(":%d:%d", (item.line or 0) + 1, (item.col or 0) + 1)

	if item.type == "symbol" then
		add_part(parts, string.format("%-12s ", item.kind_name or "Symbol"), "LspListKind")
		add_part(parts, item.name or "", "LspListName")
		if item.detail and item.detail ~= "" then
			add_part(parts, "  " .. item.detail, "LspListDetail")
		end
	elseif item.type == "diagnostic" then
		local severity = severities[item.severity]
		add_part(
			parts,
			string.format("%-5s ", severity and severity.label or "Diagnostic"),
			severity and severity.hl or "LspListInfo"
		)
		add_part(parts, normalize_message(item.message), nil)
		if item.source and item.source ~= "" then
			add_part(parts, "  " .. item.source, "LspListDetail")
		end
	else
		add_part(parts, normalize_message(item.text), nil)
	end

	local path = display_path(item_path(item))
	local suffix = "  " .. path .. location
	local content = ""
	for _, part in ipairs(parts) do
		content = content .. part.text
	end
	local available = math.max(1, width - vim.fn.strdisplaywidth(suffix) - 1)
	local clipped = float.truncate(content, available)
	local line = float.truncate(clipped .. suffix, width)

	local content_bytes = math.min(#clipped, #line)
	local spans = {}
	for _, part in ipairs(parts) do
		if part.hl and part.start_col < content_bytes then
			spans[#spans + 1] =
				{ start_col = part.start_col, end_col = math.min(part.end_col, content_bytes), hl = part.hl }
		end
	end
	if #line > content_bytes then
		spans[#spans + 1] = { start_col = content_bytes, end_col = #line, hl = "LspListPosition" }
	end
	return line, spans
end

local function clear_preview_highlight()
	if valid_buf(state.preview_target) then
		vim.api.nvim_buf_clear_namespace(state.preview_target, namespace, 0, -1)
	end
	state.preview_target = nil
end

local function set_preview_title(title)
	local config = vim.api.nvim_win_get_config(state.preview_win)
	config.title = title
	config.title_pos = "left"
	vim.api.nvim_win_set_config(state.preview_win, config)
end

local function reset_preview()
	clear_preview_highlight()
	if valid_buf(state.preview_buf) and vim.api.nvim_win_get_buf(state.preview_win) ~= state.preview_buf then
		vim.api.nvim_win_set_buf(state.preview_win, state.preview_buf)
		vim.api.nvim_set_option_value("number", false, { win = state.preview_win })
		set_preview_title(" Preview ")
	end
end

local function update_preview()
	if not valid_win(state.list_win) or not valid_win(state.preview_win) then
		return
	end
	local row = vim.api.nvim_win_get_cursor(state.list_win)[1]
	local item = state.items[row]
	if not item then
		reset_preview()
		return
	end
	local bufnr = target_buffer(item)
	if not bufnr then
		reset_preview()
		return
	end
	if not vim.api.nvim_buf_is_loaded(bufnr) then
		pcall(vim.fn.bufload, bufnr)
	end
	if not vim.api.nvim_buf_is_loaded(bufnr) then
		reset_preview()
		return
	end

	clear_preview_highlight()
	state.preview_target = bufnr
	vim.api.nvim_win_set_buf(state.preview_win, bufnr)
	vim.api.nvim_set_option_value("number", true, { win = state.preview_win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = state.preview_win })
	vim.api.nvim_set_option_value("cursorline", false, { win = state.preview_win })

	local line = item.line or 0
	local source_text = vim.api.nvim_buf_get_lines(bufnr, line, line + 1, false)[1]
	if source_text then
		vim.api.nvim_buf_set_extmark(bufnr, namespace, line, 0, {
			end_row = line + 1,
			hl_group = "LspListCursor",
			hl_eol = true,
			priority = 100,
		})
		local col = byte_col(item, bufnr)
		local end_col = col + 1
		if item.end_col then
			if item.end_line and item.end_line ~= item.line then
				end_col = #source_text
			elseif item.byte_col then
				end_col = math.max(end_col, item.end_col)
			else
				local ok, converted =
					pcall(vim.str_byteindex, source_text, item.encoding or "utf-16", item.end_col, false)
				if ok then
					end_col = math.max(end_col, converted)
				end
			end
		end
		local start_col = math.min(#source_text, col)
		vim.api.nvim_buf_set_extmark(bufnr, namespace, line, start_col, {
			end_col = math.min(#source_text, end_col),
			hl_group = "LspListMatch",
			priority = 110,
		})
		pcall(vim.api.nvim_win_set_cursor, state.preview_win, { line + 1, start_col })
		vim.api.nvim_win_call(state.preview_win, function()
			vim.cmd("normal! zz")
		end)
	end

	local path = display_path(item_path(item))
	set_preview_title(string.format(" %s:%d ", path ~= "" and path or "Preview", line + 1))
end

local function update_cursor()
	if not valid_buf(state.list_buf) or not valid_win(state.list_win) then
		return
	end
	vim.api.nvim_buf_clear_namespace(state.list_buf, cursor_namespace, 0, -1)
	local cursor_row = vim.api.nvim_win_get_cursor(state.list_win)[1] - 1
	if state.items[cursor_row + 1] then
		vim.api.nvim_buf_set_extmark(state.list_buf, cursor_namespace, cursor_row, 0, {
			end_row = cursor_row + 1,
			hl_group = "LspListCursor",
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
	local width = vim.api.nvim_win_get_width(state.list_win)
	local lines = {}
	local spans = {}
	for index, item in ipairs(state.items) do
		lines[index], spans[index] = render_item(item, width)
	end
	if #lines == 0 then
		lines = { "No results" }
	end

	vim.api.nvim_set_option_value("modifiable", true, { buf = state.list_buf })
	vim.api.nvim_buf_set_lines(state.list_buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = state.list_buf })
	vim.api.nvim_buf_clear_namespace(state.list_buf, namespace, 0, -1)

	for row, row_spans in ipairs(spans) do
		for _, span in ipairs(row_spans) do
			vim.api.nvim_buf_set_extmark(state.list_buf, namespace, row - 1, span.start_col, {
				end_col = span.end_col,
				hl_group = span.hl,
			})
		end
	end
	update_cursor()
end

local function picker_window(win)
	return win == state.list_win or win == state.preview_win
end

function M.close()
	state.generation = state.generation + 1
	if state.cancel_request then
		pcall(state.cancel_request)
		state.cancel_request = nil
	end
	clear_preview_highlight()
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
	state.items = {}
	pcall(vim.api.nvim_del_augroup_by_name, "NativeLspListPicker")
end

local function jump(action)
	if not valid_win(state.list_win) then
		return
	end
	local item = state.items[vim.api.nvim_win_get_cursor(state.list_win)[1]]
	if not item then
		return
	end
	local bufnr = target_buffer(item)
	if not bufnr then
		return
	end
	if not vim.api.nvim_buf_is_loaded(bufnr) then
		pcall(vim.fn.bufload, bufnr)
	end
	local target_win = valid_win(state.source_win) and state.source_win or nil
	M.close()
	if target_win and valid_win(target_win) then
		vim.api.nvim_set_current_win(target_win)
	end
	vim.cmd("normal! m'")
	if action == "split" then
		vim.cmd("split")
	elseif action == "vsplit" then
		vim.cmd("vsplit")
	end
	vim.bo[bufnr].buflisted = true
	vim.api.nvim_win_set_buf(0, bufnr)
	local col = byte_col(item, bufnr)
	pcall(vim.api.nvim_win_set_cursor, 0, { (item.line or 0) + 1, col })
	vim.cmd("normal! zvzz")
end

local function filter_symbols(kind, label)
	if state.kind ~= "symbols" or not valid_win(state.list_win) then
		return
	end
	if state.symbol_filter == kind then
		state.symbol_filter = nil
		state.items = state.all_items
		state.title = state.base_title
	else
		state.symbol_filter = kind
		state.items = vim.tbl_filter(function(item)
			return item.kind == kind
		end, state.all_items)
		state.title = string.format("%s: %s", state.base_title, label)
	end
	local config = vim.api.nvim_win_get_config(state.list_win)
	config.title = " " .. state.title .. " "
	config.title_pos = "left"
	vim.api.nvim_win_set_config(state.list_win, config)
	vim.api.nvim_win_set_cursor(state.list_win, { 1, 0 })
	render()
end

local function setup_buffer_keymaps()
	local map_opts = { buffer = state.list_buf, silent = true, nowait = true }
	vim.keymap.set("n", "<CR>", function()
		jump("edit")
	end, vim.tbl_extend("force", map_opts, { desc = "Open location" }))
	vim.keymap.set("n", "q", M.close, vim.tbl_extend("force", map_opts, { desc = "Close list" }))
	vim.keymap.set("n", "<Esc>", M.close, vim.tbl_extend("force", map_opts, { desc = "Close list" }))
	vim.keymap.set("n", "<C-s>", function()
		jump("split")
	end, vim.tbl_extend("force", map_opts, { desc = "Open location in split" }))
	vim.keymap.set("n", "<C-v>", function()
		jump("vsplit")
	end, vim.tbl_extend("force", map_opts, { desc = "Open location in vertical split" }))
	if state.kind == "symbols" then
		vim.keymap.set("n", "f", function()
			filter_symbols(vim.lsp.protocol.SymbolKind.Function, "Functions")
		end, vim.tbl_extend("force", map_opts, { desc = "Filter function symbols" }))
		vim.keymap.set("n", "v", function()
			filter_symbols(vim.lsp.protocol.SymbolKind.Variable, "Variables")
		end, vim.tbl_extend("force", map_opts, { desc = "Filter variable symbols" }))
	end
end

local function open(items, title, kind, source_buf, source_win)
	M.close()
	state.generation = state.generation + 1
	state.items = items
	state.all_items = items
	state.symbol_filter = nil
	state.title = title
	state.base_title = title
	state.kind = kind
	state.source_buf = source_buf
	state.source_win = source_win

	state.list_buf = vim.api.nvim_create_buf(false, true)
	state.preview_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(state.list_buf, "lsp-list://" .. kind)
	vim.api.nvim_buf_set_name(state.preview_buf, "lsp-list://preview")
	for _, buf in ipairs({ state.list_buf, state.preview_buf }) do
		vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
		vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
		vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	end
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = state.list_buf })
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = state.preview_buf })
	vim.api.nvim_set_option_value("filetype", "lsp-list", { buf = state.list_buf })
	vim.api.nvim_set_option_value("filetype", "lsp-list-preview", { buf = state.preview_buf })

	local layout, configs = float.window_configs(opts, title, "Preview")
	state.layout = layout
	state.preview_win = vim.api.nvim_open_win(state.preview_buf, false, configs.preview)
	state.list_win = vim.api.nvim_open_win(state.list_buf, true, configs.list)
	float.set_window_options(state.preview_win, list_winhighlight, false)
	float.set_window_options(state.list_win, list_winhighlight, false)
	setup_buffer_keymaps()
	render()

	local group = vim.api.nvim_create_augroup("NativeLspListPicker", { clear = true })
	vim.api.nvim_create_autocmd("CursorMoved", {
		group = group,
		buffer = state.list_buf,
		callback = update_cursor,
	})
	vim.api.nvim_create_autocmd("WinLeave", {
		group = group,
		callback = function()
			local leaving = vim.api.nvim_get_current_win()
			if not picker_window(leaving) then
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
			local new_layout, new_configs = float.window_configs(opts, state.title, "Preview")
			state.layout = new_layout
			vim.api.nvim_win_set_config(state.preview_win, new_configs.preview)
			vim.api.nvim_win_set_config(state.list_win, new_configs.list)
			render()
		end,
	})
end

local function current_context()
	return vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
end

local function supported_clients(bufnr, method)
	return vim.lsp.get_clients({ bufnr = bufnr, method = method })
end

local function flatten_symbols(symbols, client, bufnr, uri, parent, items)
	for _, symbol in ipairs(symbols or {}) do
		if symbol.location then
			local range = symbol.location.range
			items[#items + 1] = {
				type = "symbol",
				name = symbol.name,
				kind = symbol.kind,
				kind_name = symbol_kinds[symbol.kind] or "Symbol",
				detail = symbol.containerName,
				uri = symbol.location.uri,
				line = range.start.line,
				col = range.start.character,
				end_line = range["end"].line,
				end_col = range["end"].character,
				encoding = client.offset_encoding,
			}
		else
			local range = symbol.selectionRange or symbol.range
			items[#items + 1] = {
				type = "symbol",
				name = symbol.name,
				kind = symbol.kind,
				kind_name = symbol_kinds[symbol.kind] or "Symbol",
				detail = symbol.detail or parent,
				uri = uri,
				bufnr = bufnr,
				line = range.start.line,
				col = range.start.character,
				end_line = range["end"].line,
				end_col = range["end"].character,
				encoding = client.offset_encoding,
			}
			flatten_symbols(symbol.children, client, bufnr, uri, symbol.name, items)
		end
	end
end

function M.symbols()
	if picker_window(vim.api.nvim_get_current_win()) then
		return
	end
	local bufnr, winid = current_context()
	local clients = supported_clients(bufnr, "textDocument/documentSymbol")
	if #clients == 0 then
		vim.notify("No document symbol provider is attached", vim.log.levels.INFO)
		return
	end
	local generation = state.generation + 1
	state.generation = generation
	if state.cancel_request then
		pcall(state.cancel_request)
		state.cancel_request = nil
	end
	local uri = vim.uri_from_bufnr(bufnr)
	state.cancel_request = vim.lsp.buf_request_all(bufnr, "textDocument/documentSymbol", function()
		return { textDocument = { uri = uri } }
	end, function(responses)
		if generation ~= state.generation then
			return
		end
		state.cancel_request = nil
		local items = {}
		for client_id, response in pairs(responses) do
			local client = vim.lsp.get_client_by_id(client_id)
			if client and response.result then
				flatten_symbols(response.result, client, bufnr, uri, nil, items)
			end
		end
		table.sort(items, function(a, b)
			return a.line == b.line and a.col < b.col or a.line < b.line
		end)
		open(items, "Symbols", "symbols", bufnr, winid)
	end)
end

local function diagnostic_items(diagnostics)
	local items = {}
	for _, diagnostic in ipairs(diagnostics) do
		items[#items + 1] = {
			type = "diagnostic",
			message = diagnostic.message,
			severity = diagnostic.severity,
			source = diagnostic.source,
			code = diagnostic.code,
			bufnr = diagnostic.bufnr,
			line = diagnostic.lnum,
			col = diagnostic.col,
			end_line = diagnostic.end_lnum,
			end_col = diagnostic.end_col,
			byte_col = true,
			path = valid_buf(diagnostic.bufnr) and vim.api.nvim_buf_get_name(diagnostic.bufnr) or nil,
		}
	end
	table.sort(items, function(a, b)
		local a_path, b_path = item_path(a), item_path(b)
		if a_path ~= b_path then
			return a_path < b_path
		end
		if a.line ~= b.line then
			return a.line < b.line
		end
		return a.col < b.col
	end)
	return items
end

function M.buffer_diagnostics()
	if picker_window(vim.api.nvim_get_current_win()) then
		return
	end
	local bufnr, winid = current_context()
	open(diagnostic_items(vim.diagnostic.get(bufnr)), "Buffer Diagnostics", "buffer-diagnostics", bufnr, winid)
end

local function workspace_roots(bufnr)
	local roots = {}
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
		for _, folder in ipairs(client.workspace_folders or {}) do
			local ok, path = pcall(vim.uri_to_fname, folder.uri)
			if ok then
				roots[vim.fs.normalize(path)] = true
			end
		end
		if client.root_dir then
			roots[vim.fs.normalize(client.root_dir)] = true
		end
	end
	if not next(roots) then
		roots[vim.fs.normalize(vim.fn.getcwd())] = true
	end
	return vim.tbl_keys(roots)
end

local function path_in_roots(path, roots)
	path = vim.fs.normalize(path)
	for _, root in ipairs(roots) do
		if path == root or path:sub(1, #root + 1) == root .. "/" then
			return true
		end
	end
	return false
end

local function known_workspace_diagnostics(bufnr)
	local roots = workspace_roots(bufnr)
	return vim.tbl_filter(function(diagnostic)
		if not valid_buf(diagnostic.bufnr) then
			return false
		end
		local path = vim.api.nvim_buf_get_name(diagnostic.bufnr)
		return path ~= "" and path_in_roots(path, roots)
	end, vim.diagnostic.get(nil))
end

function M.workspace_diagnostics()
	if picker_window(vim.api.nvim_get_current_win()) then
		return
	end
	local bufnr, winid = current_context()
	open(
		diagnostic_items(known_workspace_diagnostics(bufnr)),
		"Workspace Diagnostics",
		"workspace-diagnostics",
		bufnr,
		winid
	)
	for _, client in ipairs(supported_clients(bufnr, "workspace/diagnostic")) do
		vim.lsp.buf.workspace_diagnostics({ client_id = client.id })
	end
end

local function reference_text(path, line, file_cache)
	local target = vim.fn.bufnr(path)
	if target ~= -1 and vim.api.nvim_buf_is_loaded(target) then
		return vim.api.nvim_buf_get_lines(target, line, line + 1, false)[1] or ""
	end
	local lines = file_cache[path]
	if lines == nil then
		local ok, read = pcall(vim.fn.readfile, path)
		lines = ok and read or false
		file_cache[path] = lines
	end
	return lines and lines[line + 1] or ""
end

function M.references()
	if picker_window(vim.api.nvim_get_current_win()) then
		return
	end
	local bufnr, winid = current_context()
	local clients = supported_clients(bufnr, "textDocument/references")
	if #clients == 0 then
		vim.notify("No references provider is attached", vim.log.levels.INFO)
		return
	end
	local generation = state.generation + 1
	state.generation = generation
	if state.cancel_request then
		pcall(state.cancel_request)
		state.cancel_request = nil
	end
	state.cancel_request = vim.lsp.buf_request_all(bufnr, "textDocument/references", function(client)
		local params = vim.lsp.util.make_position_params(winid, client.offset_encoding)
		params.context = { includeDeclaration = true }
		return params
	end, function(responses)
		if generation ~= state.generation then
			return
		end
		state.cancel_request = nil
		local items, seen, file_cache = {}, {}, {}
		for client_id, response in pairs(responses) do
			local client = vim.lsp.get_client_by_id(client_id)
			if client then
				for _, location in ipairs(response.result or {}) do
					local range = location.range
					local key = table.concat({ location.uri, range.start.line, range.start.character }, ":")
					if not seen[key] then
						seen[key] = true
						local path = uri_to_path(location.uri)
						items[#items + 1] = {
							type = "reference",
							uri = location.uri,
							path = path,
							line = range.start.line,
							col = range.start.character,
							end_line = range["end"].line,
							end_col = range["end"].character,
							encoding = client.offset_encoding,
							text = reference_text(path, range.start.line, file_cache),
						}
					end
				end
			end
		end
		table.sort(items, function(a, b)
			if a.path ~= b.path then
				return a.path < b.path
			end
			return a.line == b.line and a.col < b.col or a.line < b.line
		end)
		open(items, "References", "references", bufnr, winid)
	end)
end

function M.setup(user_opts)
	opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_opts or {})
	highlights.apply()

	local group = vim.api.nvim_create_augroup("NativeLspList", { clear = true })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		desc = "Restore LSP list highlights",
		callback = highlights.apply,
	})
	vim.api.nvim_create_autocmd("DiagnosticChanged", {
		group = group,
		desc = "Refresh open diagnostic list",
		callback = function()
			if not valid_win(state.list_win) then
				return
			end
			if state.kind == "buffer-diagnostics" then
				state.items =
					diagnostic_items(valid_buf(state.source_buf) and vim.diagnostic.get(state.source_buf) or {})
				state.all_items = state.items
				render()
			elseif state.kind == "workspace-diagnostics" then
				state.items = diagnostic_items(known_workspace_diagnostics(state.source_buf))
				state.all_items = state.items
				render()
			end
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		desc = "Close LSP list",
		callback = M.close,
	})

	local maps = opts.keymaps
	vim.keymap.set("n", maps.symbols, M.symbols, { desc = "Show document symbols" })
	vim.keymap.set("n", maps.buffer_diagnostics, M.buffer_diagnostics, { desc = "Show buffer diagnostics" })
	vim.keymap.set("n", maps.workspace_diagnostics, M.workspace_diagnostics, { desc = "Show workspace diagnostics" })
	vim.keymap.set("n", maps.references, M.references, { desc = "Show references" })
end

return M
