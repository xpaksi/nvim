local expanded_tab
local source_tab

local function toggle()
	if expanded_tab and vim.api.nvim_tabpage_is_valid(expanded_tab) then
		local return_tab = vim.api.nvim_get_current_tabpage()
		if return_tab == expanded_tab then
			return_tab = source_tab
		end

		vim.api.nvim_set_current_tabpage(expanded_tab)
		vim.cmd.tabclose()

		if return_tab and vim.api.nvim_tabpage_is_valid(return_tab) then
			vim.api.nvim_set_current_tabpage(return_tab)
		end

		expanded_tab = nil
		source_tab = nil
		return
	end

	source_tab = vim.api.nvim_get_current_tabpage()
	vim.cmd("tab split")
	expanded_tab = vim.api.nvim_get_current_tabpage()
end

vim.keymap.set("n", "<S-Esc>", toggle, { desc = "Toggle expanded buffer" })
