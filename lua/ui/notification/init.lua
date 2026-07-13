local highlights = require("ui.notification.highlights")

local M = {}

local defaults = {
	border = nil,
	max_width = 50,
	min_width = 24,
	padding = 1,
	timeout = 3000,
	zindex = 200,
}

local kinds = {
	loading = { icon = "⠋", title = "Loading", highlight = "NotificationLoading" },
	success = { icon = "", title = "Success", highlight = "NotificationSuccess" },
	error = { icon = "", title = "Error", highlight = "NotificationError" },
	warn = { icon = "", title = "Warning", highlight = "NotificationWarn" },
	info = { icon = "", title = "Info", highlight = "NotificationInfo" },
}

local levels = {
	[vim.log.levels.ERROR] = "error",
	[vim.log.levels.WARN] = "warn",
}

local spinner = { "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" }
local notifications = {}
local next_id = 0
local opts = vim.deepcopy(defaults)
local original_notify = vim.notify

local function resolve_border()
	if opts.border then
		return opts.border
	end
	local winborder = vim.fn.exists("&winborder") == 1 and vim.o.winborder or ""
	-- Comma-separated winborder values are custom character lists that
	-- nvim_open_win only accepts as a table, so treat them as unsupported.
	if winborder == "" or winborder:find(",", 1, true) then
		return "rounded"
	end
	return winborder
end

local function icon_for(notification)
	if notification.kind == "loading" then
		return spinner[notification.frame or 1]
	end
	return kinds[notification.kind].icon
end

local function stop_timer(timer)
	if timer and not timer:is_closing() then
		timer:stop()
		timer:close()
	end
end

local function remove(index)
	local notification = table.remove(notifications, index)
	stop_timer(notification.timeout_timer)
	stop_timer(notification.spinner_timer)
	if vim.api.nvim_win_is_valid(notification.win) then
		vim.api.nvim_win_close(notification.win, true)
	end
	if notification.on_close then
		pcall(notification.on_close)
	end
end

local function reflow()
	local bottom = math.max(1, vim.o.lines - vim.o.cmdheight)
	for index = #notifications, 1, -1 do
		local notification = notifications[index]
		if not vim.api.nvim_win_is_valid(notification.win) then
			remove(index)
		else
			local config = vim.api.nvim_win_get_config(notification.win)
			local extent = notification.border_extent
			bottom = bottom - (config.height + extent * 2)
			if bottom < 0 then
				remove(index)
			else
				config.relative = "editor"
				config.row = bottom
				config.col = math.max(0, vim.o.columns - config.width - extent * 2)
				vim.api.nvim_win_set_config(notification.win, config)
			end
			bottom = bottom - 1
		end
	end
end

local function find(id)
	for index, notification in ipairs(notifications) do
		if notification.id == id then
			return notification, index
		end
	end
end

function M.dismiss(id)
	local notification, index = find(id)
	if not notification then
		return
	end
	remove(index)
	reflow()
end

local function text_lines(message)
	if type(message) == "table" then
		return vim.tbl_map(tostring, message)
	end
	return vim.split(tostring(message or ""), "\n", { plain = true })
end

local function truncate(text, width)
	if vim.fn.strdisplaywidth(text) <= width then
		return text
	end
	local chars = vim.fn.strchars(text)
	while chars > 0 do
		local value = vim.fn.strcharpart(text, 0, chars) .. "…"
		if vim.fn.strdisplaywidth(value) <= width then
			return value
		end
		chars = chars - 1
	end
	return ""
end

local function wrap(text, width)
	if text == "" then
		return { "" }
	end
	local lines = {}
	local offset = 0
	local length = vim.fn.strchars(text)
	while offset < length do
		local count = math.min(width, length - offset)
		local line = vim.fn.strcharpart(text, offset, count)
		while count > 1 and vim.fn.strdisplaywidth(line) > width do
			count = count - 1
			line = vim.fn.strcharpart(text, offset, count)
		end
		table.insert(lines, line)
		offset = offset + count
	end
	return lines
end

