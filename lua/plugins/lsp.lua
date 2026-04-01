vim.pack.add({
	{ src = "https://github.com/mason-org/mason.nvim" },
	{ src = "https://github.com/neovim/nvim-lspconfig" },
	{ src = "https://github.com/stevearc/conform.nvim" },
})

require("mason").setup()

local servers = {
	gopls = {},
	rust_analyzer = {
		settings = {
			["rust-analyzer"] = {
				diagnostics = {
					enable = false,
				},
			},
		},
	},
	lua_ls = {
		on_init = function(client)
			if client.workspace_folders then
				local path = client.workspace_folders[1].name
				if
					path ~= vim.fn.stdpath("config")
					and (vim.uv.fs_stat(path .. "/.luarc.json") or vim.uv.fs_stat(path .. "/.luarc.jsonc"))
				then
					return
				end
			end

			client.config.settings.Lua = vim.tbl_deep_extend("force", client.config.settings.Lua, {
				runtime = {
					version = "LuaJIT",
					path = {
						"lua/?.lua",
						"lua/?/init.lua",
					},
				},
				workspace = {
					checkThirdParty = false,
					library = {
						vim.env.VIMRUNTIME,
					},
				},
			})
		end,
		settings = {
			Lua = {},
		},
	},
	tailwindcss = {},
	jsonls = {},
	ty = {},
	vtsls = {},
	jdtls = {},
}

for server, config in pairs(servers) do
	vim.lsp.config(server, config)
	vim.lsp.enable(server)
end

require("conform").setup({
	format_on_save = {
		timeout_ms = 500,
		lsp_format = "fallback",
	},
	notify_on_error = false,
	formatters_by_ft = {
		lua = { "stylua" },
		javascript = { "oxfmt" },
		typescript = { "oxfmt" },
		vue = { "oxfmt" },
		rust = { "rustfmt" },
		python = { "ruff" },
		sql = { "sqruff" },
		json = { "oxfmt" },
		go = { "gofmt", "goimports" },
		typescriptreact = { "oxfmt" },
	},
})
