local M = {}

local cache = {}
local next_group = 0

local links = {
	CommandlineNormal = "NormalFloat",
	CommandlineBorder = "FloatBorder",
	CommandlineTitle = "FloatTitle",
	CommandlineCursor = "Cursor",
	CommandlineSpecial = "Special",
	CommandlineBlockNormal = "NormalFloat",
}

local function attributes(attrs)
	local result = {}
	local names = {
		foreground = "fg",
		background = "bg",
		special = "sp",
		bold = "bold",
		italic = "italic",
		underline = "underline",
		undercurl = "undercurl",
		underdouble = "underdouble",
		underdotted = "underdotted",
		underdashed = "underdashed",
		strikethrough = "strikethrough",
		reverse = "reverse",
		standout = "standout",
		blend = "blend",
	}
	for source, target in pairs(names) do
		if attrs[source] ~= nil then
			result[target] = attrs[source]
		end
	end
	return result
end

function M.apply()
	for name, target in pairs(links) do
		vim.api.nvim_set_hl(0, name, { link = target, default = true })
	end
	cache = {}
	next_group = 0
end

function M.group(attrs, hl_id)
	if hl_id and hl_id > 0 then
		local ok, name = pcall(vim.fn.synIDattr, hl_id, "name")
		if ok and name ~= "" then
			return name
		end
	end
	if not next(attrs or {}) then
		return nil
	end
	local key = vim.inspect(attrs)
	if cache[key] then
		return cache[key]
	end
	next_group = next_group + 1
	local name = "CommandlineProtocol" .. next_group
	vim.api.nvim_set_hl(0, name, attributes(attrs))
	cache[key] = name
	return name
end

return M
