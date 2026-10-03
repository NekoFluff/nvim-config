-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.g.lazyvim_php_lsp = "intelephense"

-- when started in a Godot project, accept "open this file" requests from Godot
if vim.uv.fs_stat(vim.fn.getcwd() .. "/project.godot") then
  pcall(vim.fn.serverstart, vim.fn.getcwd() .. "/godothost")
end
