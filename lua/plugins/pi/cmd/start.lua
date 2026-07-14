local M = {}

local pi = require("plugins.pi.cmd.pi")
local pane = require("plugins.pi.ui.buffer")

---@param options { model: string, cwd?: string }
function M.open(options)
	assert(type(options.model) == "string" and options.model ~= "", "Pi model must be a non-empty string")

	local binary = pi.executable()
	if not binary then
		vim.notify(pi.binary_name .. " was not found in PATH", vim.log.levels.ERROR)
		return
	end

	pane.open({ binary, "--model", options.model }, {
		cwd = options.cwd or vim.fn.getcwd(),
	})
end

return M
