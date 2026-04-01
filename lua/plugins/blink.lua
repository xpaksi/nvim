vim.pack.add({
	{ src = "https://github.com/saghen/blink.indent" },
	{ src = "https://github.com/rafamadriz/friendly-snippets" },
	{ src = "https://github.com/Saghen/blink.cmp", version = vim.version.range("1") },
})

require("blink.cmp").setup({
	keymap = { preset = "super-tab" },

	appearance = {
		nerd_font_variant = "mono",
	},

	completion = {
		documentation = { auto_show = true },
		ghost_text = { enabled = true },
	},

	sources = {
		default = { "lsp", "path", "snippets", "buffer" },
	},

	signature = {
		enabled = true,
	},
	fuzzy = { implementation = "prefer_rust_with_warning" },
})
