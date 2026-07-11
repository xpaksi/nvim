local M = {}

local progress = {}
local timer
local spinner_index = 1
local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }

local function redraw()
	-- Bang form: progress can belong to a buffer shown in a non-current window.
	pcall(vim.cmd, "redrawstatus!")
end

local function has_progress()
	for _, operations in pairs(progress) do
		if next(operations) then
			return true
		end
	end
	return false
end

local function stop_timer()
	if timer then
		timer:stop()
	end
end

local function sync_timer()
	if not has_progress() then
		stop_timer()
		return
	end
	if not timer then
		timer = vim.uv.new_timer()
	end
	if not timer:is_active() then
		timer:start(0, 120, vim.schedule_wrap(function()
			spinner_index = spinner_index % #spinner + 1
			redraw()
		end))
	end
end

local function close_timer()
	if timer and not timer:is_closing() then
		timer:stop()
		timer:close()
	end
	timer = nil
end

local function progress_event(args)
	local data = args.data or {}
	local params = data.params or {}
	local value = params.value or {}
	local client_id = data.client_id
	local token = params.token
	if not client_id or token == nil or not value.kind then
		return
	end

	local token_key = type(token) .. ":" .. tostring(token)
	if value.kind == "end" then
		if progress[client_id] then
			progress[client_id][token_key] = nil
			if not next(progress[client_id]) then
				progress[client_id] = nil
			end
		end
	else
		progress[client_id] = progress[client_id] or {}
		local operation = progress[client_id][token_key] or {}
		operation.kind = value.kind
		operation.title = value.title or operation.title
		operation.message = value.message or operation.message
		operation.percentage = value.percentage ~= nil and value.percentage or operation.percentage
		progress[client_id][token_key] = operation
	end

	sync_timer()
	redraw()
end

local function clients_for_buffer(bufnr)
	local clients = {}
	local seen_names = {}
	for _, client in ipairs(vim.lsp.get_clients({ bufnr = bufnr })) do
		local stopped = client.is_stopped and client:is_stopped()
		if not stopped and client.name and client.name ~= "" then
			table.insert(clients, client)
			seen_names[client.name] = true
		end
	end

	table.sort(clients, function(a, b)
		if a.name == b.name then
			return a.id < b.id
		end
		return a.name < b.name
	end)

	local names = vim.tbl_keys(seen_names)
	table.sort(names)
	return clients, names
end

local function operation_for(clients)
	for _, client in ipairs(clients) do
		local operations = progress[client.id]
		if operations then
			local tokens = vim.tbl_keys(operations)
			table.sort(tokens)
			if tokens[1] then
				return operations[tokens[1]]
			end
		end
	end
end

local function names_text(names, compact)
	if not compact or #names <= 1 then
		return table.concat(names, " + ")
	end
	return names[1] .. " +" .. (#names - 1)
end

local function first_that_fits(candidates, max_width)
	for _, candidate in ipairs(candidates) do
		if vim.fn.strdisplaywidth(candidate) <= max_width then
			return candidate
		end
	end
	return ""
end

function M.render(bufnr, max_width)
	local clients, names = clients_for_buffer(bufnr)
	if #names == 0 or max_width <= 0 then
		return "", nil
	end

	local all_names = names_text(names, false)
	local compact_names = names_text(names, true)
	local operation = operation_for(clients)
	if not operation then
		local text = first_that_fits({ all_names, compact_names }, max_width)
		return text, "StatusLineLspIdle"
	end

	local title = operation.title or "Working"
	local message = operation.message
	local percentage = operation.percentage ~= nil and (tostring(operation.percentage) .. "%") or nil
	local spin = spinner[spinner_index]
	local function join(...)
		local present = {}
		for index = 1, select("#", ...) do
			local part = select(index, ...)
			if part and part ~= "" then
				table.insert(present, part)
			end
		end
		return table.concat(present, " ")
	end

	local candidates = {
		join(all_names, spin, title, message, percentage),
		join(all_names, spin, title, percentage), -- message is least important
		join(all_names, spin, title),
		join(compact_names, spin, title),
		join(compact_names, spin),
	}
	return first_that_fits(candidates, max_width), "StatusLineLspWorking"
end

function M.setup(group)
	vim.api.nvim_create_autocmd("LspProgress", {
		group = group,
		desc = "Track LSP work-done progress for the statusline",
		callback = progress_event,
	})

	vim.api.nvim_create_autocmd("LspDetach", {
		group = group,
		desc = "Remove detached LSP progress from the statusline",
		callback = function(args)
			-- LspDetach fires per buffer; keep progress while the client is
			-- still attached elsewhere. attached_buffers includes args.buf.
			local client_id = args.data and args.data.client_id
			if client_id then
				local client = vim.lsp.get_client_by_id(client_id)
				if not client or client:is_stopped() or vim.tbl_count(client.attached_buffers) <= 1 then
					progress[client_id] = nil
				end
			end
			sync_timer()
			redraw()
		end,
	})

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		desc = "Close the statusline spinner",
		callback = close_timer,
	})
end

function M.redraw()
	redraw()
end

return M
