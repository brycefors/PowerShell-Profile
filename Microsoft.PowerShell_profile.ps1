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
    param([string]$Command, [Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    
    # Install gsudo (sudo for Windows) if not found
    if (-not (Get-Command gsudo -ErrorAction SilentlyContinue)) {
        Write-Host "gsudo not found. Installing..." -ForegroundColor Yellow
        winget install gerardog.gsudo -s winget --accept-source-agreements --accept-package-agreements
    }

    $cmd = if ($Command) { Get-Command $Command -ErrorAction SilentlyContinue | Select-Object -First 1 } else { $null }
    $isPsCmd = $cmd -and $cmd.CommandType -ne 'Application'
    $hasGsudo = [bool](Get-Command gsudo -ErrorAction SilentlyContinue)

    if ($hasGsudo) {
        if (-not $Command) {
            gsudo
        } elseif ($isPsCmd) {
            $shell = (Get-Process -Id $PID).Path
            $argList = ($Arguments | ForEach-Object { "`"$_`"" }) -join ' '
            gsudo $shell -NoExit -Command "& { $Command $argList }"
        } else {
            gsudo $Command $Arguments
        }
    } else {
        $shell = (Get-Process -Id $PID).Path
        if (-not $Command) {
            Start-Process -FilePath $shell -Verb RunAs -WorkingDirectory $PWD
        } elseif ($isPsCmd) {
            $argList = ($Arguments | ForEach-Object { "`"$_`"" }) -join ' '
            Start-Process -FilePath $shell -ArgumentList "-NoExit", "-Command", "& { $Command $argList }" -Verb RunAs -WorkingDirectory $PWD
        } else {
            Start-Process -FilePath $Command -ArgumentList $Arguments -Verb RunAs -WorkingDirectory $PWD
        }
    }
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

$Global:RebootMarkerPath = "$env:TEMP\ps_scheduled_reboot.xml"

function global:Get-PendingReboot {
    if (-not (Test-Path $Global:RebootMarkerPath)) { return $null }
    try {
        $rebootTime = Import-Clixml $Global:RebootMarkerPath
        $markerTime = (Get-Item $Global:RebootMarkerPath).LastWriteTime
        $bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        
        if ($bootTime -lt $markerTime -and $rebootTime -gt (Get-Date)) {
            return $rebootTime
        }
    } catch {}
    Remove-Item $Global:RebootMarkerPath -Force -ErrorAction SilentlyContinue
    return $null
}

# Schedule a timed reboot
function global:treboot {
    param([string]$Time = "3AM")
    try {
        $target = Get-Date $Time
        if ($target -lt (Get-Date)) { $target = $target.AddDays(1) }
        $seconds = [int]($target - (Get-Date)).TotalSeconds
        
        shutdown.exe /r /t $seconds
        
        $target | Export-Clixml -Path $Global:RebootMarkerPath -Force
        Write-Host "Reboot scheduled for $($target.ToString())" -ForegroundColor Yellow
    } catch {
        Write-Error "Invalid time format (try '2AM', '16:30') or error scheduling."
    }
}

# Abort scheduled reboot
function global:areboot {
    shutdown.exe /a
    if (Test-Path $Global:RebootMarkerPath) {
        Remove-Item $Global:RebootMarkerPath -Force
    }
    Write-Host "Scheduled reboot cancelled." -ForegroundColor Green
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
    if (-not ([System.Management.Automation.PSTypeName]'Win32Functions.Win32PowerControl').Type) {
        Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern bool PostMessage(int hWnd, int hMsg, int wParam, int lParam);' -Name "Win32PowerControl" -Namespace Win32Functions | Out-Null
    }
    [Win32Functions.Win32PowerControl]::PostMessage(0xFFFF, 0x0112, 0xF170, 2) | Out-Null
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
# Set Windows Terminal Appearance
function global:Set-WTAppearance {
    param(
        [string]$FontName = "JetBrainsMonoNL Nerd Font",
        [double]$Opacity = 0.8,
        [bool]$UseAcrylic = $true
    )
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
        
        # Check if update is needed
        $needUpdate = $false
        if ($json.profiles.defaults.font.face -ne $FontName) { $needUpdate = $true }
        if ($json.profiles.defaults.useAcrylic -ne $UseAcrylic) { $needUpdate = $true }
        if ($json.profiles.defaults.acrylicOpacity -ne $Opacity) { $needUpdate = $true }

        if (-not $needUpdate) { return }

        $json.profiles.defaults.font | Add-Member -MemberType NoteProperty -Name "face" -Value $FontName -Force
        $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "useAcrylic" -Value $UseAcrylic -Force
        $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "acrylicOpacity" -Value $Opacity -Force
        $json | ConvertTo-Json -Depth 20 | Set-Content $settingsPath -Encoding UTF8
        Write-Host "Windows Terminal appearance updated. Restart Terminal to see changes." -ForegroundColor Green
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
    Set-WTAppearance
}
if ($env:TERM_PROGRAM -eq 'vscode') {
    Set-VSCodeFont
}

# Check for scheduled reboot
$pendingReboot = Get-PendingReboot
if ($pendingReboot) {
    Write-Host "WARNING: System is scheduled to reboot at $($pendingReboot.ToString())" -ForegroundColor Red -BackgroundColor Black
    Write-Host "Run 'areboot' to cancel." -ForegroundColor Yellow
}
