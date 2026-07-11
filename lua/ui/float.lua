local M = {}

local border_sets = {
	single = { "┌", "─", "┐", "│", "┘", "─", "└", "│", "┬", "┴", "├", "┤" },
	rounded = { "╭", "─", "╮", "│", "╯", "─", "╰", "│", "┬", "┴", "├", "┤" },
	double = { "╔", "═", "╗", "║", "╝", "═", "╚", "║", "╦", "╩", "╠", "╣" },
}

local function border_style()
	local border = vim.o.winborder
	return border_sets[border] and border or "rounded"
end

local function borders(layout)
	local b = border_sets[border_style()]
	if layout == "right" then
		return {
			list = { b[1], b[2], b[9], b[4], b[10], b[6], b[7], b[8] },
			preview = { b[9], b[2], b[3], b[4], b[5], b[6], b[10], b[8] },
		}
	end
	return {
		list = { b[11], b[2], b[12], b[4], b[5], b[6], b[7], b[8] },
		preview = { b[1], b[2], b[3], b[4], b[12], b[6], b[11], b[8] },
	}
end

function M.truncate(text, width)
	if width <= 0 then
		return ""
	end
	if vim.fn.strdisplaywidth(text) <= width then
		return text
	end
	local chars = math.min(vim.fn.strchars(text), width)
	while chars > 0 do
		local candidate = vim.fn.strcharpart(text, 0, chars) .. "…"
		if vim.fn.strdisplaywidth(candidate) <= width then
			return candidate
		end
		chars = chars - 1
	end
	return ""
end

function M.truncate_left(text, width)
	if width <= 0 then
		return ""
	end
	if vim.fn.strdisplaywidth(text) <= width then
		return text
	end
	local total = vim.fn.strchars(text)
	local chars = math.min(total, width)
	while chars > 0 do
		local candidate = "…" .. vim.fn.strcharpart(text, total - chars, chars)
		if vim.fn.strdisplaywidth(candidate) <= width then
			return candidate
		end
		chars = chars - 1
	end
	return ""
end

-- opts requires width, height, preview_size, flex_width (fractions/columns).
function M.window_configs(opts, list_title, preview_title)
	local columns = vim.o.columns
	local available_lines = math.max(5, vim.o.lines - vim.o.cmdheight - 1)
	local max_width = math.max(10, columns - 2)
	local max_height = math.max(5, available_lines - 1)
	local total_width = math.min(max_width, math.max(math.min(30, max_width), math.floor(columns * opts.width)))
	local total_height = math.min(max_height, math.max(math.min(8, max_height), math.floor(available_lines * opts.height)))
	local start_col = math.max(0, math.floor((columns - total_width) / 2))
	local start_row = math.max(0, math.floor((available_lines - total_height) / 2))
	local layout = columns >= opts.flex_width and "right" or "top"
	local border = borders(layout)
	local common = {
		relative = "editor",
		style = "minimal",
		focusable = true,
		noautocmd = true,
	}

	if layout == "right" then
		local content_width = total_width - 3
		local list_width = math.max(20, math.floor(content_width * (1 - opts.preview_size)))
		local preview_width = math.max(10, content_width - list_width)
		local height = total_height - 2
		return layout, {
			list = vim.tbl_extend("force", common, {
				row = start_row,
				col = start_col,
				width = list_width,
				height = height,
				border = border.list,
				title = " " .. list_title .. " ",
				title_pos = "left",
				zindex = 52,
			}),
			preview = vim.tbl_extend("force", common, {
				row = start_row,
				col = start_col + list_width + 1,
				width = preview_width,
				height = height,
				border = border.preview,
				title = " " .. preview_title .. " ",
				title_pos = "left",
				focusable = false,
				zindex = 51,
			}),
		}
	end

	local content_height = total_height - 3
	local preview_height = math.max(1, math.floor(content_height * 0.4))
	local list_height = math.max(1, content_height - preview_height)
	local width = total_width - 2
	return layout, {
		preview = vim.tbl_extend("force", common, {
			row = start_row,
			col = start_col,
			width = width,
			height = preview_height,
			border = border.preview,
			title = " " .. preview_title .. " ",
			title_pos = "left",
			focusable = false,
			zindex = 51,
		}),
		list = vim.tbl_extend("force", common, {
			row = start_row + preview_height + 1,
			col = start_col,
			width = width,
			height = list_height,
			border = border.list,
			title = " " .. list_title .. " ",
			title_pos = "left",
			zindex = 52,
		}),
	}
end

function M.set_window_options(win, winhighlight, number)
	vim.api.nvim_set_option_value("wrap", false, { win = win })
	vim.api.nvim_set_option_value("number", number == true, { win = win })
	vim.api.nvim_set_option_value("relativenumber", false, { win = win })
	vim.api.nvim_set_option_value("cursorline", false, { win = win })
	vim.api.nvim_set_option_value("signcolumn", "no", { win = win })
	vim.api.nvim_set_option_value("foldcolumn", "0", { win = win })
	vim.api.nvim_set_option_value("winhighlight", winhighlight, { win = win })
end

return M
