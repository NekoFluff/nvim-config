return {
  {
    "NekoFluff/nekofluff.nvim",
    lazy = false,
    priority = 1000,
    opts = {
      transparent = true,
      italic = true, -- italic comments and keywords
    },
  },
  { "LazyVim/LazyVim", opts = { colorscheme = "nekofluff" } },
}
