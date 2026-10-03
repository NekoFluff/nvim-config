-- Run and debug GUT (Godot Unit Test) tests from Neovim.
--
-- Running:   starts Godot on the command line with GUT's runner (gut_cmdln.gd).
-- Debugging: starts the same run connected to the Godot editor's debugger, then
--            attaches nvim-dap to it through Godot's debug adapter (port 6006),
--            so breakpoints set with <leader>db work inside tests.
--
-- One-time setup per Godot project, in the Godot editor:
--   Debug menu > "Keep Debug Server Open"  (lets tests started from Neovim
--   connect to the editor's debugger; Godot remembers this per project)

local M = {}

-- Godot executable: `godot` on PATH, otherwise the macOS app
M.godot = vim.fn.exepath("godot") ~= "" and "godot" or "/Applications/Godot.app/Contents/MacOS/Godot"
M.headless = true -- false = show GUT's window (stays open after the run)
M.debug_port = 6007 -- Godot: Editor Settings > Network > Debug > Remote Port

-- GUT pre-run hook. Holds the tests back until nvim-dap has attached, so a
-- breakpoint on the first line of a test is not missed. Written into the
-- project the first time you debug; safe to commit.
local HOOK_RES = "res://addons/nvim_gut/wait_for_debugger.gd"
local HOOK_FILE = "addons/nvim_gut/wait_for_debugger.gd"
local HOOK_SRC = [[
# GUT pre-run hook, created by Neovim's GUT debug keymaps (lua/godot_gut.lua).
# 1. Tells Neovim the test process is up (and whether it reached the editor's
#    debugger) by writing the file named in NVIM_GUT_READY.
# 2. Waits until Neovim's debugger has attached (Neovim creates the file named
#    in NVIM_GUT_MARKER) so breakpoints early in a test are not missed.
# Does nothing when the tests are not started from Neovim's debugger.
extends GutHookScript

const TIMEOUT_SEC := 15.0

func run():
	var ready_path := OS.get_environment("NVIM_GUT_READY")
	var marker := OS.get_environment("NVIM_GUT_MARKER")
	if ready_path == "" or marker == "":
		return
	var f := FileAccess.open(ready_path, FileAccess.WRITE)
	if f:
		f.store_string("ok" if EngineDebugger.is_active() else "no-debugger")
		f = null
	if not EngineDebugger.is_active():
		return
	var waited := 0.0
	while not FileAccess.file_exists(marker) and waited < TIMEOUT_SEC:
		await Engine.get_main_loop().create_timer(0.1).timeout
		waited += 0.1
	if waited >= TIMEOUT_SEC:
		push_warning("nvim_gut: debugger did not attach, running tests anyway")
]]

--- GUT command line shared by run and debug
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
local function terminal(cmd, root, env)
  if _G.Snacks and Snacks.terminal then
    Snacks.terminal(cmd, {
      cwd = root,
      env = env,
      auto_close = false,
      start_insert = false,
      auto_insert = false,
      -- a split along the bottom (not a float), and keep the cursor in the code
      win = { position = "bottom", height = 0.25, enter = false },
    })
  else
    vim.cmd("botright split | enew")
    vim.fn.jobstart(cmd, { cwd = root, env = env, term = true })
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

local listeners_added = false
local function add_listeners(dap)
  if listeners_added then
    return
  end
  listeners_added = true

  -- breakpoints are sent before configurationDone: now let the tests start
  dap.listeners.after.configurationDone["godot_gut"] = function(session)
    local marker = session.config and session.config.nvim_gut_marker
    if marker then
      local f = io.open(marker, "w")
      if f then
        f:close()
      end
    end
  end

  -- the editor can take a moment to register the new process: retry briefly
  dap.listeners.after.attach["godot_gut"] = function(session, err)
    local cfg = session.config or {}
    if not (err and cfg.nvim_gut_marker) then
      return
    end
    local tries = (cfg.nvim_gut_tries or 0) + 1
    if tries > 3 then
      return vim.notify("GUT: couldn't attach the debugger to the test run.", vim.log.levels.ERROR)
    end
    vim.defer_fn(function()
      dap.run(vim.tbl_extend("force", cfg, { nvim_gut_tries = tries }))
    end, 300)
  end
end

--- debug tests with nvim-dap
function M.debug(root, extra)
  local ok, dap = pcall(require, "dap")
  if not ok then
    return vim.notify("GUT: nvim-dap is not installed (enable the dap.core extra)", vim.log.levels.ERROR)
  end
  add_listeners(dap)

  -- create the pre-run hook in the project if it isn't there yet
  local hook = root .. "/" .. HOOK_FILE
  if not vim.uv.fs_stat(hook) then
    vim.fn.mkdir(vim.fs.dirname(hook), "p")
    local f = assert(io.open(hook, "w"))
    f:write(HOOK_SRC)
    f:close()
  end

  local marker = vim.fn.tempname() .. "_nvim_gut"
  local ready = marker .. "_ready"
  local cmd = gut_cmd(root, extra)
  table.insert(cmd, 4, "--remote-debug")
  table.insert(cmd, 5, "tcp://127.0.0.1:" .. M.debug_port)
  table.insert(cmd, "-gpre_run_script=" .. HOOK_RES)
  terminal(cmd, root, { NVIM_GUT_MARKER = marker, NVIM_GUT_READY = ready })

  -- wait for the hook to report in, then attach
  local timer = assert(vim.uv.new_timer())
  local waited = 0
  timer:start(100, 100, vim.schedule_wrap(function()
    waited = waited + 100
    local stat = vim.uv.fs_stat(ready)
    if not stat and waited < 30000 then
      return
    end
    timer:stop()
    timer:close()
    if not stat then
      return vim.notify("GUT: the test run didn't start (see the terminal output).", vim.log.levels.ERROR)
    end
    local f = io.open(ready)
    local status = f and f:read("*a") or ""
    if f then
      f:close()
    end
    if status ~= "ok" then
      return vim.notify(
        "GUT: tests ran without the debugger.\n"
          .. "In Godot, enable Debug > Keep Debug Server Open (keep the editor open).",
        vim.log.levels.ERROR
      )
    end
    dap.run({
      type = "godot",
      request = "attach",
      name = "GUT tests",
      project = root,
      nvim_gut_marker = marker,
    })
  end))
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
  local file = vim.fn.expand("%:p")
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
