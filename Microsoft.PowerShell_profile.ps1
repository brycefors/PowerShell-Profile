# --- Dependencies & Setup ---
# Install PSReadLine if missing
if (-not (Get-Module -ListAvailable PSReadLine)) {
    Write-Host "PSReadLine not found. Installing..." -ForegroundColor Yellow
    Install-Module PSReadLine -Force -Scope CurrentUser
}

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

# --- Shell Initialization ---
# Shows navigable menu of all options when hitting Tab
Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete

if ($PSVersionTable.PSVersion.Major -ge 6 -and (Get-Command oh-my-posh -ErrorAction SilentlyContinue) -and ($env:WT_SESSION -or $env:TERM_PROGRAM -eq 'vscode')) {
    $themeUrl = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/blue-owl.omp.json"
    $themeDir = "$env:LOCALAPPDATA\oh-my-posh\themes"
    if ($env:POSH_THEMES_PATH) { $themeDir = $env:POSH_THEMES_PATH }
    if (-not (Test-Path $themeDir)) { New-Item -ItemType Directory -Path $themeDir -Force | Out-Null }

    $themeName = Split-Path $themeUrl -Leaf
    $themePath = Join-Path $themeDir $themeName
    if (-not (Test-Path $themePath)) {
        Write-Host "Downloading Oh My Posh theme ($themeName)..." -ForegroundColor Yellow
        Invoke-WebRequest $themeUrl -OutFile $themePath
    }
    oh-my-posh init pwsh --config $themePath | Invoke-Expression
}

# Enable Predictive IntelliSense (History based)
try {
    Set-PSReadLineOption -PredictionSource History
    Set-PSReadLineOption -PredictionViewStyle ListView
} catch {}

# --- Navigation ---
# Quick Navigation
function global:.. { Set-Location .. }
function global:... { Set-Location ..\.. }

# Create directory and enter it
function global:mk {
    param([Parameter(Mandatory)][string]$Path)
    New-Item -ItemType Directory -Path $Path -Force | Out-Null
    Set-Location $Path
}

# --- File Operations ---
# List files (force)
function global:ll { Get-ChildItem -Force @args }

# Create new file or update timestamp
function global:touch {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path $Path) {
        (Get-Item $Path).LastWriteTime = Get-Date
    } else {
        New-Item -ItemType File -Path $Path -Force | Out-Null
    }
}

# Find file recursively
function global:ff {
    param([Parameter(Mandatory)][string]$Name)
    Get-ChildItem -Recurse -Filter "*$Name*" -ErrorAction SilentlyContinue
}

# Extract zip file
function global:unzip {
    param([Parameter(Mandatory)][string]$Path, [string]$Destination = ".")
    Expand-Archive -Path $Path -DestinationPath $Destination -Force
}

# --- System Utilities ---
# Run as Administrator
function global:sudo {
    param([Parameter(Mandatory)][string]$Command, [Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    Start-Process -FilePath $Command -ArgumentList $Arguments -Verb RunAs
}

# Reboot the computer
function global:reboot {
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
function global:lock {
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
Set-Alias l lock -Scope Global

# Clear PSReadLine History
function global:Clear-PSHistory {
    $historyPath = (Get-PSReadLineOption).HistorySavePath
    if (Test-Path $historyPath) {
        Remove-Item $historyPath -Force
        Write-Host "Persistent history deleted." -ForegroundColor Green
    }
    [Microsoft.PowerShell.PSConsoleReadLine]::ClearHistory()
    Write-Host "In-memory history cleared." -ForegroundColor Green
}

# --- Unix Compatibility ---
Set-Alias grep Select-String -Scope Global
Set-Alias open Invoke-Item -Scope Global

function global:which ([string]$Name) {
    Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
}

function global:df { Get-Volume }

function global:du {
    param([string]$Path = ".")
    $size = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    [PSCustomObject]@{ Path = (Resolve-Path $Path); Size = "{0:N2} MB" -f ($size / 1MB) }
}

function global:free {
    Get-CimInstance Win32_OperatingSystem | Select-Object @{N="Total(GB)";E={"{0:N2}" -f ($_.TotalVisibleMemorySize / 1MB)}}, @{N="Free(GB)";E={"{0:N2}" -f ($_.FreePhysicalMemory / 1MB)}}
}

function global:uptime {
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $uptime = (Get-Date) - $boot
    "Up for $($uptime.Days)d $($uptime.Hours)h $($uptime.Minutes)m"
}

function global:head {
    param([string[]]$Path, [int]$n = 10)
    if ($Path) { Get-Content $Path -TotalCount $n } else { $input | Select-Object -First $n }
}

function global:tail {
    param([string[]]$Path, [int]$n = 10)
    if ($Path) { Get-Content $Path -Tail $n } else { $input | Select-Object -Last $n }
}

function global:wc {
    param([string[]]$Path)
    if ($Path) { Get-Content $Path | Measure-Object -Line -Word -Character } else { $input | Measure-Object -Line -Word -Character }
}

# --- Terminal Configuration ---
# Set Windows Terminal Font
function global:Set-WTFont {
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
function global:Set-VSCodeFont {
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

# --- Profile Management ---
# Quick edit profile
function global:Edit-Profile {
    param([string]$Editor = 'code')
    if (Get-Command $Editor -ErrorAction SilentlyContinue) { & $Editor $PROFILE } else { notepad $PROFILE }
}
Set-Alias pro Edit-Profile -Scope Global

# Reload profile
function global:Import-Profile {
    @(
        $Profile.AllUsersAllHosts,
        $Profile.AllUsersCurrentHost,
        $Profile.CurrentUserAllHosts,
        $Profile.CurrentUserCurrentHost
    ) | ForEach-Object {
        if (Test-Path $_) {
            Write-Verbose "Running $_"
            . $_
        }
    }
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Profiles reloaded." -ForegroundColor Green
}
Set-Alias reload Import-Profile -Scope Global

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

# --- Startup Execution ---
# Auto-configure font if running in Windows Terminal
if ($env:WT_SESSION) {
    Set-WTFont
}
if ($env:TERM_PROGRAM -eq 'vscode') {
    Set-VSCodeFont
}
