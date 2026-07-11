local M = {}

local function width(text)
	return vim.fn.strdisplaywidth(text)
end

local function tail_truncate(text, max_width)
	if max_width <= 0 then
		return ""
	end
	if width(text) <= max_width then
		return text
	end
	if max_width == 1 then
		return "…"
	end

	local chars = vim.fn.strchars(text)
	for start = 1, chars do
		local tail = vim.fn.strcharpart(text, start, chars - start)
		if width("…" .. tail) <= max_width then
			return "…" .. tail
		end
	end
	return "…"
end

local function has_duplicate_basename(bufnr, basename, winid)
	local tabpage = vim.api.nvim_win_get_tabpage(winid)
	for _, other_win in ipairs(vim.api.nvim_tabpage_list_wins(tabpage)) do
		local other_buf = vim.api.nvim_win_get_buf(other_win)
		if other_buf ~= bufnr then
			local other_name = vim.api.nvim_buf_get_name(other_buf)
			if other_name ~= "" and vim.fn.fnamemodify(other_name, ":t") == basename then
				return true
			end
		end
	end
	return false
end

local function terminal_name(name)
	local command = name:match("^term://.-//%d+:(.*)$") or name:match(":([^:]*)$") or name
	-- Keep only the executable: ":t" on the full command line would return
	-- the basename of the last path-like argument instead.
	command = vim.fn.fnamemodify(command:match("%S+") or "", ":t")
	if command == "" then
		command = "shell"
	end
	return "[Terminal: " .. command .. "]"
end

function M.get(bufnr, winid, max_width)
	local name = vim.api.nvim_buf_get_name(bufnr)
	local buftype = vim.bo[bufnr].buftype
	local text
	local basename

	if buftype == "terminal" then
		text = terminal_name(name)
	elseif name == "" then
		text = "[No Name]"
	else
		basename = vim.fn.fnamemodify(name, ":t")
		if has_duplicate_basename(bufnr, basename, winid) then
			text = vim.fn.fnamemodify(name, ":.")
		else
			text = basename
		end
	end

	local modified = vim.bo[bufnr].modified and "[+]" or ""
	local readonly = vim.bo[bufnr].readonly and "[RO]" or ""
	local marker_width = width(modified) + width(readonly)
	local available = math.max(1, (max_width or width(text) + marker_width) - marker_width)

	-- Prefer the basename before truncating the actual filename.
	if basename and text ~= basename and width(text) > available then
		text = basename
	end
	text = tail_truncate(text, available)

	return {
		text = text,
		modified = modified,
		readonly = readonly,
		width = width(text) + marker_width,
	}
end

return M
