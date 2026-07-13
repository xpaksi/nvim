local M = {}

local links = {
	NotificationNormal = "NormalFloat",
	NotificationBorder = "FloatBorder",
	NotificationTitle = "FloatTitle",
	NotificationLoading = "DiagnosticWarn",
	NotificationSuccess = "DiagnosticOk",
	NotificationError = "DiagnosticError",
	NotificationWarn = "DiagnosticWarn",
	NotificationInfo = "DiagnosticInfo",
}

function M.apply()
	for name, target in pairs(links) do
		vim.api.nvim_set_hl(0, name, { link = target, default = true })
	end
end

return M
