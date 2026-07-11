local M = {}

local links = {
	BufferlineFill = "TabLineFill",
	BufferlineActive = "TabLineSel",
	BufferlineInactive = "TabLine",
	BufferlineModified = "DiagnosticWarn",
	BufferlineTree = "TabLineFill",
	BufferManagerNormal = "NormalFloat",
	BufferManagerBorder = "FloatBorder",
	BufferManagerTitle = "FloatTitle",
	BufferManagerCursor = "CursorLine",
	BufferManagerNumber = "LineNr",
	BufferManagerName = "Normal",
	BufferManagerPath = "Comment",
	BufferManagerModified = "DiagnosticWarn",
}

function M.apply()
	for name, target in pairs(links) do
		vim.api.nvim_set_hl(0, name, { link = target, default = true })
	end
end

return M
