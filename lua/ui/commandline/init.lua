local highlights = require("ui.commandline.highlights")
local Renderer = require("ui.commandline.renderer")
local State = require("ui.commandline.state")

local M = {}

local defaults = {
	position = "top",
	min_width = 30,
	max_width = 0.7,
	border = nil,
	zindex = 250,
	cmdheight = 0,
}

local namespace = vim.api.nvim_create_namespace("NativeCommandline")
local state = State.new()
local renderer
local attached = false
local rendering_scheduled = false
local saved_cmdheight
local opts = vim.deepcopy(defaults)

local events = {
	cmdline_show = function(...)
		State.show(state, ...)
	end,
	cmdline_pos = function(...)
		State.position(state, ...)
	end,
	cmdline_special_char = function(...)
		State.special(state, ...)
	end,
	cmdline_hide = function(level)
		State.hide(state, level)
	end,
	cmdline_block_show = function(...)
		State.block_show(state, ...)
	end,
	cmdline_block_append = function(...)
		State.block_append(state, ...)
	end,
	cmdline_block_hide = function()
		State.block_hide(state)
	end,
}

local function notify_error(message)
	vim.schedule(function()
		vim.notify("Command-line UI disabled: " .. message, vim.log.levels.ERROR)
	end)
end

local function render_or_disable()
	rendering_scheduled = false
	if not attached then
		return
	end
	local ok, err = xpcall(Renderer.render, debug.traceback, renderer, state)
	if not ok then
		M.disable()
		notify_error(err)
	end
end

local function schedule_render()
	if rendering_scheduled or not attached then
		return
	end
	rendering_scheduled = true
	vim.schedule(render_or_disable)
end

local function callback(event, ...)
	local handler = events[event]
	if not handler then
		return
	end
	local ok, err = xpcall(handler, debug.traceback, ...)
	if not ok then
		vim.schedule(function()
			M.disable()
			notify_error(err)
		end)
		return true
	end
	schedule_render()
	return true
end

local function create_command()
	vim.api.nvim_create_user_command("CommandlineUI", function(command)
		local action = command.args ~= "" and command.args or "toggle"
		if action == "enable" then
			M.enable()
		elseif action == "disable" then
			M.disable()
		elseif attached then
			M.disable()
		else
			M.enable()
		end
	end, {
		nargs = "?",
		force = true,
		desc = "Enable, disable, or toggle the floating command line",
		complete = function(arglead)
			return vim.tbl_filter(function(action)
				return vim.startswith(action, arglead)
			end, { "enable", "disable", "toggle" })
		end,
	})
end

function M.enable()
	if attached then
		return true
	end
	if vim.fn.has("nvim-0.12") ~= 1 or type(vim.ui_attach) ~= "function" or type(vim.ui_detach) ~= "function" then
		vim.notify("Floating command line requires Neovim 0.12 or newer", vim.log.levels.ERROR)
		return false
	end

	State.reset(state)
	renderer = Renderer.new(opts)
	local ok, result = pcall(vim.ui_attach, namespace, { ext_cmdline = true }, callback)
	if not ok or result == false then
		Renderer.close(renderer)
		renderer = nil
		vim.notify("Unable to attach floating command line: " .. tostring(result), vim.log.levels.ERROR)
		return false
	end

	attached = true
	saved_cmdheight = vim.o.cmdheight
	local configured, err = pcall(function()
		vim.o.cmdheight = opts.cmdheight
	end)
	if not configured then
		M.disable()
		vim.notify("Unable to configure floating command line: " .. tostring(err), vim.log.levels.ERROR)
		return false
	end
	return true
end

function M.disable()
	if attached then
		pcall(vim.ui_detach, namespace)
	end
	attached = false
	rendering_scheduled = false
	if renderer then
		pcall(Renderer.close, renderer)
		renderer = nil
	end
	State.reset(state)
	if saved_cmdheight ~= nil then
		vim.o.cmdheight = math.max(1, saved_cmdheight)
		saved_cmdheight = nil
	end
end

function M.setup(user_opts)
	M.disable()
	opts = vim.tbl_deep_extend("force", vim.deepcopy(defaults), user_opts or {})
	highlights.apply()
	create_command()

	local group = vim.api.nvim_create_augroup("NativeCommandline", { clear = true })
	vim.api.nvim_create_autocmd({ "VimResized", "TabEnter" }, {
		group = group,
		desc = "Reposition the floating command line",
		callback = schedule_render,
	})
	vim.api.nvim_create_autocmd("ColorScheme", {
		group = group,
		desc = "Restore floating command-line highlights",
		callback = function()
			highlights.apply()
			schedule_render()
		end,
	})
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = group,
		desc = "Close the floating command line",
		callback = M.disable,
	})

	return M.enable()
end

function M.is_enabled()
	return attached
end

return M
