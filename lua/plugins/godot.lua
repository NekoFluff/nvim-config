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
-- front. Godot's external editor setting runs it after opening a file, so
-- double-clicking a script in Godot switches straight to Neovim. Finds the
-- window by the "nvim-godot" title set in lua/config/options.lua.
if vim.fn.has("win32") == 1 then
  vim.api.nvim_create_user_command("GodotFocus", function()
    local ffi = require("ffi")
    pcall(ffi.cdef, [[
      typedef int (__stdcall *GODOT_WNDENUMPROC)(void *hwnd, intptr_t lparam);
      int EnumWindows(GODOT_WNDENUMPROC cb, intptr_t lparam);
      int GetWindowTextA(void *hwnd, char *text, int max);
      int IsWindowVisible(void *hwnd);
      int IsIconic(void *hwnd);
      int ShowWindow(void *hwnd, int cmd);
      int SetForegroundWindow(void *hwnd);
      void keybd_event(uint8_t vk, uint8_t scan, uint32_t flags, uintptr_t extra);
    ]])
    local user32 = ffi.load("user32")

    -- find the first visible window whose title contains "nvim-godot"
    local found = nil
    local buf = ffi.new("char[512]")
    local cb = ffi.cast("GODOT_WNDENUMPROC", function(hwnd)
      if user32.IsWindowVisible(hwnd) ~= 0 then
        user32.GetWindowTextA(hwnd, buf, 512)
        if ffi.string(buf):find("nvim-godot", 1, true) then
          found = hwnd
          return 0 -- stop searching
        end
      end
      return 1
    end)
    user32.EnumWindows(cb, 0)
    cb:free()
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
