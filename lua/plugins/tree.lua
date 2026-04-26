vim.pack.add({
	{ src = "https://github.com/nvim-tree/nvim-web-devicons" },
	{ src = "https://github.com/nvim-tree/nvim-tree.lua" },
})

require("nvim-tree").setup({
	filters = {
		dotfiles = true,
	},
	view = {
		width = 40,
	},
	renderer = {
		indent_markers = {
			enable = true,
		},
		highlight_git = "all",
	},
})

vim.keymap.set("n", "<leader>e", "<cmd>NvimTreeFocus<cr>", {
	silent = true,
	desc = "Toggle NvimTree (Vinegar style)",
})

vim.keymap.set("n", "<leader>E", "<cmd>NvimTreeToggle<cr>", {
	silent = true,
	desc = "Toggle NvimTree",
})
