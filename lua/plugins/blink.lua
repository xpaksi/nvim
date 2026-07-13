vim.pack.add({
	{ src = "https://github.com/saghen/blink.lib" },
	{ src = "https://github.com/saghen/blink.indent" },
	{ src = "https://github.com/rafamadriz/friendly-snippets" },
	{ src = "https://github.com/saghen/blink.cmp" },
	{ src = "https://github.com/saghen/blink.nvim" },
	{ src = "https://github.com/nvim-tree/nvim-web-devicons" },
})

require("blink").setup({ tree = { enabled = true } })

vim.keymap.set("n", "<leader>E", "<cmd>BlinkTree reveal<cr>", { desc = "Reveal current file in tree" })
vim.keymap.set("n", "<leader>e", "<cmd>BlinkTree toggle-focus<cr>", { desc = "Toggle file tree window or focus" })

local cmp = require("blink.cmp")
cmp.build():pwait()

cmp.setup({
	keymap = { preset = "super-tab" },
	appearance = {
		nerd_font_variant = "normal",
		use_nvim_cmp_as_default = true,
	},
	completion = {
		list = {
			max_items = 50,
			selection = { preselect = true, auto_insert = false },
		},
		menu = {
			min_width = 60,
			max_height = 12,
			border = "rounded",
			draw = {
				columns = {
					{ "kind_icon" },
					{ "label" },
					{ "label_description" },
					{ "kind" },
					{ "source_name" },
				},
				components = {
					label = { width = { min = 24, max = 24 } },
					label_description = { width = { min = 12, max = 12 } },
					kind = { width = { min = 9, max = 9 } },
					source_name = { width = { min = 7, max = 7 } },
				},
			},
		},
		documentation = {
			auto_show = true,
			auto_show_delay_ms = 300,
			window = {
				min_width = 60,
				max_width = 60,
				desired_min_width = 60,
				border = "rounded",
			},
		},
		ghost_text = { enabled = true },
	},
	sources = { default = { "lsp", "path", "snippets", "buffer" } },
	signature = { enabled = true, window = { show_documentation = false } },
})
