# --- Shell Configuration ---
# Shows navigable menu of all options when hitting Tab
Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete

# Install and Enable Oh My Posh
if (-not (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    Write-Host "Oh My Posh not found. Installing..." -ForegroundColor Yellow
    winget install JanDeDobbeleer.OhMyPosh -s winget --accept-source-agreements --accept-package-agreements
}

# Install Nerd Font (Meslo) if not found
$fontName = "Meslo"
$fontReg = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts", "HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts"
$isFontInstalled = $fontReg | ForEach-Object {
    $key = Get-Item $_ -ErrorAction SilentlyContinue
    if ($key) { $key.GetValueNames() }
} | Where-Object { $_ -like "*$fontName*" }

if (-not $isFontInstalled -and (Get-Command oh-my-posh -ErrorAction SilentlyContinue)) {
    Write-Host "Nerd Font ($fontName) not found. Installing..." -ForegroundColor Yellow
    oh-my-posh font install meslo
}

if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    $shell = if ($PSVersionTable.PSVersion.Major -le 5) { 'powershell' } else { 'pwsh' }
    oh-my-posh init $shell | Invoke-Expression
}

# Enable Predictive IntelliSense (History based)
if ($PSVersionTable.PSVersion.Major -ge 7) {
    try {
        Set-PSReadLineOption -PredictionSource History -ErrorAction Stop
        Set-PSReadLineOption -PredictionViewStyle ListView -ErrorAction Stop
    } catch {}
}

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

# Set Windows Terminal Font
function Set-WTFont {
    param([string]$FontName = "MesloLGS Nerd Font")
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
    . $PROFILE
    Write-Host "Profile reloaded." -ForegroundColor Green
}

# Auto-configure font if running in Windows Terminal
if ($env:WT_SESSION) {
    Set-WTFont
}