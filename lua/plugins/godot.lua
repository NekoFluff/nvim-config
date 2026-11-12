-- Godot: :GodotRefreshDiagnostics (or <leader>Gd) re-checks every open GDScript
-- file. Godot's language server only re-checks the file you save, so after
-- adding or moving a `class_name`, other files can show stale "not declared"
-- errors. Godot must have noticed the new file first: switch to the Godot
-- window once, or turn on Editor Settings > Interface > Editor >
-- "Import Resources When Unfocused".
vim.api.nvim_create_user_command("GodotRefreshDiagnostics", function()
  for _, client in ipairs(vim.lsp.get_clients({ name = "gdscript" })) do
    for bufnr in pairs(client.attached_buffers) do
      if vim.api.nvim_buf_is_loaded(bufnr) then
        local text = table.concat(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false), "\n") .. "\n"
        -- resend the file's current text; Godot re-checks it and updates diagnostics
        client:notify("textDocument/didChange", {
          textDocument = { uri = vim.uri_from_bufnr(bufnr), version = vim.b[bufnr].changedtick },
          contentChanges = { { text = text } },
        })
      end
    end
  end
end, { desc = "Re-check all open GDScript files" })

-- Godot (Windows): :GodotFocus brings this Neovim's terminal window to the
-- front and minimizes every other window on the same monitor. Godot's external
-- editor setting runs it after opening a file, so double-clicking a script in
-- Godot switches straight to Neovim. Finds the window by the "nvim-godot" title
-- set in lua/config/options.lua.
if vim.fn.has("win32") == 1 then
  local MINIMIZE_OTHERS = true -- false: only bring Neovim forward

  vim.api.nvim_create_user_command("GodotFocus", function()
    local ffi = require("ffi")
    local bit = require("bit")
    -- declare each Windows function separately, so re-running is harmless
    for _, decl in ipairs({
      "typedef int (__stdcall *GODOT_WNDENUMPROC)(void *hwnd, intptr_t lparam);",
      "int EnumWindows(GODOT_WNDENUMPROC cb, intptr_t lparam);",
      "int GetWindowTextA(void *hwnd, char *text, int max);",
      "int GetClassNameA(void *hwnd, char *name, int max);",
      "int IsWindowVisible(void *hwnd);",
      "int IsIconic(void *hwnd);",
      "int ShowWindow(void *hwnd, int cmd);",
      "int ShowWindowAsync(void *hwnd, int cmd);",
      "int SetForegroundWindow(void *hwnd);",
      "void *GetWindow(void *hwnd, unsigned int cmd);",
      "intptr_t GetWindowLongPtrA(void *hwnd, int index);",
      "void *MonitorFromWindow(void *hwnd, uint32_t flags);",
      "void keybd_event(uint8_t vk, uint8_t scan, uint32_t flags, uintptr_t extra);",
      "long DwmGetWindowAttribute(void *hwnd, uint32_t attr, void *value, uint32_t size);",
    }) do
      pcall(ffi.cdef, decl)
    end
    local user32 = ffi.load("user32")
    local dwmapi = ffi.load("dwmapi")
    local buf = ffi.new("char[512]")

    local function title(hwnd)
      user32.GetWindowTextA(hwnd, buf, 512)
      return ffi.string(buf)
    end

    -- every visible top-level window
    local windows = {}
    local cb = ffi.cast("GODOT_WNDENUMPROC", function(hwnd)
      if user32.IsWindowVisible(hwnd) ~= 0 then
        table.insert(windows, hwnd)
      end
      return 1
    end)
    user32.EnumWindows(cb, 0)
    cb:free()

    -- this Neovim's window: the first one with "nvim-godot" in its title
    local found = nil
    for _, hwnd in ipairs(windows) do
      if title(hwnd):find("nvim-godot", 1, true) then
        found = hwnd
        break
      end
    end
    if not found then
      return vim.notify("GodotFocus: no window titled nvim-godot", vim.log.levels.WARN)
    end

    if user32.IsIconic(found) ~= 0 then
      user32.ShowWindow(found, 9) -- restore if minimized
    end
    -- a quick Alt key tap lets Windows allow the switch to another window
    user32.keybd_event(0x12, 0, 0, 0)
    user32.keybd_event(0x12, 0, 2, 0)
    user32.SetForegroundWindow(found)

    if not MINIMIZE_OTHERS then
      return
    end

    -- is this a normal app window (not the taskbar, desktop, a tooltip, ...)?
    local skip_class = { Shell_TrayWnd = true, Shell_SecondaryTrayWnd = true, Progman = true, WorkerW = true }
    local cloaked = ffi.new("int[1]")
    local function is_app_window(hwnd)
      if user32.IsIconic(hwnd) ~= 0 or title(hwnd) == "" then
        return false
      end
      if user32.GetWindow(hwnd, 4) ~= nil then -- has an owner: a dialog or popup
        return false
      end
      local style = tonumber(user32.GetWindowLongPtrA(hwnd, -16))
      local exstyle = tonumber(user32.GetWindowLongPtrA(hwnd, -20))
      if bit.band(style, 0x20000) == 0 or bit.band(exstyle, 0x80) ~= 0 then
        return false -- can't be minimized, or a tool window
      end
      user32.GetClassNameA(hwnd, buf, 512)
      if skip_class[ffi.string(buf)] then
        return false
      end
      -- hidden "cloaked" windows (e.g. suspended Store apps)
      if dwmapi.DwmGetWindowAttribute(hwnd, 14, cloaked, 4) == 0 and cloaked[0] ~= 0 then
        return false
      end
      return true
    end

    -- minimize every other app window on the same monitor, without activating it
    local monitor = user32.MonitorFromWindow(found, 2)
    for _, hwnd in ipairs(windows) do
      if hwnd ~= found and user32.MonitorFromWindow(hwnd, 2) == monitor and is_app_window(hwnd) then
        user32.ShowWindowAsync(hwnd, 7) -- SW_SHOWMINNOACTIVE
      end
    end
  end, { desc = "Bring this Neovim window to the front (Windows)" })
