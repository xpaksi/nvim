vim.pack.add({ "https://github.com/dmtrKovalenko/fff.nvim" })

vim.g.fff = {
	lazy_sync = true,
	debug = {
		enabled = true,
		show_scores = true,
	},
}

vim.keymap.set("n", "sf", function()
	require("fff").find_files()
end, { desc = "FFFind files" })

vim.keymap.set("n", "sg", function()
	require("fff").live_grep()
end, { desc = "LiFFFe grep" })

vim.keymap.set("n", "sz", function()
	require("fff").live_grep({
		grep = {
			modes = { "fuzzy", "plain" },
		},
	})
end, { desc = "Live fffuzy grep" })

vim.keymap.set("n", "sc", function()
	require("fff").live_grep({ query = vim.fn.expand("<cword>") })
end, { desc = "Search current word" })
