vim.pack.add({ "https://github.com/nvim-treesitter/nvim-treesitter" })

local misc = require("mini.misc")
local now = function(f)
	misc.safely("now", f)
end
local later = function(f)
	misc.safely("later", f)
end
local now_if_args = vim.fn.argc(-1) > 0 and now or later
local gr = vim.api.nvim_create_augroup("custom-config", {})
local new_autocmd = function(event, pattern, callback, desc)
	local opts = { group = gr, pattern = pattern, callback = callback, desc = desc }
	vim.api.nvim_create_autocmd(event, opts)
end

now_if_args(function()
	local ensure_languages = {
		"go",
		"lua",
		"typescript",
		"tsx",
		"javascript",
		"json",
		"rust",
		"python",
		"sql",
		"markdown",
		"java",
		"diff",
		"css",
	}

	local installed = vim.api.nvim_get_runtime_file("parser/*", true)
	local installed_map = {}
	for _, path in ipairs(installed) do
		local name = vim.fn.fnamemodify(path, ":t:r")
		installed_map[name] = true
	end

	local not_installed = function(lang)
		return installed_map[lang] ~= true
	end

	local to_install = vim.tbl_filter(not_installed, ensure_languages)
	if #to_install > 0 then
		require("nvim-treesitter").install(to_install)
	end

	-- Ensure started
	local filetypes = vim.iter(ensure_languages):map(vim.treesitter.language.get_filetypes):flatten():totable()
	local ts_start = function(ev)
		vim.treesitter.start(ev.buf)
	end
	new_autocmd("FileType", filetypes, ts_start, "Ensure enabled tree-sitter")
end)
