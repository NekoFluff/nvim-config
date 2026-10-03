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
    config = function()
      local dap = require("dap")
      dap.adapters.godot = { type = "server", host = "127.0.0.1", port = 6006 }
      dap.configurations.gdscript = {
        { type = "godot", request = "launch", name = "Launch scene", project = "${workspaceFolder}" },
      }
    end,
  },
}
