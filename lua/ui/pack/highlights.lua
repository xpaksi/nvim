local M = {}

local links = {
	PackListNormal = "NormalFloat",
	PackListBorder = "FloatBorder",
	PackListTitle = "FloatTitle",
	PackListCursor = "CursorLine",
	PackListActive = "DiagnosticOk",
	PackListInactive = "Comment",
	PackListName = "Identifier",
	PackListRevision = "LineNr",
	PackListSource = "Comment",
}

function M.apply()
	for name, target in pairs(links) do
		vim.api.nvim_set_hl(0, name, { link = target, default = true })
	end
end

return M
