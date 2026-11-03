-- Run and debug GUT (Godot Unit Test) tests from Neovim.
--
-- Running:   starts Godot on the command line with GUT's runner (gut_cmdln.gd).
-- Debugging: asks the Godot editor (through its debug adapter, port 6006) to
--            start a small runner scene that runs the chosen tests, so
--            breakpoints set with <leader>db work inside tests. Needs Godot 4.7+
--            and the Godot editor open on the project. No editor settings needed.

local M = {}

-- Godot executable. Set the GODOT environment variable to override, e.g. on
-- Windows: setx GODOT "C:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe"
-- (the _console.exe shows test output in Neovim's terminal).
M.godot = (function()
  if vim.env.GODOT and vim.env.GODOT ~= "" then
    return vim.env.GODOT
  end
  for _, name in ipairs({ "godot", "godot4", "Godot" }) do
    if vim.fn.executable(name) == 1 then
      return name
    end
  end
  local mac_app = "/Applications/Godot.app/Contents/MacOS/Godot"
  if vim.uv.fs_stat(mac_app) then
    return mac_app
  end
  return "godot" -- not found: commands will fail with a clear error
end)()

M.headless = true -- false = show GUT's window (stays open after the run)

--- GUT command line for normal (non-debug) runs
local function gut_cmd(root, extra)
  local cmd = { M.godot, "--path", root }
  if M.headless then
    table.insert(cmd, "--headless")
  end
  vim.list_extend(cmd, { "-s", "addons/gut/gut_cmdln.gd" })
  if M.headless then
    table.insert(cmd, "-gexit") -- the window version stays open to read results
  end
  if not vim.uv.fs_stat(root .. "/.gutconfig.json") then
    vim.list_extend(cmd, { "-gdir=res://test,res://tests", "-ginclude_subdirs" })
  end
  return vim.list_extend(cmd, extra or {})
end

--- show a command's output in a terminal split
local function terminal(cmd, root)
  if _G.Snacks and Snacks.terminal then
    Snacks.terminal(cmd, {
      cwd = root,
      auto_close = false,
      start_insert = false,
      auto_insert = false,
      -- a split along the bottom (not a float), and keep the cursor in the code
      win = { position = "bottom", height = 0.25, enter = false },
    })
  else
    vim.cmd("botright split | enew")
    vim.fn.jobstart(cmd, { cwd = root, term = true })
  end
end

--- GUT options for "this file" and "test under cursor"
function M.file_args()
  return { "-gselect=" .. vim.fn.expand("%:t") }
end

function M.test_args()
  local lnum = vim.fn.search([[^\s*func\s\+test_]], "bnW")
  local name = lnum > 0 and vim.fn.getline(lnum):match("func%s+(test_[%w_]+)")
  if not name then
    vim.notify("No test function above the cursor", vim.log.levels.WARN)
    return nil
  end
  return { "-gselect=" .. vim.fn.expand("%:t"), "-gunit_test_name=" .. name }
end

--- run tests (-d lets the `breakpoint` keyword stop in the terminal)
function M.run(root, extra)
  local cmd = gut_cmd(root, extra)
  table.insert(cmd, 2, "-d")
  terminal(cmd, root)
end

-- ── Debugging tests ───────────────────────────────────────────────────────
-- A tiny scene that runs GUT with the tests Neovim picked. Written into the
-- project's addons/nvim_gut/ folder (safe to commit). Neovim writes the picked
-- tests to addons/nvim_gut/.nvim_gut.json before each run (add that file to
-- .gitignore).

local RUNNER_DIR = "addons/nvim_gut"
local RUNNER_SCENE = "res://" .. RUNNER_DIR .. "/runner.tscn"
local SELECTION_FILE = RUNNER_DIR .. "/.nvim_gut.json"

local RUNNER_GD = [[
# Runs GUT with the tests Neovim picked. Created by Neovim (lua/godot_gut.lua).
# Neovim's GUT debug keys start this scene through the Godot editor's debugger.
extends Node

const SELECTION := "res://addons/nvim_gut/.nvim_gut.json"

func _ready() -> void:
	var cfg = load("res://addons/gut/gut_config.gd").new()
	cfg.load_options("res://.gutconfig.json") # your GUT settings, if any
	if FileAccess.file_exists(SELECTION):
		cfg.load_options(SELECTION) # which tests to run, from Neovim
	var runner = load("res://addons/gut/gui/GutRunner.tscn").instantiate()
	runner.set_gut_config(cfg)
	# print results to the output (shown in Neovim's debug console)
	runner.get_gut().get_logger().disable_printer("console", false)
	add_child(runner)
	runner.run_tests()
]]

local RUNNER_TSCN = [[
[gd_scene load_steps=2 format=3]

[ext_resource type="Script" path="res://addons/nvim_gut/runner.gd" id="1"]

[node name="NvimGutRunner" type="Node"]
script = ExtResource("1")
]]

--- write a file only when its content changed (so Godot doesn't see edits)
local function write_if_changed(path, text)
  local f = io.open(path, "r")
  if f then
    local old = f:read("*a")
    f:close()
    if old == text then
      return
    end
  end
  vim.fn.mkdir(vim.fs.dirname(path), "p")
  f = assert(io.open(path, "w"))
  f:write(text)
  f:close()
end

--- turn GUT command-line options into GUT config settings
local function selection(root, extra)
  local cfg = {
    selected = "",
    unit_test_name = "",
    include_subdirs = true,
    should_exit = M.headless, -- the window version stays open to read results
  }
  for _, arg in ipairs(extra or {}) do
    cfg.selected = arg:match("^%-gselect=(.*)") or cfg.selected
    cfg.unit_test_name = arg:match("^%-gunit_test_name=(.*)") or cfg.unit_test_name
  end
  if not vim.uv.fs_stat(root .. "/.gutconfig.json") then
    cfg.dirs = {}
    for _, dir in ipairs({ "test", "tests" }) do
      if vim.uv.fs_stat(root .. "/" .. dir) then
        table.insert(cfg.dirs, "res://" .. dir)
      end
    end
  end
  return cfg
end

--- debug tests with nvim-dap
function M.debug(root, extra)
  local ok, dap = pcall(require, "dap")
  if not ok then
    return vim.notify("GUT: nvim-dap is not installed (enable the dap.core extra)", vim.log.levels.ERROR)
  end

  write_if_changed(root .. "/" .. RUNNER_DIR .. "/runner.gd", RUNNER_GD)
  write_if_changed(root .. "/" .. RUNNER_DIR .. "/runner.tscn", RUNNER_TSCN)
  write_if_changed(root .. "/" .. SELECTION_FILE, vim.json.encode(selection(root, extra)))

  dap.run({
    type = "godot",
    request = "launch",
    name = "GUT tests",
    project = root,
    scene = RUNNER_SCENE,
    playArgs = M.headless and { "--headless" } or nil,
  })
end

-- ── Scenes ────────────────────────────────────────────────────────────────
-- Godot 4.7+ can start any scene through its debug adapter, with your
-- breakpoints already set (even ones in _ready).

--- every .tscn in the project (skipping addons and Godot's cache)
function M.scenes(root)
  local found = vim.fs.find(function(name)
    return name:match("%.tscn$") ~= nil
  end, { path = root, type = "file", limit = math.huge })
  local scenes = {}
  for _, path in ipairs(found) do
    local rel = path:sub(#root + 2)
    if not rel:match("^addons/") and not rel:match("^%.godot/") then
      table.insert(scenes, rel)
    end
  end
  table.sort(scenes)
  return scenes
end

--- the scene that belongs to the current file: the .tscn itself, or a .tscn
--- with the same name next to a .gd script (player.gd -> player.tscn)
function M.scene_for_buffer(root)
  local file = vim.fs.normalize(vim.fn.expand("%:p")) -- forward slashes on Windows too
  local scene = file:match("%.tscn$") and file or file:gsub("%.gd$", ".tscn")
  if scene:match("%.tscn$") and vim.uv.fs_stat(scene) then
    return scene:sub(#root + 2)
  end
end

--- start a scene ("res://..." path relative to the project) in the debugger
function M.launch_scene(root, rel)
  require("dap").run({
    type = "godot",
    request = "launch",
    name = "Scene: " .. rel,
    project = root,
    scene = "res://" .. rel,
  })
end

--- debug this file's scene; asks which scene when there isn't one (or pick = true)
function M.debug_scene(root, pick)
  local rel = not pick and M.scene_for_buffer(root)
  if rel then
    return M.launch_scene(root, rel)
  end
  vim.ui.select(M.scenes(root), { prompt = "Debug scene" }, function(choice)
    if choice then
      M.launch_scene(root, choice)
    end
  end)
end

return M
