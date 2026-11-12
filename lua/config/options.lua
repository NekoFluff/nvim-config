-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here
vim.g.lazyvim_php_lsp = "intelephense"

-- when started in a Godot project, accept "open this file" requests from Godot
-- (Godot > Editor Settings > Text Editor > External sends them to this address)
if vim.uv.fs_stat(vim.fn.getcwd() .. "/project.godot") then
  if vim.fn.has("win32") == 1 then
    -- Windows uses named pipes instead of socket files
    pcall(vim.fn.serverstart, [[\\.\pipe\godot-nvim]])
    -- window title that scripts/godot-nvim.ps1 looks for to bring Neovim forward
    vim.opt.title = true
    vim.opt.titlestring = "nvim-godot - %t"
  else
    pcall(vim.fn.serverstart, vim.fn.getcwd() .. "/godothost")
  end
end
