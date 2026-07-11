local M = {}

local links = {
	LspListNormal = "NormalFloat",
	LspListBorder = "FloatBorder",
	LspListTitle = "FloatTitle",
	LspListCursor = "CursorLine",
	LspListKind = "Type",
	LspListName = "Identifier",
	LspListDetail = "Comment",
	LspListPosition = "LineNr",
	LspListError = "DiagnosticError",
	LspListWarn = "DiagnosticWarn",
	LspListInfo = "DiagnosticInfo",
	LspListHint = "DiagnosticHint",
	LspListMatch = "IncSearch",
}

function M.apply()
	for name, target in pairs(links) do
		vim.api.nvim_set_hl(0, name, { link = target, default = true })
	end
end

return M
