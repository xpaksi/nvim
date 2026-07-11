local highlights = require("ui.commandline.highlights")

local M = {}

local function valid_buf(buf)
	return buf and vim.api.nvim_buf_is_valid(buf)
end

local function valid_win(win)
	return win and vim.api.nvim_win_is_valid(win)
end

local function resolve_border(opts)
	if vim.o.columns < 3 or vim.o.lines < 3 then
		return "none"
	end
	if opts.border then
		return opts.border
	end
	return vim.o.winborder ~= "" and vim.o.winborder or "rounded"
end

local function frame_size(border)
	return border == "none" and 0 or 2
end

local function label(item)
	local labels = { [":"] = "Command", ["/"] = "Search ↓", ["?"] = "Search ↑", ["="] = "Expression" }
	return labels[item.firstc] or "Input"
end

local function create_buffer(name)
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_buf_set_name(buf, name)
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "hide", { buf = buf })
	vim.api.nvim_set_option_value("swapfile", false, { buf = buf })
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
	return buf
end

local function set_window_options(win, winhl)
	vim.api.nvim_set_option_value("number", false, { win = win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = win })
	vim.api.nvim_set_option_value("foldcolumn", "0", { win = win })
	vim.api.nvim_set_option_value("wrap", false, { win = win })
	vim.api.nvim_set_option_value("cursorline", false, { win = win })
	vim.api.nvim_set_option_value("scrolloff", 0, { win = win })
	vim.api.nvim_set_option_value("sidescrolloff", 0, { win = win })
	vim.api.nvim_set_option_value("winhl", winhl, { win = win })
end

local function set_lines(buf, lines)
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })
end

local function add_chunks(namespace, buf, row, chunks, offset, transform)
	local col = 0
	for _, chunk in ipairs(chunks) do
		local finish = col + #chunk.text
		local start_col = transform and transform(col) or col
		local end_col = transform and transform(finish) or finish
		local group = highlights.group(chunk.attrs, chunk.hl_id)
		if group and end_col > start_col then
			vim.api.nvim_buf_set_extmark(buf, namespace, row, offset + start_col, {
				end_col = offset + end_col,
				hl_group = group,
				priority = 100,
			})
		end
		col = finish
	end
end

local function next_character_length(text, byte_pos)
	local character = text:sub(byte_pos + 1):match("^.[\128-\191]*")
	return character and #character or 0
end

local function display_item(item)
	local prefix = (item.prompt ~= "" and item.prompt or item.firstc) .. string.rep(" ", item.indent)
	local text = item.text
	local transform
	local special_start
	local special_end

	if item.special and item.special.char ~= "" then
		local pos = item.pos
		local removed = item.special.shift and 0 or next_character_length(text, pos)
		local delta = #item.special.char - removed
		text = text:sub(1, pos) .. item.special.char .. text:sub(pos + removed + 1)
		transform = function(value)
			if value <= pos then
				return value
			end
			if value < pos + removed then
				return pos
			end
			return value + delta
		end
		special_start = #prefix + pos
		special_end = special_start + #item.special.char
	end

	return {
		line = prefix .. text,
		prefix = prefix,
		cursor = #prefix + item.pos,
		transform = transform,
		special_start = special_start,
		special_end = special_end,
	}
end

function M.new(opts)
	return {
		opts = opts,
		namespace = vim.api.nvim_create_namespace("NativeCommandlineRenderer"),
		buf = nil,
		win = nil,
		block_buf = nil,
		block_win = nil,
	}
end

local function dimensions(renderer, line, title)
	local border = resolve_border(renderer.opts)
	local available = math.max(1, vim.o.columns - frame_size(border))
	local maximum = renderer.opts.max_width
	if type(maximum) ~= "number" or maximum <= 0 then
		maximum = 0.7
	end
	if maximum <= 1 then
		maximum = math.floor(vim.o.columns * maximum)
	end
	maximum = math.max(1, math.min(available, math.floor(maximum)))
	local minimum = math.max(1, math.min(maximum, renderer.opts.min_width or 30))
	local natural = math.max(vim.fn.strdisplaywidth(line), vim.fn.strdisplaywidth(title) + 4)
	return math.max(minimum, math.min(maximum, natural)), border
end

local function command_config(renderer, width, border, title)
	local position = renderer.opts.position or "top"
	local framed_height = 1 + frame_size(border)
	local config = {
		relative = "editor",
		width = width,
		height = 1,
		col = math.max(0, math.floor((vim.o.columns - width) / 2)),
		row = 1,
		style = "minimal",
		focusable = false,
		border = border,
		zindex = renderer.opts.zindex or 250,
		hide = false,
	}
	if position == "center" then
		config.row = math.max(0, math.floor((vim.o.lines - framed_height) / 2))
	elseif position == "bottom" then
		config.row = math.max(0, vim.o.lines - framed_height - 1)
	elseif position == "cursor" then
		config.relative = "cursor"
		config.row = 1
		config.col = 0
	end
	if border ~= "none" then
		config.title = " " .. title .. " "
		config.title_pos = "left"
	end
	return config
end

local function ensure_command_window(renderer, config)
	if not valid_buf(renderer.buf) then
		renderer.buf = create_buffer("commandline://input")
	end
	if valid_win(renderer.win) then
		vim.api.nvim_win_set_config(renderer.win, config)
	else
		renderer.win = vim.api.nvim_open_win(renderer.buf, false, vim.tbl_extend("force", config, { noautocmd = true }))
		set_window_options(renderer.win, "Normal:CommandlineNormal,FloatBorder:CommandlineBorder,FloatTitle:CommandlineTitle")
	end
end

