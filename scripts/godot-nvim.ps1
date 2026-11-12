# Opens a GDScript file from Godot in Neovim and brings Neovim's window forward.
# Windows only. Godot setup (Editor > Editor Settings > Text Editor > External):
#   Exec Path:  C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe
#   Exec Flags: -NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\Users\<you>\AppData\Local\nvim\scripts\godot-nvim.ps1 "{project}" "{file}" {line} {col}
#
# If Neovim is already running in the project (it listens on the named pipe set
# up in lua/config/options.lua), the file opens there at the right line and the
# window titled "nvim-godot ..." is brought to the front. Otherwise a new
# Windows Terminal window opens in the project with the file.

param(
  [string]$Project,
  [string]$File,
  [int]$Line = 1,
  [int]$Col = 1
)

$pipe = '\\.\pipe\godot-nvim'
$title = 'nvim-godot'

# Neovim: set NVIM_EXE to override, otherwise whatever `nvim` is on PATH
$nvim = $env:NVIM_EXE
if (-not $nvim) {
  $cmd = Get-Command nvim -ErrorAction SilentlyContinue
  if ($cmd) { $nvim = $cmd.Source } else { $nvim = 'nvim' }
}

$running = [System.IO.Directory]::GetFiles('\\.\pipe\') -contains $pipe

if ($running) {
  # escape spaces for Vim's :e command
  $vimFile = $File -replace ' ', '\ '
  & $nvim --server $pipe --remote-send "<C-\><C-N>:e $vimFile<CR>:call cursor($Line,$Col)<CR>"

  # bring Neovim's terminal window to the front
  $shell = New-Object -ComObject WScript.Shell
  if (-not $shell.AppActivate($title)) {
    Start-Sleep -Milliseconds 200
    [void]$shell.AppActivate($title)
  }
}
else {
  # start Neovim in a new Windows Terminal window, in the project folder
  Start-Process wt.exe -ArgumentList @(
    '-d', "`"$Project`"",
    "`"$nvim`"", "`"+call cursor($Line,$Col)`"", "`"$File`""
  )
}
