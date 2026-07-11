vim.pack.add({
	{ src = "https://github.com/nvim-tree/nvim-web-devicons" },
	{ src = "https://github.com/nvim-tree/nvim-tree.lua" },
})

local default_width = 40

require("nvim-tree").setup({
	filters = {
		dotfiles = true,
	},
	view = {
		width = default_width,
	},
	renderer = {
		indent_markers = {
			enable = true,
		},
		highlight_git = "all",
	},
})

local tree_width_fitted = false

local function toggle_tree_width()
	local api = require("nvim-tree.api")
	local winid = api.tree.winid()
	if not winid then
		return
	end
	if tree_width_fitted then
		api.tree.resize({ absolute = default_width })
		tree_width_fitted = false
		return
	end

	local bufnr = vim.api.nvim_win_get_buf(winid)
	local width = 1
	local namespace = vim.api.nvim_get_namespaces().NvimTreeExtmarks

	for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
		local line_width = vim.fn.strdisplaywidth(line)
		if namespace then
			local extmarks = vim.api.nvim_buf_get_extmarks(bufnr, namespace, { row - 1, 0 }, { row - 1, -1 }, {
				details = true,
			})
			for _, extmark in ipairs(extmarks) do
				for _, text in ipairs(extmark[4].virt_text or {}) do
					line_width = line_width + vim.fn.strdisplaywidth(text[1])
				end
			end
		end
		width = math.max(width, line_width)
	end

	local wininfo = vim.fn.getwininfo(winid)[1]
	api.tree.resize({ absolute = width + (wininfo and wininfo.textoff or 0) + 1 })
	tree_width_fitted = true
end

vim.keymap.set("n", "<leader>e", "<cmd>NvimTreeFocus<cr>", {
	silent = true,
	desc = "Toggle NvimTree (Vinegar style)",
})

vim.keymap.set("n", "<leader>E", "<cmd>NvimTreeToggle<cr>", {
	silent = true,
	desc = "Toggle NvimTree",
})

vim.keymap.set("n", "<leader>ew", toggle_tree_width, {
	silent = true,
	desc = "Toggle fitted NvimTree width",
})
