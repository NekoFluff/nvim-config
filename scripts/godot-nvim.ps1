# Opens a GDScript file from Godot in Neovim and brings Neovim's window forward.
# Windows only. Godot setup (Editor > Editor Settings > Text Editor > External):
#   Exec Path:  C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
#   Exec Flags: -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Users\<you>\AppData\Local\nvim\scripts\godot-nvim.ps1 "{project}" "{file}" {line} {col}
#
# If Neovim is already running in the project (it listens on the named pipe set
# up in lua/config/options.lua), the file opens there at the right line and the
# window titled "nvim-godot ..." is brought to the front. Otherwise a new
# Windows Terminal window opens in the project with the file.
#
# Every run is logged to %TEMP%\godot-nvim.log, to see what happened.

param(
  [string]$Project,
  [string]$File,
  [int]$Line = 1,
  [int]$Col = 1
)

$pipe = '\\.\pipe\godot-nvim'
$title = 'nvim-godot'
$log = Join-Path $env:TEMP 'godot-nvim.log'

function Log([string]$msg) {
  Add-Content -Path $log -Value ((Get-Date -Format 'HH:mm:ss') + ' ' + $msg)
}

# Windows functions to find a window by its title and bring it to the front
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class GodotNvimWindow {
  public delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);
  [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc cb, IntPtr lParam);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hwnd, StringBuilder text, int max);
  [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
  [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
  [DllImport("user32.dll")] static extern bool ShowWindow(IntPtr hwnd, int cmd);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hwnd);
  [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);

  // first visible window whose title contains `part`
  public static IntPtr Find(string part) {
    IntPtr found = IntPtr.Zero;
    EnumWindows(delegate (IntPtr hwnd, IntPtr lParam) {
      if (!IsWindowVisible(hwnd)) return true;
      StringBuilder sb = new StringBuilder(512);
      GetWindowText(hwnd, sb, 512);
      if (sb.ToString().Contains(part)) { found = hwnd; return false; }
      return true;
    }, IntPtr.Zero);
    return found;
  }

  public static bool Focus(IntPtr hwnd) {
    if (IsIconic(hwnd)) ShowWindow(hwnd, 9); // restore if minimized
    // a quick Alt key tap lets Windows allow the switch to another window
    keybd_event(0x12, 0, 0, UIntPtr.Zero);
    keybd_event(0x12, 0, 2, UIntPtr.Zero);
    return SetForegroundWindow(hwnd);
  }
}
"@

try {
  Log "--- project=$Project file=$File line=$Line col=$Col"

  # Neovim: set NVIM_EXE to override, otherwise whatever `nvim` is on PATH
  $nvim = $env:NVIM_EXE
  if (-not $nvim) {
    $cmd = Get-Command nvim -ErrorAction SilentlyContinue
    if ($cmd) { $nvim = $cmd.Source } else { $nvim = 'nvim' }
  }
  Log "nvim=$nvim"

  # try to send the file to a running Neovim (fails if none is listening)
  $vimFile = $File -replace ' ', '\ '
  $out = & $nvim --server $pipe --remote-send "<C-\><C-N>:e $vimFile<CR>:call cursor($Line,$Col)<CR>" 2>&1
  $sent = ($LASTEXITCODE -eq 0)
  Log "sent=$sent $out"

  if ($sent) {
    $hwnd = [GodotNvimWindow]::Find($title)
    if ($hwnd -eq [IntPtr]::Zero) {
      Log "no window with '$title' in its title"
    } else {
      Log ("focused=" + [GodotNvimWindow]::Focus($hwnd))
    }
  } else {
    # no Neovim running: open one in a new Windows Terminal window
    Start-Process wt.exe -ArgumentList @(
      '-d', "`"$Project`"",
      "`"$nvim`"", "`"+call cursor($Line,$Col)`"", "`"$File`""
    )
    Log "started a new Windows Terminal window"
  }
} catch {
  Log "ERROR: $_"
}
