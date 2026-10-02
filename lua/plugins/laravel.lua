-- treat *.blade.php files as Blade templates
vim.filetype.add({ pattern = { [".*%.blade%.php"] = "blade" } })

return {
  -- syntax highlighting for Blade
  {
    "nvim-treesitter/nvim-treesitter",
    opts = { ensure_installed = { "php", "php_only", "blade", "html" } },
  },

  -- format PHP with Laravel Pint instead of php-cs-fixer
  {
    "stevearc/conform.nvim",
    opts = { formatters_by_ft = { blade = { "blade-formatter" } } },
  },
  {
    "mason-org/mason.nvim",
    opts = { ensure_installed = { "blade-formatter" } },
  },

  -- press gf on <x-component> or @include('view') to jump to that file
  { "ricardoramirezr/blade-nav.nvim", ft = { "blade", "php" } },
}
