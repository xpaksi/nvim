local M = {}

M.binary_name = "pi"

function M.executable()
	local path = vim.fn.exepath(M.binary_name)
	if path == "" then
		return nil
	end

	local resolved = vim.fn.resolve(path)
	return resolved ~= "" and resolved or path
end

return M
