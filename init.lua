vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.g.have_nerd_font = true
vim.opt.number = true
vim.opt.relativenumber = false
vim.opt.mouse = "a"

vim.opt.showmode = false
vim.opt.tabstop = 2
vim.opt.shiftwidth = 2

vim.opt.wrap = true

vim.g.loaded_netrw = 1
vim.g.loaded_netrwPlugin = 1
vim.opt.termguicolors = true

vim.schedule(function()
	vim.opt.clipboard = "unnamedplus"
end)

vim.diagnostic.config({ virtual_lines = true })

vim.opt.breakindent = true
vim.opt.undofile = true

vim.opt.ignorecase = true
vim.opt.smartcase = true

vim.opt.updatetime = 250
vim.opt.timeoutlen = 300

vim.opt.splitright = true
vim.opt.splitbelow = true

vim.opt.cursorline = true
vim.opt.scrolloff = 10

vim.o.signcolumn = "yes"

vim.opt.foldlevelstart = 99

vim.o.foldmethod = "indent"
vim.o.pumborder = "bold"

require("vim._core.ui2").enable({ enable = true })

vim.api.nvim_create_user_command("W", "w", { desc = "Write" })

vim.api.nvim_create_autocmd("TextYankPost", {
	desc = "Highlight when yanking (copying) text",
	group = vim.api.nvim_create_augroup("kickstart-highlight-yank", { clear = true }),
	callback = function()
		vim.highlight.on_yank()
	end,
})

local function show_installed_plugins()
	local plugins = vim.pack.get()
	local lines = {}

	for _, plugin in ipairs(plugins) do
		local status = plugin.active and "✓" or "✗"
		table.insert(lines, string.format("%s %s (%s)", status, plugin.spec.name, plugin.rev))
	end

	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	vim.api.nvim_set_option_value("bufhidden", "wipe", { buf = buf })
	vim.api.nvim_set_option_value("modifiable", true, { buf = buf })
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_set_option_value("modifiable", false, { buf = buf })

	vim.cmd("vsplit")
	vim.api.nvim_win_set_buf(0, buf)
end

local function update_plugins()
	vim.pack.update()
end

vim.api.nvim_create_user_command("ShowPlugins", show_installed_plugins, {
	desc = "Show installed plugins",
})

vim.api.nvim_create_user_command("UpdatePlugins", update_plugins, {
	desc = "Update installed plugins",
})

vim.keymap.set("n", "<Tab>", ":bnext<CR>", { desc = "Next buffer" })
vim.keymap.set("n", "<S-Tab>", ":bprevious<CR>", { desc = "Previous buffer" })

vim.keymap.set("n", "<C-h>", "<C-w><C-h>", { desc = "Move focus to the left window" })
vim.keymap.set("n", "<C-l>", "<C-w><C-l>", { desc = "Move focus to the right window" })
vim.keymap.set("n", "<C-j>", "<C-w><C-j>", { desc = "Move focus to the lower window" })
vim.keymap.set("n", "<C-k>", "<C-w><C-k>", { desc = "Move focus to the upper window" })

require("plugins.mini")
require("plugins.treesitter")
require("plugins.tree")
require("plugins.theme")
require("plugins.lsp")
require("plugins.fff")
require("plugins.blink")

vim.cmd.colorscheme("catppuccin-nvim")
