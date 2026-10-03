-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Godot keymaps: only active inside Godot projects (a folder with project.godot)
-- The GUT run/debug logic lives in lua/godot_gut.lua
local gut = require("godot_gut")

vim.api.nvim_create_autocmd("BufEnter", {
  group = vim.api.nvim_create_augroup("godot_keymaps", { clear = true }),
  callback = function(ev)
    local root = vim.fs.root(ev.buf, "project.godot")
    if not root then
      return -- not a Godot project: add nothing
    end

    local function map(lhs, fn, desc)
      vim.keymap.set("n", lhs, fn, { buffer = ev.buf, desc = desc })
    end

    map("<leader>Gw", function()
      gut.headless = not gut.headless
      vim.notify("GUT headless: " .. (gut.headless and "on" or "off"))
    end, "GUT: toggle headless")

    map("<leader>Gr", function()
      vim.fn.jobstart({ gut.godot, "--path", root }, { detach = true })
    end, "Godot: run project")

    -- run tests (lowercase)
    map("<leader>Ga", function()
      gut.run(root)
    end, "GUT: run all tests")

    map("<leader>Gf", function()
      gut.run(root, gut.file_args())
    end, "GUT: run tests in this file")

    map("<leader>Gt", function()
      local args = gut.test_args()
      if args then
        gut.run(root, args)
      end
    end, "GUT: run test under cursor")

    -- debug tests with breakpoints from <leader>db (uppercase)
    map("<leader>GA", function()
      gut.debug(root)
    end, "GUT: debug all tests")

    map("<leader>GF", function()
      gut.debug(root, gut.file_args())
    end, "GUT: debug tests in this file")

    map("<leader>GT", function()
      local args = gut.test_args()
      if args then
        gut.debug(root, args)
      end
    end, "GUT: debug test under cursor")

    -- debug scenes (Godot 4.7+)
    map("<leader>Gs", function()
      gut.debug_scene(root)
    end, "Godot: debug this file's scene")

    map("<leader>GS", function()
      gut.debug_scene(root, true)
    end, "Godot: debug a scene (pick)")

    -- label the <Space>G group in the which-key menu
    local ok, wk = pcall(require, "which-key")
    if ok then
      wk.add({ { "<leader>G", group = "GUT", buffer = ev.buf } })
    end
  end,
})
