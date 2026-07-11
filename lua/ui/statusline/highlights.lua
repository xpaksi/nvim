local M = {}

local links = {
	StatusLineModeNormal = "Function",
	StatusLineModeInsert = "String",
	StatusLineModeVisual = "Keyword",
	StatusLineModeReplace = "DiagnosticError",
	StatusLineModeCommand = "Type",
	StatusLineModeTerminal = "Special",
	StatusLineModeSelect = "Keyword",
	StatusLineFilename = "StatusLine",
	StatusLineModified = "DiagnosticWarn",
	StatusLineReadonly = "DiagnosticWarn",
	StatusLineLspIdle = "DiagnosticOk",
	StatusLineLspWorking = "DiagnosticInfo",
}

function M.apply()
	for name, target in pairs(links) do
		vim.api.nvim_set_hl(0, name, { link = target, default = true })
	end
end

return M
