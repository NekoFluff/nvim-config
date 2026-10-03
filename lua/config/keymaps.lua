-- Keymaps are automatically loaded on the VeryLazy event
-- Default keymaps that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
-- Add any additional keymaps here

-- Godot keymaps: only active inside Godot projects (a folder with project.godot)
local godot = vim.fn.exepath("godot") ~= "" and "godot" or "/Applications/Godot.app/Contents/MacOS/Godot"

local gut_headless = true -- start in headless mode

local function gut(root, extra)
  local cmd = { godot, "-d", "--path", root, "-s", "addons/gut/gut_cmdln.gd" }
  if not gut_headless then
    -- leave the window open after the run so you can read the results
  else
    table.insert(cmd, 2, "--headless")
    table.insert(cmd, "-gexit")
  end
  if not vim.uv.fs_stat(root .. "/.gutconfig.json") then
    vim.list_extend(cmd, { "-gdir=res://test,res://tests", "-ginclude_subdirs" })
  end
  vim.list_extend(cmd, extra or {})
  Snacks.terminal(cmd, { cwd = root, interactive = true, auto_close = false })
end

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
      gut_headless = not gut_headless
      vim.notify("GUT headless: " .. (gut_headless and "on" or "off"))
    end, "GUT: toggle headless")

    map("<leader>Gr", function()
      vim.fn.jobstart({ godot, "--path", root }, { detach = true })
    end, "Godot: run project")

    map("<leader>Ga", function()
      gut(root)
    end, "GUT: run all tests")

    map("<leader>Gf", function()
      gut(root, { "-gselect=" .. vim.fn.expand("%:t") })
    end, "GUT: run tests in this file")

    map("<leader>Gt", function()
      local lnum = vim.fn.search([[^\s*func\s\+test_]], "bnW")
      local name = lnum > 0 and vim.fn.getline(lnum):match("func%s+(test_[%w_]+)")
      if not name then
        return vim.notify("No test function above the cursor", vim.log.levels.WARN)
      end
      gut(root, { "-gselect=" .. vim.fn.expand("%:t"), "-gunit_test_name=" .. name })
    end, "GUT: run test under cursor")

    -- label the <Space>G group in the which-key menu
    local ok, wk = pcall(require, "which-key")
    if ok then
      wk.add({ { "<leader>G", group = "GUT", buffer = ev.buf } })
    end
  end,
})
