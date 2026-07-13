local M = {}

local opencode = require("plugins.opencode.cmd.opencode")

---@class OpenCodeApiOptions
---@field params? table<string, string|number|boolean>
---@field data? string|table
---@field headers? table<string, string>
---@field server? string
---@field standalone? boolean
---@field cwd? string

---@class OpenCodeApiError
---@field code integer
---@field message string
---@field stderr string

---@param operation_id string OpenAPI operation ID, for example `v2.session.list`
---@param options? OpenCodeApiOptions
---@param callback? fun(error: OpenCodeApiError?, response: any)
---@return vim.SystemObj?
function M.call(operation_id, options, callback)
	assert(type(operation_id) == "string" and operation_id ~= "", "operation_id must be a non-empty string")
	options = options or {}

	local binary = opencode.resolved_binary_path ~= "" and opencode.resolved_binary_path or opencode.binary_path
	if binary == "" then
		local error = {
			code = -1,
			message = opencode.binary_name .. " was not found in PATH",
			stderr = "",
		}
		if callback then
			vim.schedule(function()
				callback(error, nil)
			end)
		end
		return nil
	end

	local command = { binary, "api", operation_id }

	if options.standalone then
		table.insert(command, "--standalone")
	end
	if options.server then
		vim.list_extend(command, { "--server", options.server })
	end
	if options.data ~= nil then
		local data = type(options.data) == "string" and options.data or vim.json.encode(options.data)
		vim.list_extend(command, { "--data", data })
	end

	for _, name in ipairs(vim.tbl_keys(options.headers or {})) do
		vim.list_extend(command, { "--header", name .. ":" .. options.headers[name] })
	end
	for _, name in ipairs(vim.tbl_keys(options.params or {})) do
		vim.list_extend(command, { "--param", name .. "=" .. tostring(options.params[name]) })
	end

	return vim.system(command, { cwd = options.cwd, text = true }, function(result)
		if not callback then
			return
		end

		vim.schedule(function()
			if result.code ~= 0 then
				local stderr = vim.trim(result.stderr or "")
				callback({
					code = result.code,
					message = stderr ~= "" and stderr or "OpenCode API request failed",
					stderr = stderr,
				}, nil)
				return
			end

			local stdout = vim.trim(result.stdout or "")
			if stdout == "" then
				callback(nil, nil)
				return
			end

			local ok, response = pcall(vim.json.decode, stdout)
			callback(nil, ok and response or stdout)
		end)
	end)
end

return M
