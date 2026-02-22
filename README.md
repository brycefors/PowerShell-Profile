# PowerShell Profile

This repository contains my personal PowerShell profile script, designed to enhance the terminal experience on Windows with improved aesthetics, navigation shortcuts, and utility functions tailored to my workflow.

## Features

### 🎨 Appearance & Shell Configuration
- **Oh My Posh**: Automatically checks for, installs (via `winget`), and initializes Oh My Posh for a rich prompt experience.
- **Nerd Fonts**: Detects if the **Meslo** Nerd Font is installed. If not, it installs it automatically.
- **Windows Terminal Auto-Config**: If running inside Windows Terminal, it attempts to update the `settings.json` to use the installed Nerd Font automatically.
- **IntelliSense**: Enables History-based Predictive IntelliSense with a ListView style (requires PowerShell 7+).
- **Tab Completion**: Sets `Tab` key to `MenuComplete` for a navigable menu of options.

### 🛠 Custom Functions & Aliases

#### Navigation
- `..`: Go up one directory.
- `...`: Go up two directories.
- `mk <path>`: Create a directory and immediately enter it (`mkdir` + `cd`).

#### File Operations
- `ll`: List all files (forces display of hidden items).
- `touch <path>`: Create a new file or update the timestamp of an existing one.
- `ff <name>`: Find files recursively by name in the current directory.
- `unzip <path> [destination]`: Extract a zip file (defaults to current directory).

#### System & Utilities
- `sudo <command>`: Run a command as Administrator.
- `grep`: Alias for `Select-String`.
- `which`: Alias for `Get-Command`.
- **Winget Completion**: Registers native argument completion for `winget`.

#### Profile Management
- `pro`: Edit the profile script (launches VS Code if available, falls back to Notepad).
- `reload`: Reload the profile script in the current session.

## Installation

1. Clone this repository and navigate into the directory.
2. Run the following command to symlink your profile:

```powershell
# Run in PowerShell as Administrator inside the repo folder
New-Item -ItemType SymbolicLink -Path $PROFILE -Value "$PWD\Microsoft.PowerShell_profile.ps1" -Force
```

## Requirements

- **PowerShell**: Supports Windows PowerShell 5.1 and PowerShell 7+ (Core).
- **Winget**: Required for the automatic installation of Oh My Posh.
- **Windows Terminal**: Recommended for full font and glyph support.

> **Note**: The script modifies Windows Terminal settings (`settings.json`) to apply the font. It creates a backup of the settings implicitly by how `Set-Content` works, but reviewing the `Set-WTFont` function is recommended before running.
