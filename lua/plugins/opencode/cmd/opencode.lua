local M = {}

local binary_name = "opencode2"
local binary_path = vim.fn.exepath(binary_name)
local resolved_binary_path = binary_path ~= "" and vim.fn.resolve(binary_path) or ""

M.binary_name = binary_name
M.binary_path = binary_path
M.resolved_binary_path = resolved_binary_path
M.binary_dir = resolved_binary_path ~= "" and vim.fs.dirname(resolved_binary_path) or ""

return M
