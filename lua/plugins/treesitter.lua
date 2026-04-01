vim.pack.add({ "https://github.com/nvim-treesitter/nvim-treesitter" })

vim.api.nvim_create_autocmd("FileType", {
	pattern = {
		"go",
		"lua",
		"typescript",
		"javascript",
		"javascriptreact",
		"typescriptreact",
		"json",
		"rust",
		"python",
		"sql",
		"markdown",
		"java",
	},
	callback = function()
		vim.treesitter.start()
		vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
		vim.wo.foldexpr = "v:lua.vim.treesitter.foldexpr()"
	end,
})
