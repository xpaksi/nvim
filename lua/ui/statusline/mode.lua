local M = {}

local modes = {
	n = { "NORMAL", "StatusLineModeNormal" },
	i = { "INSERT", "StatusLineModeInsert" },
	v = { "VISUAL", "StatusLineModeVisual" },
	V = { "VISUAL", "StatusLineModeVisual" },
	["\22"] = { "VISUAL", "StatusLineModeVisual" },
	R = { "REPLACE", "StatusLineModeReplace" },
	c = { "COMMAND", "StatusLineModeCommand" },
	t = { "TERMINAL", "StatusLineModeTerminal" },
	s = { "SELECT", "StatusLineModeSelect" },
	S = { "SELECT", "StatusLineModeSelect" },
	["\19"] = { "SELECT", "StatusLineModeSelect" },
}

function M.get()
	local mode = vim.api.nvim_get_mode().mode
	-- The prefix lookup folds variants (no, niI, ic, Rv, ...) into their base
	-- mode; anything unrecognized is treated as Normal.
	local entry = modes[mode] or modes[mode:sub(1, 1)] or modes.n

	return entry[1], entry[2]
end

return M