local function render_cursor(renderer, line, cursor)
	cursor = math.max(0, math.min(cursor, #line))
	local char_length = next_character_length(line, cursor)
	if char_length > 0 then
		vim.api.nvim_buf_set_extmark(renderer.buf, renderer.namespace, 0, cursor, {
			end_col = cursor + char_length,
			hl_group = "CommandlineCursor",
			priority = 300,
		})
	else
		vim.api.nvim_buf_set_extmark(renderer.buf, renderer.namespace, 0, cursor, {
			virt_text = { { " ", "CommandlineCursor" } },
			virt_text_pos = "overlay",
			priority = 300,
		})
	end

	vim.api.nvim_win_set_cursor(renderer.win, { 1, cursor })
	local cursor_width = vim.fn.strdisplaywidth(line:sub(1, cursor))
	local width = vim.api.nvim_win_get_width(renderer.win)
	vim.api.nvim_win_call(renderer.win, function()
		vim.fn.winrestview({ leftcol = math.max(0, cursor_width - width + 3) })
	end)
end

local function close_window(renderer, field)
	if valid_win(renderer[field]) then
		vim.api.nvim_win_close(renderer[field], true)
	end
	renderer[field] = nil
end

local function hide_window(renderer, field)
	if valid_win(renderer[field]) then
		vim.api.nvim_win_set_config(renderer[field], { hide = true })
	end
end

local function window_visible(renderer, field)
	return valid_win(renderer[field]) and not vim.api.nvim_win_get_config(renderer[field]).hide
end

local function render_block(renderer, block)
	if not block or #block == 0 then
		hide_window(renderer, "block_win")
		return
	end
	if not valid_buf(renderer.block_buf) then
		renderer.block_buf = create_buffer("commandline://block")
	end

	local lines = {}
	local natural = 1
	for _, line in ipairs(block) do
		lines[#lines + 1] = line.text
		natural = math.max(natural, vim.fn.strdisplaywidth(line.text))
	end
	local border = resolve_border(renderer.opts)
	local frame = frame_size(border)
	local width = natural
	local height = math.min(#lines, math.max(1, vim.o.lines - 4))
	local row, col
	if window_visible(renderer, "win") then
		local command_position = vim.api.nvim_win_get_position(renderer.win)
		width = math.max(natural, vim.api.nvim_win_get_width(renderer.win))
		row = command_position[1] - height - frame
		if row < 0 then
			row = command_position[1] + 1 + frame
		end
		col = command_position[2]
	else
		row = 1
		col = math.floor((vim.o.columns - width) / 2)
	end
	width = math.min(width, math.max(1, vim.o.columns - 2))
	row = math.max(0, math.min(row, vim.o.lines - height - frame))
	local config = {
		relative = "editor",
		row = row,
		col = math.max(0, math.min(col, vim.o.columns - width - 2)),
		width = width,
		height = height,
		style = "minimal",
		focusable = false,
		border = border,
		zindex = (renderer.opts.zindex or 250) - 1,
		hide = false,
	}
	if valid_win(renderer.block_win) then
		vim.api.nvim_win_set_config(renderer.block_win, config)
	else
		renderer.block_win = vim.api.nvim_open_win(renderer.block_buf, false, vim.tbl_extend("force", config, { noautocmd = true }))
		set_window_options(renderer.block_win, "Normal:CommandlineBlockNormal,FloatBorder:CommandlineBorder")
	end
	set_lines(renderer.block_buf, lines)
	vim.api.nvim_buf_clear_namespace(renderer.block_buf, renderer.namespace, 0, -1)
	for row, line in ipairs(block) do
		add_chunks(renderer.namespace, renderer.block_buf, row - 1, line.chunks, 0)
	end
	vim.api.nvim_win_set_cursor(renderer.block_win, { #lines, 0 })
	vim.api.nvim_win_call(renderer.block_win, function()
		vim.fn.winrestview({ topline = math.max(1, #lines - height + 1) })
	end)
end

function M.render(renderer, state)
	local item = state.active_level and state.levels[state.active_level] or nil
	if not item then
		hide_window(renderer, "win")
		render_block(renderer, state.block)
		vim.api.nvim__redraw({ flush = true })
		return
	end

	local display = display_item(item)
	local title = label(item)
	local width, border = dimensions(renderer, display.line, title)
	ensure_command_window(renderer, command_config(renderer, width, border, title))
	set_lines(renderer.buf, { display.line })
	vim.api.nvim_buf_clear_namespace(renderer.buf, renderer.namespace, 0, -1)

	local prefix_group = highlights.group({}, item.prompt_hl_id)
	if prefix_group and #display.prefix > 0 then
		vim.api.nvim_buf_set_extmark(renderer.buf, renderer.namespace, 0, 0, {
			end_col = #display.prefix,
			hl_group = prefix_group,
			priority = 100,
		})
	end
	add_chunks(renderer.namespace, renderer.buf, 0, item.chunks, #display.prefix, display.transform)
	if display.special_start then
		vim.api.nvim_buf_set_extmark(renderer.buf, renderer.namespace, 0, display.special_start, {
			end_col = display.special_end,
			hl_group = "CommandlineSpecial",
			priority = 200,
		})
	end
	render_cursor(renderer, display.line, display.cursor)
	render_block(renderer, state.block)
	-- The cmdline input loop does not repaint floats changed from scheduled
	-- callbacks; without an explicit flush the window paints only on the
	-- next forced redraw.
	vim.api.nvim__redraw({ flush = true })
end

function M.close(renderer)
	close_window(renderer, "block_win")
	close_window(renderer, "win")
	for _, field in ipairs({ "block_buf", "buf" }) do
		if valid_buf(renderer[field]) then
			vim.api.nvim_buf_delete(renderer[field], { force = true })
		end
		renderer[field] = nil
	end
end

return M
