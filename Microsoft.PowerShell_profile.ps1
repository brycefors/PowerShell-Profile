# --- Shell Configuration ---
# Install PSReadLine if missing
if (-not (Get-Module -ListAvailable PSReadLine)) {
    Write-Host "PSReadLine not found. Installing..." -ForegroundColor Yellow
    Install-Module PSReadLine -Force -Scope CurrentUser
}

# Shows navigable menu of all options when hitting Tab
Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete

# Install and Enable Oh My Posh
if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    Write-Host "Oh My Posh not found. Installing..." -ForegroundColor Yellow
    winget install JanDeDobbeleer.OhMyPosh -s winget --accept-source-agreements --accept-package-agreements
}

# Install Nerd Font (JetBrainsMono) if not found
$fontName = "JetBrainsMono"
$fontReg = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts", "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
$isFontInstalled = $fontReg | ForEach-Object {
    $key = Get-Item $_ -ErrorAction SilentlyContinue
    if ($key) { $key.GetValueNames() }
} | Where-Object { $_ -like "*$fontName*" }

if (-not $isFontInstalled -and (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    Write-Host "Nerd Font ($fontName) not found. Installing..." -ForegroundColor Yellow
    oh-my-posh font install $fontName
}

if ($PSVersionTable.PSVersion.Major -ge 6 -and (Get-Command oh-my-posh -ErrorAction SilentlyContinue) -and ($env:WT_SESSION -or $env:TERM_PROGRAM -eq 'vscode')) {
    oh-my-posh init pwsh | Invoke-Expression
}

# Enable Predictive IntelliSense (History based)
try {
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle ListView
} catch {}


# --- Completions ---
# Register winget autocomplete
Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
        [Console]::InputEncoding = [Console]::OutputEncoding = $OutputEncoding = [System.Text.Utf8Encoding]::new()
        $Local:word = $wordToComplete.Replace('"', '""')
        $Local:ast = $commandAst.ToString().Replace('"', '""')
        winget complete --word="$Local:word" --commandline "$Local:ast" --position $cursorPosition | ForEach-Object {
            [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
        }
}

# --- Navigation ---
# Quick Navigation
function .. { Set-Location .. }
function ... { Set-Location ..\.. }

# Create directory and enter it
function mk {
    param([Parameter(Mandatory)][string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Set-Location $Path
}

# --- File Operations ---
# List files (force)
function ll { Get-ChildItem -Force @args }

# Create new file or update timestamp
function touch {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path $Path) {
        (Get-Item $Path).LastWriteTime = Get-Date
    } else {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    }
}

# Find file recursively
function ff {
    param([Parameter(Mandatory)][string]$Name)
    Get-ChildItem -Recurse -Filter "*$Name*" -ErrorAction SilentlyContinue
}

# Extract zip file
function unzip {
    param([Parameter(Mandatory)][string]$Path, [string]$Destination = ".")
    Expand-Archive -Path $Path -DestinationPath $Destination -Force
}

# --- System & Utilities ---
# Run as Administrator
function sudo {
    param([Parameter(Mandatory)][string]$Command, [Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    Start-Process -FilePath $Command -ArgumentList $Arguments -Verb RunAs
}

# Reboot the computer
function reboot {
    Write-Host "Rebooting in 5 seconds... Press any key to cancel." -ForegroundColor Yellow
    for ($i = 5; $i -gt 0; $i--) {
        Write-Host -NoNewline "$i... "
        for ($j = 0; $j -lt 10; $j++) {
            if ([Console]::KeyAvailable) {
                $null = [Console]::ReadKey($true)
                Write-Host "`nReboot cancelled." -ForegroundColor Green
                return
            }
            Start-Sleep -Milliseconds 100
        }
    }
    Write-Host "`nRebooting..." -ForegroundColor Red
    Restart-Computer
}

# Lock the computer and turn off monitors
function lock {
    Write-Host "Locking in 5 seconds... Press any key to cancel." -ForegroundColor Yellow
    for ($i = 5; $i -gt 0; $i--) {
        Write-Host -NoNewline "$i... "
        for ($j = 0; $j -lt 10; $j++) {
            if ([Console]::KeyAvailable) {
                $null = [Console]::ReadKey($true)
                Write-Host "`nLock cancelled." -ForegroundColor Green
                return
            }
            Start-Sleep -Milliseconds 100
        }
    }
    Write-Host "`nLocking..." -ForegroundColor Red
    rundll32.exe user32.dll,LockWorkStation
    if (-not ([System.Management.Automation.PSTypeName]'Win32Functions.Win32SendMessage').Type) {
        Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern int SendMessage(int hWnd, int hMsg, int wParam, int lParam);' -Name "Win32SendMessage" -Namespace Win32Functions | Out-Null
    }
    [Win32Functions.Win32SendMessage]::SendMessage(0xFFFF, 0x0112, 0xF170, 2) | Out-Null
}
Set-Alias l lock

# Set Windows Terminal Font
function Set-WTFont {
    param([string]$FontName = "JetBrainsMonoNL Nerd Font")
    $settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    
    if (-not (Test-Path $settingsPath)) { return }
    
    try {
        $jsonContent = Get-Content $settingsPath -Raw
        if ($PSVersionTable.PSVersion.Major -le 5) {
            $jsonContent = $jsonContent -replace '(?m)^\s*//.*$',''
        }
        $json = $jsonContent | ConvertFrom-Json
        if (-not $json.profiles.defaults) { $json.profiles | Add-Member -MemberType NoteProperty -Name "defaults" -Value ([PSCustomObject]@{}) }
        if (-not $json.profiles.defaults.font) { $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "font" -Value ([PSCustomObject]@{}) }
        
        # Only update if different
        if ($json.profiles.defaults.font.face -eq $FontName) { return }
        
        $json.profiles.defaults.font | Add-Member -MemberType NoteProperty -Name "face" -Value $FontName -Force
        $json | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8
        Write-Host "Windows Terminal font updated to '$FontName'. Restart Terminal to see changes." -ForegroundColor Green
    } catch {}
}

# Set VS Code Font
function Set-VSCodeFont {
    param([string]$FontName = "JetBrainsMonoNL Nerd Font")
    $settingsPath = "$env:APPDATA\Code\User\settings.json"
    
    if (-not (Test-Path $settingsPath)) { return }
    
    try {
        $jsonContent = Get-Content $settingsPath -Raw
        $jsonContent = $jsonContent -replace '(?m)^\s*//.*$',''
        $json = $jsonContent | ConvertFrom-Json
        
        if ($json.'terminal.integrated.fontFamily' -eq $FontName) { return }
        
        $json | Add-Member -MemberType NoteProperty -Name "terminal.integrated.fontFamily" -Value $FontName -Force
        $json | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8
        Write-Host "VS Code font updated to '$FontName'. Reload window to see changes." -ForegroundColor Green
    } catch {}
}

# Clear PSReadLine History
function Clear-PSHistory {
    $historyPath = (Get-PSReadLineOption).HistorySavePath
    if (Test-Path $historyPath) {
        Remove-Item $historyPath -Force
        Write-Host "Persistent history deleted." -ForegroundColor Green
    }
    [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory()
    Write-Host "In-memory history cleared." -ForegroundColor Green
}

Set-Alias grep Select-String
Set-Alias which Get-Command

# --- Profile Management ---
# Quick edit profile
function Edit-Profile {
    param([string]$Editor = 'code')
    if (Get-Command $Editor -ErrorAction SilentlyContinue) { & $Editor $PROFILE } else { notepad $PROFILE }
}
Set-Alias pro Edit-Profile

# Reload profile
function reload {
    try {
        . $PROFILE
        Write-Host "Profile reloaded from '$PROFILE'." -ForegroundColor Green
    } catch {
        Write-Error "Error reloading profile: $_"
    }
}

# Auto-configure font if running in Windows Terminal
if ($env:WT_SESSION) {
    Set-WTFont
}
if ($env:TERM_PROGRAM -eq 'vscode') {
    Set-VSCodeFont
}
