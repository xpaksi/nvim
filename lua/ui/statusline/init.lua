local filename = require("ui.statusline.filename")
local highlights = require("ui.statusline.highlights")
local lsp = require("ui.statusline.lsp")
local mode = require("ui.statusline.mode")

local M = {}

local function escape(text)
	-- A literal percent starts a statusline item unless doubled.
	return (text or ""):gsub("%%", "%%%%"):gsub("[\r\n]", " ")
end

local function statusline_window()
	local winid = tonumber(vim.g.statusline_winid)
	if winid and vim.api.nvim_win_is_valid(winid) then
		return winid
	end
	return vim.api.nvim_get_current_win()
end

function M.render()
	local winid = statusline_window()
	local active = winid == vim.api.nvim_get_current_win()
	local bufnr = vim.api.nvim_win_get_buf(winid)
	local window_width = vim.api.nvim_win_get_width(winid)

	-- The global mode only describes the active window.
	local mode_text, mode_highlight = "", nil
	if active then
		mode_text, mode_highlight = mode.get()
	end

	-- Reserve enough space to keep the primary filename useful. The LSP
	-- renderer then progressively drops details to fit its own budget.
	local preliminary_file = filename.get(bufnr, winid, window_width)
	local filename_reserve = math.min(preliminary_file.width, math.max(8, math.floor(window_width * 0.45)))
	local lsp_budget = math.max(0, window_width - vim.fn.strdisplaywidth(mode_text) - filename_reserve - 5)
	local lsp_text, lsp_highlight = lsp.render(bufnr, lsp_budget)
	local right_width = vim.fn.strdisplaywidth(lsp_text)
	local filename_budget = math.max(1, window_width - vim.fn.strdisplaywidth(mode_text) - right_width - 5)
	local file = filename.get(bufnr, winid, filename_budget)

	local left
	if active then
		left = table.concat({
			"%#" .. mode_highlight .. "#",
			escape(mode_text),
			"%*  %#StatusLineFilename#",
			escape(file.text),
			"%*",
		})
	else
		-- Plain text inherits StatusLineNC, keeping inactive windows dim.
		left = " " .. escape(file.text)
	end
	if file.modified ~= "" then
		left = left .. "%#StatusLineModified#" .. escape(file.modified) .. "%*"
	end
	if file.readonly ~= "" then
		left = left .. "%#StatusLineReadonly#" .. escape(file.readonly) .. "%*"
	end

	if lsp_text == "" then
		return left
	end
	return left .. "%=" .. "%#" .. lsp_highlight .. "#" .. escape(lsp_text) .. " %*"
end

function M.setup()
	vim.opt.showmode = false
	vim.opt.laststatus = 2
	highlights.apply()

	local group = vim.api.nvim_create_augroup("NativeStatusline", { clear = true })
	lsp.setup(group)
	vim.api.nvim_create_autocmd({ "LspAttach", "BufEnter", "BufDelete", "ModeChanged" }, {
		group = group,
		desc = "Refresh the native statusline",
		callback = lsp.redraw,
	})
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		desc = "Restore native statusline highlights",
		callback = function()
			highlights.apply()
			lsp.redraw()
		end,
	})

	vim.o.statusline = "%!v:lua.require'ui.statusline'.render()"
end

return M
