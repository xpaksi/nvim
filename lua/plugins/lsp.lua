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
	jdtls = {},
	texlab = {
		build = {
			forwardSearchAfter = false,
			onSave = false,
		},
	},
	harper_ls = {},
	powershell_es = {},
	tsgo = {},
}

for server, config in pairs(servers) do
	vim.lsp.config(server, config)
	vim.lsp.enable(server)
end

local notification = require("ui.notification")
local progress = {}
local lsp_notify_group = vim.api.nvim_create_augroup("LspProgressNotify", { clear = true })

vim.api.nvim_create_autocmd("LspProgress", {
	group = lsp_notify_group,
	desc = "Show LSP progress as notifications",
	callback = function(event)
		local client = vim.lsp.get_client_by_id(event.data.client_id)
		local value = event.data.params.value
		if not client or type(value) ~= "table" then
			return
		end
		local key = event.data.client_id .. ":" .. tostring(event.data.params.token)
		if value.kind == "end" then
			local id = progress[key]
			progress[key] = nil
			if id then
				notification.success(value.message or value.title or "Done", { title = client.name, replace = id })
			end
		else
			local message = value.message or value.title or ""
			if value.percentage then
				message = string.format("%s (%d%%)", message, value.percentage)
			end
			progress[key] = notification.loading(message, { title = client.name, replace = progress[key] })
		end
	end,
})

vim.api.nvim_create_autocmd("LspDetach", {
	group = lsp_notify_group,
	desc = "Dismiss stale progress notifications",
	callback = function(event)
		local prefix = event.data.client_id .. ":"
		for key, id in pairs(progress) do
			if vim.startswith(key, prefix) then
				progress[key] = nil
				notification.dismiss(id)
			end
		end
	end,
})

vim.lsp.config("*", {
	on_exit = function(code, _, client_id)
		if code == 0 then
			return
		end
		vim.schedule(function()
			local client = vim.lsp.get_client_by_id(client_id)
			local name = client and client.name or ("LSP client " .. client_id)
			notification.error(string.format("%s exited with code %d", name, code))
		end)
	end,
})

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
		tex = { "tex-fmt" },
	},
})
