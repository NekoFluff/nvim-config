return {
  "folke/snacks.nvim",
  opts = {
    picker = {
      sources = {
        explorer = {
          layout = { layout = { position = "right", width = 40 } },
        },
        lsp_definitions = {
          -- jump straight there when only one result is left
          auto_confirm = true,
          -- drop results that come from the ide-helper files
          transform = function(item)
            if item.file and item.file:match("_ide_helper") then
              return false
            end
          end,
        },
      },
    },
  },
}
