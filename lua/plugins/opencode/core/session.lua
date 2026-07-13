local M = {}

local api = require("plugins.opencode.cmd.api")
local session_ui = require("plugins.opencode.ui.session")

local generation = 0
local list_request
local active_request
local active_timer
local active_refresh_interval = 10000

---@class OpenCodeSession
---@field id string
---@field title string
---@field directory string
---@field agent? string
---@field model? string
---@field provider? string
---@field created? integer
---@field updated? integer
---@field active boolean
---@field raw table

local function clean_text(value)
	if type(value) ~= "string" then
		return nil
	end
	value = vim.trim(value:gsub("%s+", " "))
	return value ~= "" and value or nil
end

local function normalize(session, directory)
	local model = type(session.model) == "table" and session.model or {}
	local location = type(session.location) == "table" and session.location or {}
	local time = type(session.time) == "table" and session.time or {}

	return {
		id = tostring(session.id or ""),
		title = clean_text(session.title) or "Untitled session",
		directory = type(location.directory) == "string" and location.directory or directory,
		agent = clean_text(session.agent),
		model = clean_text(model.id),
		provider = clean_text(model.providerID),
		created = tonumber(time.created),
		updated = tonumber(time.updated),
		active = false,
		raw = session,
	}
end

local function response_sessions(response)
	if type(response) ~= "table" then
		return nil
	end
	if vim.islist(response) then
		return response
	end
	return type(response.data) == "table" and vim.islist(response.data) and response.data or nil
end

local function response_active(response)
	return type(response) == "table" and type(response.data) == "table" and response.data or nil
end

local function stop_active_refresh()
	if active_timer then
		active_timer:stop()
		active_timer:close()
		active_timer = nil
	end
	if active_request then
		pcall(active_request.kill, active_request, 15)
		active_request = nil
	end
end

local function refresh_active(current_generation, directory, notify_errors)
	if current_generation ~= generation or active_request then
		return
	end

	active_request = api.call("v2.session.active", {
		cwd = directory,
	}, function(err, response)
		if current_generation ~= generation then
			return
		end
		active_request = nil
		if err then
			if notify_errors then
				vim.notify("Unable to get active OpenCode sessions: " .. err.message, vim.log.levels.WARN)
			end
			return
		end

		local active = response_active(response)
		if not active then
			if notify_errors then
				vim.notify("OpenCode returned an invalid active session list", vim.log.levels.WARN)
			end
			return
		end
		session_ui.update_active(active)
	end)
end

---Fetch sessions belonging to the current working directory and show them.
---@param options? { directory?: string, on_select?: fun(session: OpenCodeSession) }
---@return vim.SystemObj?
function M.list(options)
	options = options or {}
	local directory = vim.fs.normalize(options.directory or vim.fn.getcwd())

	generation = generation + 1
	local current_generation = generation
	stop_active_refresh()
	if list_request then
		pcall(list_request.kill, list_request, 15)
		list_request = nil
	end

	list_request = api.call("v2.session.list", {
		params = { directory = directory },
		cwd = directory,
	}, function(err, response)
		if current_generation ~= generation then
			return
		end
		list_request = nil
		if err then
			vim.notify("Unable to list OpenCode sessions: " .. err.message, vim.log.levels.ERROR)
			return
		end

		local sessions = response_sessions(response)
		if not sessions then
			vim.notify("OpenCode returned an invalid session list", vim.log.levels.ERROR)
			return
		end

		local items = {}
		for _, session in ipairs(sessions) do
			if type(session) == "table" then
				items[#items + 1] = normalize(session, directory)
			end
		end
		table.sort(items, function(a, b)
			return (a.updated or a.created or 0) > (b.updated or b.created or 0)
		end)

		session_ui.open(items, {
			directory = directory,
			on_select = options.on_select,
			on_close = function()
				if current_generation == generation then
					generation = generation + 1
					stop_active_refresh()
				end
			end,
		})

		refresh_active(current_generation, directory, true)

		active_timer = vim.uv.new_timer()
		if active_timer == nil then
			vim.notify("Unable to create active session refresh timer", vim.log.levels.ERROR)
			return
		end

		active_timer:start(
			active_refresh_interval,
			active_refresh_interval,
			vim.schedule_wrap(function()
				refresh_active(current_generation, directory, false)
			end)
		)
	end)

	return list_request
end

function M.cancel()
	generation = generation + 1
	stop_active_refresh()
	if list_request then
		pcall(list_request.kill, list_request, 15)
		list_request = nil
	end
end

return M
