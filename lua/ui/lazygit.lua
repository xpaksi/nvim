local M = {}

function M.setup()
	require("ui.terminal").setup({
		name = "Lazygit",
		command = { "lazygit" },
		desc = "Open lazygit in a floating terminal",
	})
end

return M
