local M = {}

local opencode = require("plugins.opencode.cmd.opencode")
local pane = require("plugins.opencode.ui.buffer")

---@param options { model: string, session?: string, cwd?: string }
function M.open(options)
	assert(type(options.model) == "string" and options.model ~= "", "OpenCode model must be a non-empty string")

	local binary = opencode.resolved_binary_path ~= "" and opencode.resolved_binary_path or opencode.binary_path
	if binary == "" then
		vim.notify(opencode.binary_name .. " was not found in PATH", vim.log.levels.ERROR)
		return
	end

	local command = { binary, "mini", "-m", options.model }
	if options.session then
		vim.list_extend(command, { "-s", options.session })
	end
	pane.open(command, {
		cwd = options.cwd or vim.fn.getcwd(),
		replace = options.session ~= nil,
	})
end

return M
