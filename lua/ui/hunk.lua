local M = {}

function M.setup()
	require("ui.terminal").setup({
		name = "HunkDiff",
		command = { "hunk", "diff" },
		nargs = "*",
		complete = "file",
		desc = "Open hunk diff in a floating terminal",
	})
end

return M
