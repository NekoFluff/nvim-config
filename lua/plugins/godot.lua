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

return {
  -- syntax highlighting for scripts, scenes/resources and shaders
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "gdscript", "godot_resource", "gdshader" } },
  },

  -- connect to the language server built into the Godot editor (port 6005)
  {
    "neovim/nvim-lspconfig",
    opts = {
      servers = {
        gdscript = { mason = false }, -- comes from Godot itself, not Mason
      },
    },
  },
  -- gdtoolkit
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "gdtoolkit" } },
  },
  -- linter and formatter
  { "stevearc/conform.nvim", opts = { formatters_by_ft = { gdscript = { "gdformat" } } } },

  -- debugger
  {
    "mfussenegger/nvim-dap",
    optional = true,
    opts = function()
      local dap = require("dap")
      -- Godot's debug adapter runs inside the Godot editor on port 6006
      dap.adapters.godot = { type = "server", host = "127.0.0.1", port = 6006 }
      dap.configurations.gdscript = {
        {
          type = "godot",
          request = "launch",
          name = "Run game (main scene)",
          project = "${workspaceFolder}",
        },
        {
          type = "godot",
          request = "launch",
          name = "Debug scene open in Godot editor",
          project = "${workspaceFolder}",
          scene = "current",
        },
        {
          type = "godot",
          request = "launch",
          name = "Debug a scene...",
          project = "${workspaceFolder}",
          scene = function()
            local root = vim.fn.getcwd()
            return coroutine.create(function(co)
              vim.ui.select(require("godot_gut").scenes(root), { prompt = "Debug scene" }, function(choice)
                coroutine.resume(co, choice and ("res://" .. choice) or require("dap").ABORT)
              end)
            end)
          end,
        },
        {
          -- debug something already running from the Godot editor
          type = "godot",
          request = "attach",
          name = "Attach to running game",
          project = "${workspaceFolder}",
        },
      }
      -- close the debug panels when a session ends. LazyVim only closes them on
      -- "terminated"/"exited" events, which Godot doesn't always send.
      dap.listeners.on_session["close_dapui"] = function(_, new_session)
        if new_session == nil then
          pcall(function()
            require("dapui").close({})
          end)
        end
      end

      -- show Godot's error message when a script error stops the game.
      -- Godot sends it with the "stopped" event, which nvim-dap doesn't display.
      dap.listeners.after.event_stopped["godot_error_message"] = function(session, body)
        if session.config.type ~= "godot" or body.reason ~= "exception" or not body.text then
          return
        end
        vim.notify(body.text, vim.log.levels.ERROR, { title = "Godot error" })
        pcall(function()
          require("dap.repl").append("ERROR: " .. body.text .. "\n")
        end)
      end

      -- GUT tests: <leader>GA / GF / GT, scenes: <leader>Gs / GS (lua/godot_gut.lua)
    end,
  },
}