local function render(notification)
	if not vim.api.nvim_buf_is_valid(notification.buf) then
		return
	end
	local kind = kinds[notification.kind]
	local icon = icon_for(notification)
	local padding = string.rep(" ", opts.padding)
	local title = string.format("%s %s", icon, notification.title)
	local lines = { padding .. truncate(title, notification.text_width) }
	if #notification.message > 0 and not (#notification.message == 1 and notification.message[1] == "") then
		table.insert(lines, "")
		for _, line in ipairs(notification.message) do
			for _, wrapped_line in ipairs(wrap(line, notification.text_width)) do
				table.insert(lines, padding .. wrapped_line)
			end
		end
	end

	vim.bo[notification.buf].modifiable = true
	vim.api.nvim_buf_set_lines(notification.buf, 0, -1, false, lines)
	vim.bo[notification.buf].modifiable = false
	vim.api.nvim_buf_clear_namespace(notification.buf, notification.namespace, 0, -1)
	local icon_end = math.min(#lines[1], opts.padding + #icon)
	vim.api.nvim_buf_set_extmark(notification.buf, notification.namespace, 0, opts.padding, {
		end_col = icon_end,
		hl_group = kind.highlight,
	})
	local title_start = opts.padding + #icon + 1
	if title_start < #lines[1] then
		vim.api.nvim_buf_set_extmark(notification.buf, notification.namespace, 0, title_start, {
			end_col = #lines[1],
			hl_group = "NotificationTitle",
		})
	end
	if vim.api.nvim_win_is_valid(notification.win) then
		vim.api.nvim_win_set_height(notification.win, #lines)
	end
end

local function fit(notification)
	local content_width = vim.fn.strdisplaywidth(icon_for(notification) .. " " .. notification.title)
	for _, line in ipairs(notification.message) do
		content_width = math.max(content_width, vim.fn.strdisplaywidth(line))
	end
	local max_width = math.max(1, math.min(opts.max_width, vim.o.columns - 4))
	local width = math.min(max_width, math.max(math.min(opts.min_width, max_width), content_width + opts.padding * 2))
	notification.text_width = math.max(1, width - opts.padding * 2)
	if vim.api.nvim_win_is_valid(notification.win) then
		vim.api.nvim_win_set_width(notification.win, width)
	end
end

local function relayout()
	for _, notification in ipairs(notifications) do
		if vim.api.nvim_win_is_valid(notification.win) then
			fit(notification)
			render(notification)
		end
	end
	reflow()
end

local function schedule_timeout(notification, timeout)
	stop_timer(notification.timeout_timer)
	notification.timeout_timer = nil
	if not timeout or timeout <= 0 then
		return
	end
	local timer = vim.uv.new_timer()
	notification.timeout_timer = timer
	timer:start(timeout, 0, vim.schedule_wrap(function()
		M.dismiss(notification.id)
	end))
end

local function start_spinner(notification)
	stop_timer(notification.spinner_timer)
	notification.spinner_timer = nil
	if notification.kind ~= "loading" then
		return
	end
	notification.frame = notification.frame or 1
	local timer = vim.uv.new_timer()
	notification.spinner_timer = timer
	timer:start(80, 80, vim.schedule_wrap(function()
		if not find(notification.id) then
			stop_timer(timer)
			return
		end
		if not vim.api.nvim_win_is_valid(notification.win) then
			M.dismiss(notification.id)
			return
		end
		notification.frame = notification.frame % #spinner + 1
		render(notification)
	end))
end

local function show(kind_name, message, user_opts)
	user_opts = user_opts or {}
	local notification = user_opts.replace and find(user_opts.replace) or nil
	if not notification then
		next_id = next_id + 1
		local buf = vim.api.nvim_create_buf(false, true)
		local namespace = vim.api.nvim_create_namespace("Notification" .. next_id)
		local border = resolve_border()
		notification = {
			id = next_id,
			buf = buf,
			namespace = namespace,
			message = {},
			text_width = 1,
			border_extent = border == "none" and 0 or 1,
		}
		local win = vim.api.nvim_open_win(buf, false, {
			relative = "editor",
			row = 0,
			col = 0,
			width = math.max(1, math.min(opts.min_width, vim.o.columns - 4)),
			height = 1,
			style = "minimal",
			focusable = false,
			noautocmd = true,
			border = border,
			zindex = opts.zindex,
		})
		notification.win = win
		vim.bo[buf].bufhidden = "wipe"
		vim.api.nvim_set_option_value("wrap", false, { win = win })
		vim.api.nvim_set_option_value("winhighlight", "Normal:NotificationNormal,FloatBorder:NotificationBorder", { win = win })
		table.insert(notifications, notification)
	end

	notification.kind = kinds[kind_name] and kind_name or "info"
	notification.title = tostring(user_opts.title or kinds[notification.kind].title)
	notification.message = text_lines(message)
	notification.on_close = user_opts.on_close

	fit(notification)
	render(notification)
	start_spinner(notification)
	local timeout = user_opts.timeout
	if timeout == nil then
		timeout = notification.kind == "loading" and false or opts.timeout
	end
	schedule_timeout(notification, timeout)
	reflow()
	return notification.id
end

function M.loading(message, user_opts)
	return show("loading", message, user_opts)
end

function M.success(message, user_opts)
	return show("success", message, user_opts)
end

function M.error(message, user_opts)
	return show("error", message, user_opts)
end

function M.warn(message, user_opts)
	return show("warn", message, user_opts)
end

function M.info(message, user_opts)
	return show("info", message, user_opts)
end

function M.notify(message, level, user_opts)
	user_opts = user_opts or {}
	local kind = user_opts.kind or user_opts.type
	if not kinds[kind] then
		kind = levels[level] or "info"
	end
	return show(kind, message, user_opts)
end

function M.setup(user_opts)
	for index = #notifications, 1, -1 do
		remove(index)
	end
	opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_opts or {})
	highlights.apply()
	vim.notify = M.notify

	local group = vim.api.nvim_create_augroup("NativeNotifications", { clear = true })
	vim.api.nvim_create_autocmd("VimResized", { group = group, callback = relayout })
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		desc = "Restore notification highlights",
		callback = highlights.apply,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		callback = function()
			for index = #notifications, 1, -1 do
				remove(index)
			end
		end,
	})
	return M
end

function M.disable()
	vim.notify = original_notify
	for index = #notifications, 1, -1 do
		remove(index)
	end
	pcall(vim.api.nvim_del_augroup_by_name, "NativeNotifications")
end

return M
