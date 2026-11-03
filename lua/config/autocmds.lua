-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Godot: :GodotRefreshDiagnostics (or <leader>Gd) re-checks every open GDScript
-- file. Godot's language server only re-checks the file you save, so after
-- adding or moving a `class_name`, other files can show stale "not declared"
-- errors. Godot must have noticed the new file first: switch to the Godot
-- window once, or turn on Editor Settings > Interface > Editor >
-- "Import Resources When Unfocused".
vim.api.nvim_create_user_command("GodotRefreshDiagnostics", function()
  for _, client in ipairs(vim.lsp.get_clients({ name = "gdscript" })) do
    for bufnr in pairs(client.attached_buffers) do
      if vim.api.nvim_buf_is_loaded(bufnr) then
        local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n") .. "\n"
        -- resend the file's current text; Godot re-checks it and updates diagnostics
        client:notify("textDocument/didChange", {
          textDocument = { uri = vim.uri_from_bufnr(bufnr), version = vim.b[bufnr].changedtick },
          contentChanges = { { text = text } },
        })
      end
    end
  end
end, { desc = "Re-check all open GDScript files" })
