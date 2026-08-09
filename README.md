# PowerShell Profile

This repository contains my personal PowerShell profile script, designed to enhance the terminal experience on Windows with improved aesthetics, navigation shortcuts, and utility functions tailored to my workflow.

## Features

### 🎨 Appearance & Shell Configuration
- **Oh My Posh**: Automatically checks for, installs (via `winget`), and initializes Oh My Posh for a rich prompt experience.
- **Theme Switcher**: Built-in `theme` command to browse and apply Oh My Posh themes from GitHub.
- **Nerd Fonts**: Configures **JetBrains Mono** Nerd Font as the default font if running in a supported terminal.
- **Windows Terminal Auto-Config**: If running inside Windows Terminal, it attempts to update the `settings.json` to use the installed Nerd Font automatically. You can also run `Set-WTAppearance -Opacity 0.85 -UseAcrylic $true` to customize the look.
- **VS Code Auto-Config**: If running inside VS Code, it attempts to update the `settings.json` to use the installed Nerd Font automatically.
- **IntelliSense**: Enables History-based Predictive IntelliSense with a ListView style (requires PowerShell 7+).
- **Tab Completion**: Sets `Tab` key to `MenuComplete` for a navigable menu of options.

### 🛠 Custom Functions & Aliases

#### Navigation
- `..`: Go up one directory.
- `...`: Go up two directories.
- `mk <path>`: Alias for `New-DirectoryAndEnter`. Create a directory and immediately enter it (`mkdir` + `cd`).

#### File Operations
- `ll`: Alias for `Get-ChildItemForce`. List all files (forces display of hidden items).
- `touch <path>`: Alias for `Update-FileTimestamp`. Create a new file or update the timestamp of an existing one.
- `ff <name>`: Alias for `Find-File`. Find files recursively by name in the current directory.
- `unzip <path> [destination]`: Alias for `Expand-ArchiveFile`. Extract a zip file (defaults to current directory).

#### System & Utilities
- `theme`: Alias for `Set-PoshTheme`. Opens a menu to browse, download, and apply Oh My Posh themes from GitHub.
- `slideshow`: Alias for `Show-PoshThemeSlideshow`. Cycles through Oh My Posh themes (alphabetical by default). Use `-Random` to shuffle, and `-Seconds <int>` to set duration. Controls: `Left`/`Right` to navigate, `Enter` to select, `Esc` to cancel.
- `sudo [command]`: Alias for `Invoke-ElevatedCommand`. Run a command as Administrator (or elevate current shell if no command provided).
- `reboot`: Alias for `Invoke-RebootCountdown`. Reboot the computer with a 5-second countdown (cancellable).
- `treboot [time]`: Alias for `Register-ScheduledReboot`. Schedule a reboot at a specific time (defaults to 3AM).
- `areboot`: Alias for `Unregister-ScheduledReboot`. Cancel a scheduled reboot.
- `lock` (alias `l`): Alias for `Invoke-LockWorkstation`. Lock the workstation and turn off monitors with a 5-second countdown (cancellable).
- `Clear-PSHistory`: Clears both in-memory and persistent PSReadLine history.
- **Winget Completion**: Registers native argument completion for `winget`.
- `up`: Alias for `Update-WindowsPackages`. Upgrades software via `winget`, updates NVIDIA drivers (if GPU detected), updates User-scope PowerShell modules (with auto-fix for conflicts), runs Windows Updates (via `PSWindowsUpdate`), and reloads `PATH`.
- `Install-Git`: Checks for and installs Git via `winget` if not present.
- `Refresh-Path`: Alias for `Update-EnvironmentPath`. Reloads the `PATH` environment variable from the registry (Machine + User).
- `kill-port <port>`: Alias for `Stop-PortProcess`. Finds and stops the process listening on a specific TCP port.
- `cleanup`: Alias for `Start-SystemCleanup`. Empties Recycle Bin, cleans Temp folders, and launches Windows Disk Cleanup.

#### Unix Compatibility
- `grep`: Alias for `Select-String`.
- `open`: Alias for `Invoke-Item`.
- `which <name>`: Alias for `Get-CommandSource`. Returns the source path of a command.
- `base64 <string>`: Alias for `Convert-Base64`. Encode a string to Base64 (use `-Decode` switch to decode).
- `df`: Alias for `Get-VolumeInfo`. View disk volume information.
- `du [path]`: Alias for `Get-DirectorySize`. Calculate directory size.
- `free`: Alias for `Get-MemoryUsage`. Display memory usage (Total/Free).
- `uptime`: Alias for `Get-SystemUptime`. Show system uptime.
- `ip`: Alias for `Get-NetworkSummary`. Display a detailed, colored summary of network interfaces, IPs, and DNS.
- `head [file]`: Alias for `Get-ContentHead`. Display first 10 lines (supports pipeline).
- `tail [file]`: Alias for `Get-ContentTail`. Display last 10 lines (supports pipeline).
- `wc [file]`: Alias for `Measure-Content`. Count lines, words, and characters (supports pipeline).

