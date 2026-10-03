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
      -- GUT tests: <leader>GA / GF / GT, scenes: <leader>Gs / GS (lua/godot_gut.lua)
    end,
  },
}
