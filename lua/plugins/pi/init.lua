local M = {}

local start = require("plugins.pi.cmd.start")

local default_model = "openai-codex/gpt-5.6-sol"

function M.setup()
	vim.api.nvim_create_user_command("Pi", function()
		start.open({ model = default_model })
	end, {
		force = true,
		nargs = 0,
		desc = "Open Pi",
	})
end

return M