end

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
    opts = function()
      local dap = require("dap")
      -- Godot's debug adapter runs inside the Godot editor on port 6006
      dap.adapters.godot = { type = "server", host = "127.0.0.1", port = 6006 }
      dap.configurations.gdscript = {
        {
          type = "godot",
          request = "launch",
          name = "Run game (main scene)",
          project = "${workspaceFolder}",
        },
        {
          type = "godot",
          request = "launch",
          name = "Debug scene open in Godot editor",
          project = "${workspaceFolder}",
          scene = "current",
        },
        {
          type = "godot",
          request = "launch",
          name = "Debug a scene...",
          project = "${workspaceFolder}",
          scene = function()
            local root = vim.fn.getcwd()
            return coroutine.create(function(co)
              vim.ui.select(require("godot_gut").scenes(root), { prompt = "Debug scene" }, function(choice)
                coroutine.resume(co, choice and ("res://" .. choice) or require("dap").ABORT)
              end)
            end)
          end,
        },
        {
          -- debug something already running from the Godot editor
          type = "godot",
          request = "attach",
          name = "Attach to running game",
          project = "${workspaceFolder}",
        },
      }
      -- close the debug panels when a session ends. LazyVim only closes them on
      -- "terminated"/"exited" events, which Godot doesn't always send.
      dap.listeners.on_session["close_dapui"] = function(_, new_session)
        if new_session == nil then
          pcall(function()
            require("dapui").close({})
          end)
        end
      end

      -- show Godot's error message when a script error stops the game.
      -- Godot sends it with the "stopped" event, which nvim-dap doesn't display.
      dap.listeners.after.event_stopped["godot_error_message"] = function(session, body)
        if session.config.type ~= "godot" or body.reason ~= "exception" or not body.text then
          return
        end
        vim.notify(body.text, vim.log.levels.ERROR, { title = "Godot error" })
        pcall(function()
          require("dap.repl").append("ERROR: " .. body.text .. "\n")
        end)
      end

      -- GUT tests: <leader>GA / GF / GT, scenes: <leader>Gs / GS (lua/godot_gut.lua)
    end,
  },
}
