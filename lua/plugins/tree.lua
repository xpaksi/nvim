vim.pack.add({
	{ src = "https://github.com/nvim-tree/nvim-web-devicons" },
	{ src = "https://github.com/nvim-tree/nvim-tree.lua" },
})

local api = require("nvim-tree.api")

local function toggle_replace()
	if api.tree.is_visible() then
		api.tree.close()
	else
		api.tree.open({ current_window = true })
	end
end

local function on_attach(bufnr)
	local function opts(desc)
		return { desc = "nvim-tree: " .. desc, buffer = bufnr, noremap = true, silent = true, nowait = true }
	end

	vim.keymap.set("n", "<CR>", api.node.open.replace_tree_buffer, opts("Open: In Place"))
end

require("nvim-tree").setup({
	on_attach = on_attach,
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

vim.keymap.set("n", "<leader>e", toggle_replace, {
	silent = true,
	desc = "Toggle NvimTree (Vinegar style)",
})

vim.keymap.set("n", "<leader>E", "<cmd>NvimTreeToggle<cr>", {
	silent = true,
	desc = "Toggle NvimTree",
})