#### Git Shortcuts
- `gst`: `git status -sb` (short format).
- `gco [branch]`: Checkout a branch. If no argument provided, opens a GUI list to select a branch.
- `gcmsg <msg>`: `git commit -m`
- `gpush`: `git push`. Automatically sets upstream origin if pushing a new branch.
- `gpull`: `git pull`
- `glog`: Pretty-printed git log with graph, relative dates, and colors.
- `gaa`: `git add --all`
- `gcb <name>`: `git checkout -b` (create and switch to branch)
- `gcom [msg]`: Stage all changes and commit. If `msg` is provided, uses it. Otherwise, shows status and prompts.
- `gd`: `git diff`
- `gbr`: `git branch`
- `gsta`: `git stash push`
- `gstp`: `git stash pop`

#### Profile Management
- `pro`: Edit the profile script (launches VS Code if available, falls back to Notepad).
- `reload`: Reload the profile script. Use `reload -ClearCache` to force a deep clean of caches (Oh My Posh, fonts, etc.).
- `pull-profile`: Alias for `Update-ProfileFromRemote`. Downloads the latest profile version from GitHub and reloads it.

## Installation

### Option 1: `install.bat` (automated)

Double-click `install.bat` (or run it from `cmd`). It bootstraps everything from a clean machine:

1. **Checks for PowerShell 7** — skips ahead if `pwsh.exe` is already on `PATH`.
2. **Installs it via `winget`** (`Microsoft.PowerShell`) with source/package agreements auto-accepted.
3. **Falls back to a direct MSI download** if `winget` is unavailable or fails. It queries the PowerShell GitHub releases API for the latest release, picks the MSI matching the CPU architecture (`x64`, `arm64`, or `x86`), downloads it to `%TEMP%`, and installs it silently with `msiexec /qn /norestart ADD_PATH=1` (prompts for elevation; exit code `3010` = reboot pending is treated as success). The MSI is deleted afterward.
4. **Refreshes `PATH`** from the registry (Machine + User) so the freshly installed `pwsh.exe` is usable without reopening the window.
5. **Installs the profile to every host** — resolves the real `Documents` location via `$PROFILE.CurrentUserCurrentHost` (so OneDrive-redirected folders work), then writes to:
   - `Documents\PowerShell\Microsoft.PowerShell_profile.ps1` (PowerShell 7)
   - `Documents\PowerShell\Microsoft.VSCode_profile.ps1` (PowerShell 7 in the VS Code extension host)
   - `Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1` (Windows PowerShell 5.1)
   - `Documents\WindowsPowerShell\Microsoft.VSCode_profile.ps1` (Windows PowerShell 5.1 in the VS Code extension host)

   Each existing file is backed up to `*.bak_<timestamp>` first, and the profile is written as UTF-8 **with BOM** with CRLF line endings so Windows PowerShell 5.1 reads it correctly.

Start a new `pwsh`, `powershell`, or VS Code terminal session afterward to load the profile.

### Option 2: Symlink (for development)

1. Clone this repository and navigate into the directory.
2. Run the following command to symlink your profile:

```powershell
# Run in PowerShell as Administrator inside the repo folder
New-Item -ItemType SymbolicLink -Path $PROFILE -Value "$PWD\Microsoft.PowerShell_profile.ps1" -Force
```

## Requirements

- **PowerShell**: Supports Windows PowerShell 5.1 and PowerShell 7+ (Core).
- **Winget**: Used for automatic installs (Oh My Posh, gsudo, Git, `up`). It is optional — every winget call is guarded, so without it the profile still loads and prints a skip message instead of erroring. Oh My Posh falls back to the official per-user MSIX package from `cdn.ohmyposh.dev`, and `install.bat` falls back to a direct MSI download for PowerShell 7 itself.
- **gsudo**: Recommended for inline `sudo` elevation (installed automatically if missing).
- **Windows Terminal**: Recommended for full font and glyph support.
- **JetBrains Mono Nerd Font**: The profile configures the terminal to use `JetBrainsMonoNL Nerd Font`.

> **Note**: The script modifies Windows Terminal settings (`settings.json`) to apply the font. It does **not** create a backup of the settings, so reviewing the `Set-WTAppearance` function is recommended before running.
