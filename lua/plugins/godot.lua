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
}
