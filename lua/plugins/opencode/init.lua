local M = {}

local session = require("plugins.opencode.core.session")
local start = require("plugins.opencode.cmd.start")

local default_model = "openai/gpt-5.6-sol"

function M.setup()
	vim.api.nvim_create_user_command("Opencode", function(command)
		if #command.fargs == 0 then
			start.open({ model = default_model })
			return
		end

		if vim.deep_equal(command.fargs, { "session", "list" }) then
			session.list({
				on_select = function(selected)
					start.open({
						model = default_model,
						session = selected.id,
						cwd = selected.directory,
					})
				end,
			})
			return
		end

		vim.notify("Usage: Opencode [session list]", vim.log.levels.ERROR)
	end, {
		force = true,
		nargs = "*",
		complete = function(argument, command_line)
			local prefix = command_line:sub(1, #command_line - #argument)
			local args = vim.split(prefix, "%s+", { trimempty = true })
			return #args == 1 and { "session" } or #args == 2 and args[2] == "session" and { "list" } or {}
		end,
		desc = "Open OpenCode or manage its sessions",
	})
end

return M
