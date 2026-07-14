if vim.g.vscode then
	vim.schedule(function()
		vim.opt.clipboard = "unnamedplus"
	end)
else
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

	vim.diagnostic.config({ virtual_lines = { current_line = true }, virtual_text = false })

	vim.opt.breakindent = true
	vim.opt.undofile = true

	vim.opt.ignorecase = true
	vim.opt.smartcase = true

	vim.opt.updatetime = 250
	vim.opt.timeoutlen = 300
	vim.opt.autoread = true

	vim.opt.splitright = true
	vim.opt.splitbelow = true

	vim.opt.cursorline = true
	vim.opt.scrolloff = 10
	vim.opt.shell = "zsh"

	vim.o.signcolumn = "yes"

	vim.opt.foldlevelstart = 99

	vim.o.foldmethod = "indent"
	vim.o.pumborder = "bold"

	vim.api.nvim_create_user_command("W", "w", { desc = "Write" })

	vim.api.nvim_create_autocmd("TextYankPost", {
		desc = "Highlight when yanking (copying) text",
		group = vim.api.nvim_create_augroup("kickstart-highlight-yank", { clear = true }),
		callback = function()
			vim.highlight.on_yank()
		end,
	})

	vim.api.nvim_create_autocmd({ "FocusGained", "BufEnter", "CursorHold", "CursorHoldI" }, {
		desc = "Reload files changed outside of Neovim",
		group = vim.api.nvim_create_augroup("auto-reload-external-changes", { clear = true }),
		callback = function()
			if vim.fn.mode() ~= "c" then
				vim.cmd("checktime")
			end
		end,
	})

	local function update_plugins()
		vim.pack.update()
	end

	vim.api.nvim_create_user_command("UpdatePlugins", update_plugins, {
		desc = "Update installed plugins",
	})

	vim.keymap.set("n", "<Tab>", ":bnext<CR>", { desc = "Next buffer" })
	vim.keymap.set("n", "<S-Tab>", ":bprevious<CR>", { desc = "Previous buffer" })
	vim.keymap.set("n", "<leader>t", "<cmd>enew | terminal<CR>", { desc = "Open terminal in new buffer" })

	vim.keymap.set("n", "<C-h>", "<C-w><C-h>", { desc = "Move focus to the left window" })
	vim.keymap.set("n", "<C-l>", "<C-w><C-l>", { desc = "Move focus to the right window" })
	vim.keymap.set("n", "<C-j>", "<C-w><C-j>", { desc = "Move focus to the lower window" })
	vim.keymap.set("n", "<C-k>", "<C-w><C-k>", { desc = "Move focus to the upper window" })

	vim.keymap.set("n", "<C-Up>", ":resize +2<CR>", { desc = "Increase window height" })
	vim.keymap.set("n", "<C-Down>", ":resize -2<CR>", { desc = "Decrease window height" })
	vim.keymap.set("n", "<C-Left>", ":vertical resize -2<CR>", { desc = "Decrease window width" })
	vim.keymap.set("n", "<C-Right>", ":vertical resize +2<CR>", { desc = "Increase window width" })

	require("plugins.mini")
	require("plugins.treesitter")
	require("plugins.theme")
	require("plugins.lsp")
	require("plugins.fff")
	require("plugins.blink")
	require("plugins.expand-buffer")
	require("plugins.pi").setup()
	require("ui.statusline").setup()
	require("ui.commandline").setup()
	require("ui.notification").setup()
	require("ui.lsp_list").setup()
	require("ui.pack").setup()
	require("ui.tabline").setup()
	require("ui.lazygit").setup()
	require("ui.hunk").setup()

	vim.cmd.colorscheme("catppuccin-nvim")
end
