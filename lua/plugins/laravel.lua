-- treat *.blade.php files as Blade templates
vim.filetype.add({ pattern = { [".*%.blade%.php"] = "blade" } })

return {
  -- syntax highlighting for Blade
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "php", "php_only", "blade", "html" } },
  },

  -- format Blade templates
  {
    "stevearc/conform.nvim",
    opts = { formatters_by_ft = { blade = { "blade-formatter" } } },
  },
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "blade-formatter" } },
  },

  -- disable phpcs
  {
    "mfussenegger/nvim-lint",
    opts = { linters_by_ft = { php = {} } },
  },

  -- press gf on <x-component> or @include('view') to jump to that file
  { "ricardoramirezr/blade-nav.nvim", ft = { "blade", "php" } },
}
