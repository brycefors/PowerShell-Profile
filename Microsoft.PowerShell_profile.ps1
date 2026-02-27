# --- Shell Initialization ---
# Shows navigable menu of all options when hitting Tab
Set-PSReadlineKeyHandler -Key Tab -Function MenuComplete

if ($PSVersionTable.PSVersion.Major -ge 6 -and ($env:WT_SESSION -or $env:TERM_PROGRAM -eq 'vscode')) {
    $ompCmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    if (-not $ompCmd) {
        Write-Host "Oh My Posh not found. Installing..." -ForegroundColor Yellow
        winget install JanDeDobbeleer.OhMyPosh -s winget --accept-source-agreements --accept-package-agreements
        $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
        $ompCmd = Get-Command oh-my-posh -ErrorAction SilentlyContinue
    }

    if ($ompCmd) {
        $themeUrl = "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/blue-owl.omp.json"
        $themeDir = "$env:LOCALAPPDATA\oh-my-posh\themes"
        if ($env:POSH_THEMES_PATH) { $themeDir = $env:POSH_THEMES_PATH }
        if (-not (Test-Path $themeDir)) { $null = New-Item -ItemType Directory -Path $themeDir -Force }

        $themeName = Split-Path $themeUrl -Leaf
        $themePath = Join-Path $themeDir $themeName
        if (-not (Test-Path $themePath)) {
            Write-Host "Downloading Oh My Posh theme ($themeName)..." -ForegroundColor Yellow
            Invoke-WebRequest $themeUrl -OutFile $themePath
        }

        # Cache the init script; only regenerate when oh-my-posh is updated
        # This significantly improves startup time by avoiding the 'oh-my-posh init' command overhead on every shell launch.
        $ompInitScript = "$env:TEMP\omp_init.ps1"
        if (-not (Test-Path $ompInitScript) -or
            ($ompCmd.Source -and [System.IO.File]::GetLastWriteTime($ompCmd.Source) -gt [System.IO.File]::GetLastWriteTime($ompInitScript))) {
            oh-my-posh init pwsh --config $themePath | Set-Content $ompInitScript -Encoding UTF8
        }
        . $ompInitScript
    }
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
function global:New-DirectoryAndEnter {
    param([Parameter(Mandatory)][string]$Path)
    $null = New-Item -ItemType Directory -Path $Path -Force
    Set-Location $Path
}
# Define alias in Global scope so it persists after profile script finishes
Set-Alias mk New-DirectoryAndEnter -Scope Global

# --- File Operations ---
# List files (force)
function global:Get-ChildItemForce { Get-ChildItem -Force @args }
Set-Alias ll Get-ChildItemForce -Scope Global

# Create new file or update timestamp
function global:Update-FileTimestamp {
    param([Parameter(Mandatory)][string]$Path)
    if (Test-Path $Path) {
        (Get-Item $Path).LastWriteTime = Get-Date
    } else {
        $null = New-Item -ItemType File -Path $Path -Force
    }
}
Set-Alias touch Update-FileTimestamp -Scope Global

# Find file recursively
function global:Find-File {
    param([Parameter(Mandatory)][string]$Name)
    Get-ChildItem -Recurse -Filter "*$Name*" -ErrorAction SilentlyContinue
}
Set-Alias ff Find-File -Scope Global

# Extract zip file
function global:Expand-ArchiveFile {
    param([Parameter(Mandatory)][string]$Path, [string]$Destination = ".")
    Expand-Archive -Path $Path -DestinationPath $Destination -Force
}
Set-Alias unzip Expand-ArchiveFile -Scope Global

# --- System Utilities ---
# Refresh Path environment variable from registry
# Reloads PATH from the Registry (Machine and User scopes) so changes (like new installs) take effect immediately
# without restarting the PowerShell session.
function global:Update-EnvironmentPath {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
    Write-Host "Path environment variables reloaded." -ForegroundColor Green
}
Set-Alias Refresh-Path Update-EnvironmentPath -Scope Global

# Run as Administrator
function global:Invoke-ElevatedCommand {
    param([string]$Command, [Parameter(ValueFromRemainingArguments)][string[]]$Arguments)
    
    # Install gsudo (sudo for Windows) if not found
    if (-not (Get-Command gsudo -ErrorAction SilentlyContinue)) {
        Write-Host "gsudo not found. Installing..." -ForegroundColor Yellow
        winget install gerardog.gsudo -s winget --accept-source-agreements --accept-package-agreements
        Update-EnvironmentPath
    }

    $cmd = if ($Command) { Get-Command $Command -ErrorAction SilentlyContinue | Select-Object -First 1 } else { $null }
    $isPsCmd = $cmd -and $cmd.CommandType -ne 'Application'
    $hasGsudo = [bool](Get-Command gsudo -ErrorAction SilentlyContinue)

    if ($hasGsudo) {
        if (-not $Command) {
            gsudo
        } elseif ($isPsCmd) {
            # If it's a PowerShell function/alias, we need to invoke a new shell process to run it elevated.
            $shell = (Get-Process -Id $PID).Path
            $argList = ($Arguments | ForEach-Object { "`"$_`"" }) -join ' '
            gsudo $shell -NoExit -Command "& { $Command $argList }"
        } else {
            gsudo $Command $Arguments
        }
    } else {
        # Fallback to standard Windows 'RunAs' verb if gsudo is missing
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
Set-Alias sudo Invoke-ElevatedCommand -Scope Global

# Upgrade all software via winget
function global:Update-WingetPackages {
    Write-Host "--- Winget Upgrade ---" -ForegroundColor Cyan
    winget upgrade --all --include-unknown --accept-source-agreements --accept-package-agreements
    Update-EnvironmentPath
}
Set-Alias up Update-WingetPackages -Scope Global

# Kill process on port
function global:Stop-PortProcess {
    param([int]$Port)
    $tcp = Get-NetTCPConnection -LocalPort $Port -ErrorAction SilentlyContinue
    if ($tcp) {
        $proc = Get-Process -Id $tcp.OwningProcess -ErrorAction SilentlyContinue
        if ($proc) {
            Stop-Process -Id $tcp.OwningProcess -Force
            Write-Host "Killed process $($proc.ProcessName) (PID: $($tcp.OwningProcess)) on port $Port" -ForegroundColor Green
        } else {
            Write-Host "Found PID $($tcp.OwningProcess) on port $Port, but could not access process (try sudo)." -ForegroundColor Red
        }
    } else {
        Write-Host "No process found listening on port $Port" -ForegroundColor Yellow
    }
}
if (-not (Test-Path Alias:kill-port)) { Set-Alias kill-port Stop-PortProcess -Scope Global }

# Reboot the computer
function global:Invoke-RebootCountdown {
    Write-Host "Rebooting in 5 seconds... Press any key to cancel." -ForegroundColor Yellow
    for ($i = 5; $i -gt 0; $i--) {
        Write-Host -NoNewline "$i... "
        # Check for key press every 100ms to allow immediate cancellation without waiting for the full second
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
Set-Alias reboot Invoke-RebootCountdown -Scope Global

$Global:RebootMarkerPath = "$env:TEMP\ps_scheduled_reboot.xml"

function global:Get-PendingReboot {
    if (-not (Test-Path $Global:RebootMarkerPath)) { return $null }
    try {
        $rebootTime = Import-Clixml $Global:RebootMarkerPath
        $markerTime = [System.IO.File]::GetLastWriteTime($Global:RebootMarkerPath)
        $bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
        
        # If the system boot time is earlier than the marker file, the reboot hasn't happened yet.
        # If boot time is later, the reboot occurred, so we fall through to cleanup.
        if ($bootTime -lt $markerTime -and $rebootTime -gt (Get-Date)) {
            return $rebootTime
        }
    } catch {}
    # Cleanup marker if reboot happened or file is invalid
    Remove-Item $Global:RebootMarkerPath -Force -ErrorAction SilentlyContinue
    return $null
}

# Schedule a timed reboot
function global:Register-ScheduledReboot {
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
Set-Alias treboot Register-ScheduledReboot -Scope Global

# Abort scheduled reboot
function global:Unregister-ScheduledReboot {
    shutdown.exe /a
    if (Test-Path $Global:RebootMarkerPath) {
        Remove-Item $Global:RebootMarkerPath -Force
    }
    Write-Host "Scheduled reboot cancelled." -ForegroundColor Green
}
Set-Alias areboot Unregister-ScheduledReboot -Scope Global

# Lock the computer and turn off monitors
function global:Invoke-LockWorkstation {
    Write-Host "Locking in 5 seconds... Press any key to cancel." -ForegroundColor Yellow
    for ($i = 5; $i -gt 0; $i--) {
        Write-Host -NoNewline "$i... "
        # Check for key press every 100ms to allow immediate cancellation without waiting for the full second
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
    # Use P/Invoke to send a system command to turn off the monitor.
    # 0x0112 = WM_SYSCOMMAND, 0xF170 = SC_MONITORPOWER, 2 = Power Off
    if (-not ([System.Management.Automation.PSTypeName]'Win32Functions.Win32PowerControl').Type) {
        $null = Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern bool PostMessage(int hWnd, int hMsg, int wParam, int lParam);' -Name "Win32PowerControl" -Namespace Win32Functions
    }
    [void][Win32Functions.Win32PowerControl]::PostMessage(0xFFFF, 0x0112, 0xF170, 2)
}
if (-not (Test-Path Alias:l)) { Set-Alias l Invoke-LockWorkstation -Scope Global }
Set-Alias lock Invoke-LockWorkstation -Scope Global

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
if (-not (Test-Path Alias:grep)) { Set-Alias grep Select-String -Scope Global }
if (-not (Test-Path Alias:open)) { Set-Alias open Invoke-Item -Scope Global }

# Returns the file path of a command (like Unix 'which')
function global:Get-CommandSource ([string]$Name) {
    Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1
}
Set-Alias which Get-CommandSource -Scope Global

function global:Convert-Base64 {
    param([Parameter(ValueFromPipeline)][string]$String, [switch]$Decode)
    process {
        if ($Decode) {
            [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($String))
        } else {
            [System.Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($String))
        }
    }
}
Set-Alias base64 Convert-Base64 -Scope Global

function global:Get-VolumeInfo { Get-Volume }
Set-Alias df Get-VolumeInfo -Scope Global

# Calculates directory size by recursively summing file lengths (can be slow on large trees)
function global:Get-DirectorySize {
    param([string]$Path = ".")
    $size = (Get-ChildItem $Path -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    [PSCustomObject]@{ Path = (Resolve-Path $Path); Size = "{0:N2} MB" -f ($size / 1MB) }
}
Set-Alias du Get-DirectorySize -Scope Global

function global:Get-MemoryUsage {
    Get-CimInstance Win32_OperatingSystem | Select-Object @{N="Total(GB)";E={"{0:N2}" -f ($_.TotalVisibleMemorySize / 1MB)}}, @{N="Free(GB)";E={"{0:N2}" -f ($_.FreePhysicalMemory / 1MB)}}
}
Set-Alias free Get-MemoryUsage -Scope Global

function global:Get-SystemUptime {
    $boot = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $uptime = (Get-Date) - $boot
    $parts = @()
    if ($uptime.Days -gt 0) { $parts += "$($uptime.Days)d" }
    if ($uptime.Hours -gt 0) { $parts += "$($uptime.Hours)h" }
    if ($uptime.Minutes -gt 0) { $parts += "$($uptime.Minutes)m" }
    "Up for $(if ($parts) { $parts -join ' ' } else { "$($uptime.Seconds)s" })"
}
Set-Alias uptime Get-SystemUptime -Scope Global

function global:Get-NetworkSummary {
    [CmdletBinding()]
    param()

    # Determine if output is being piped by checking if this command is the last in the pipeline
    # This allows 'ip' to show colors in the console, but output clean text when piped (e.g., 'ip | clip')
    $isPiped = $MyInvocation.PipelinePosition -lt $MyInvocation.PipelineLength

    $interfaces = [System.Net.NetworkInformation.NetworkInterface]::GetAllNetworkInterfaces() |
        Where-Object { $_.NetworkInterfaceType -ne 'Loopback' -and $_.NetworkInterfaceType -ne 'Tunnel' } |
        Sort-Object { if ($_.OperationalStatus -eq 'Up') { 0 } else { 1 } }

    $seenMacs = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)

    # This will hold our structured output objects
    $outputObjects = @()

    foreach ($iface in $interfaces) {
        $macClean = $iface.GetPhysicalAddress().ToString()
        if (-not $macClean) { continue }

        $props = $iface.GetIPProperties()
        $unicastV4 = $props.UnicastAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetwork' }
        if ($iface.OperationalStatus -eq 'Up' -and -not $unicastV4) { continue }

        if ($seenMacs.Contains($macClean)) { continue }
        $null = $seenMacs.Add($macClean)

        $outputObjects += [PSCustomObject]@{ Type = 'Header'; Name = $iface.Name; Status = $iface.OperationalStatus }
        $outputObjects += [PSCustomObject]@{ Type = 'Driver'; Text = "  Driver:   $($iface.Description)" }

        $macDashed = $macClean -replace '(..)', '$1-' -replace '-$', ''
        $macColon = $macClean -replace '(..)', '$1:' -replace ':$', ''
        $outputObjects += [PSCustomObject]@{ Type = 'MAC'; Text = "  MAC:      $macDashed / $macColon / $macClean" }

        if ($iface.OperationalStatus -ne 'Up') {
            $outputObjects += [PSCustomObject]@{ Type = 'Info'; Text = "  IPv4:     Disconnected"; Color = 'Red' }
            $outputObjects += [PSCustomObject]@{ Type = 'Info'; Text = "  IPv6:     Disconnected"; Color = 'Red' }
            $outputObjects += [PSCustomObject]@{ Type = 'Info'; Text = "  DNS:      Disconnected"; Color = 'Red' }
        } else {
            $v4Str = foreach ($ip in $unicastV4) {
                $mask = $ip.IPv4Mask
                # Attempt reverse DNS lookup (PTR) to get hostname; use QuickTimeout to avoid UI lag
                $revDns = try { (Resolve-DnsName -Name $ip.Address.IPAddressToString -Type PTR -DnsOnly -QuickTimeout -ErrorAction SilentlyContinue).NameHost } catch {}
                $revDnsStr = if ($revDns -and $revDns -ne $ip.Address.IPAddressToString) { " [$($revDns.TrimEnd('.'))]" } else { "" }

                if ($mask) {
                    $cidr = ($mask.GetAddressBytes() | ForEach-Object { [Convert]::ToString($_, 2).Replace('0', '').Length } | Measure-Object -Sum).Sum
                    "$($ip.Address)/$cidr ($mask)$revDnsStr"
                } else {
                    "$($ip.Address)$revDnsStr"
                }
            }

            $resolve = { param($ipObject)
                         $ipAddress = if ($ipObject -is [System.Net.IPAddress]) { $ipObject } else { $ipObject.Address }
                         $ipString = $ipAddress.IPAddressToString
                         $revDns = try { (Resolve-DnsName -Name $ipString -Type PTR -DnsOnly -QuickTimeout -ErrorAction SilentlyContinue).NameHost } catch {}
                         $revDnsStr = if ($revDns -and $revDns -ne $ipString) { " [$($revDns.TrimEnd('.'))]" } else { "" }
                         "$ipString$revDnsStr" }

            $v6Str = ($props.UnicastAddresses | Where-Object { $_.Address.AddressFamily -eq 'InterNetworkV6' }) | ForEach-Object { & $resolve $_ }
            $gwStr = ($props.GatewayAddresses) | ForEach-Object { & $resolve $_ }
            $dnsStr = ($props.DnsAddresses) | ForEach-Object { & $resolve $_ }

            $dhcp = try { if ($props.GetIPv4Properties().IsDhcpEnabled) { "DHCP" } else { "Static" } } catch { "Unknown" }
            if ($v4Str) { $outputObjects += [PSCustomObject]@{ Type = 'Info'; Text = "  IPv4:     $($v4Str -join ', ') [$dhcp]"; Color = 'Cyan' } }
            if ($v6Str) { $outputObjects += [PSCustomObject]@{ Type = 'Info'; Text = "  IPv6:     $($v6Str -join ', ')"; Color = 'DarkCyan' } }
            if ($gwStr) { $outputObjects += [PSCustomObject]@{ Type = 'Info'; Text = "  Gateway:  $($gwStr -join ', ')"; Color = 'Yellow' } }
            if ($dnsStr) { $outputObjects += [PSCustomObject]@{ Type = 'Info'; Text = "  DNS:      $($dnsStr -join ', ')"; Color = 'Green' } }
        }
        $outputObjects += [PSCustomObject]@{ Type = 'Blank' }
    }

    # Remove trailing blank line
    if ($outputObjects.Count -gt 0 -and $outputObjects[-1].Type -eq 'Blank') { $outputObjects = $outputObjects | Select-Object -SkipLast 1 }

    # Now process the output objects
    if ($isPiped) {
        # Output plain text for piping
        foreach ($obj in $outputObjects) {
            switch ($obj.Type) {
                'Header' { "[$($obj.Name)] ($($obj.Status))" }
                'Blank'  { "" }
                default  { $obj.Text }
            }
        }
    } else {
        # Output colored text to the host
        foreach ($obj in $outputObjects) {
            switch ($obj.Type) {
                'Header' {
                    $statColor = if ($obj.Status -eq 'Up') { 'Green' } else { 'Red' }
                    Write-Host "[$($obj.Name)] " -NoNewline -ForegroundColor Magenta
                    Write-Host "($($obj.Status))" -ForegroundColor $statColor
                }
                'Driver' { Write-Host $obj.Text -ForegroundColor DarkGray }
                'MAC'    { Write-Host $obj.Text -ForegroundColor Gray }
                'Info'   { Write-Host $obj.Text -ForegroundColor $obj.Color }
                'Blank'  { Write-Host "" }
            }
        }
    }
}
Set-Alias ip Get-NetworkSummary -Scope Global

function global:Get-ContentHead {
    param([string[]]$Path, [int]$n = 10)
    if ($Path) { Get-Content $Path -TotalCount $n } else { $input | Select-Object -First $n }
}
Set-Alias head Get-ContentHead -Scope Global

function global:Get-ContentTail {
    param([string[]]$Path, [int]$n = 10)
    if ($Path) { Get-Content $Path -Tail $n } else { $input | Select-Object -Last $n }
}
Set-Alias tail Get-ContentTail -Scope Global

function global:Measure-Content {
    param([string[]]$Path)
    if ($Path) { Get-Content $Path | Measure-Object -Line -Word -Character } else { $input | Measure-Object -Line -Word -Character }
}
Set-Alias wc Measure-Content -Scope Global

# --- Developer Tools ---
function global:gst { git status -sb }
function global:gco {
    if ($args.Count -eq 0) {
        $branch = git branch --format='%(refname:short)' | Out-GridView -Title "Select Branch to Checkout" -PassThru
        if ($branch) { git checkout $branch }
    } else {
        git checkout $args
    }
}
function global:gcmsg { git commit -m $args }
function global:gpush {
    $branch = git symbolic-ref --short HEAD 2>$null
    $upstream = git rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>$null
    if ($branch -and -not $upstream) {
        git push --set-upstream origin $branch
    } else {
        git push $args
    }
}
function global:gpull { git pull $args }
function global:glog { git log --graph --abbrev-commit --decorate --format=format:'%C(bold blue)%h%C(reset) - %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(auto)%d%C(reset)' --all }
function global:gaa { git add --all }
function global:gcb { git checkout -b $args }
function global:gcom {
    if ($args) {
        git add --all
        git commit -m "$args"
    } else {
        Write-Host "--- Status ---" -ForegroundColor Cyan
        git status -sb
        git add --all
        $msg = Read-Host "Commit Message"
        if ($msg) { git commit -m $msg } else { Write-Warning "Commit cancelled." }
    }
}
function global:gd { git diff $args }
function global:gbr { git branch $args }
function global:gsta { git stash push $args }
function global:gstp { git stash pop $args }

# --- Terminal Configuration ---
# Set Windows Terminal Appearance
function global:Set-WTAppearance {
    param(
        [string]$FontName = "JetBrainsMonoNL Nerd Font",
        [double]$Opacity = 0.99,
        [bool]$UseAcrylic = $false,
        [bool]$UseAcrylicInTabRow = $true
    )
    $settingsPath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    
    if (-not (Test-Path $settingsPath)) { return }
    
    try {
        $jsonContent = Get-Content $settingsPath -Raw
        # Remove JS-style comments (//) because standard JSON parsers (and older PS versions) fail on them
        if ($PSVersionTable.PSVersion.Major -le 5) {
            $jsonContent = $jsonContent -replace '(?m)^\s*//.*$',''
        }
        $json = $jsonContent | ConvertFrom-Json
        if (-not $json.profiles.defaults) { $json.profiles | Add-Member -MemberType NoteProperty -Name "defaults" -Value ([PSCustomObject]@{}) }
        if (-not $json.profiles.defaults.font) { $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "font" -Value ([PSCustomObject]@{}) }
        
        # Check if update is needed
        $needUpdate = $false
        if ($json.profiles.defaults.font.face -ne $FontName) { $needUpdate = $true }
        if ($UseAcrylic) {
            if ($json.profiles.defaults.useAcrylic -ne $true) { $needUpdate = $true }
            if ($json.profiles.defaults.acrylicOpacity -ne $Opacity) { $needUpdate = $true }
        } else {
            if ($json.profiles.defaults.PSObject.Properties['useAcrylic']) { $needUpdate = $true }
            if ($json.profiles.defaults.PSObject.Properties['acrylicOpacity']) { $needUpdate = $true }
            $intOpacity = if ($Opacity -le 1.0) { [int]($Opacity * 100) } else { $Opacity }
            if ($json.profiles.defaults.opacity -ne $intOpacity) { $needUpdate = $true }
        }
        if ($json.useAcrylicInTabRow -ne $UseAcrylicInTabRow) { $needUpdate = $true }

        if (-not $needUpdate) { return }

        $json.profiles.defaults.font | Add-Member -MemberType NoteProperty -Name "face" -Value $FontName -Force
        if ($UseAcrylic) {
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "useAcrylic" -Value $true -Force
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "acrylicOpacity" -Value $Opacity -Force
        } else {
            if ($json.profiles.defaults.PSObject.Properties['useAcrylic']) { $json.profiles.defaults.PSObject.Properties.Remove('useAcrylic') }
            if ($json.profiles.defaults.PSObject.Properties['acrylicOpacity']) { $json.profiles.defaults.PSObject.Properties.Remove('acrylicOpacity') }
            $intOpacity = if ($Opacity -le 1.0) { [int]($Opacity * 100) } else { $Opacity }
            $json.profiles.defaults | Add-Member -MemberType NoteProperty -Name "opacity" -Value $intOpacity -Force
        }
        $json | Add-Member -MemberType NoteProperty -Name "useAcrylicInTabRow" -Value $UseAcrylicInTabRow -Force
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
if (-not (Test-Path Alias:pro)) { Set-Alias pro Edit-Profile -Scope Global }

# Reload profile
function global:Import-Profile {
    # Clear cached files to force re-evaluation of settings (Oh My Posh init, WT settings check)
    $filesToRemove = @(
        "$env:TEMP\omp_init.ps1",
        "$env:TEMP\wt_appearance.stamp",
        "$env:TEMP\vscode_font.stamp"
    )
    $filesToRemove | ForEach-Object { if (Test-Path $_) { Remove-Item $_ -Force -ErrorAction SilentlyContinue } }

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
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] Profiles reloaded and cache cleared." -ForegroundColor Green
}
if (-not (Test-Path Alias:reload)) { Set-Alias reload Import-Profile -Scope Global }

# Pull latest profile from GitHub
function global:Update-ProfileFromRemote {
    $url = "https://raw.githubusercontent.com/brycefors/PowerShell-Profile/main/Microsoft.PowerShell_profile.ps1"
    Write-Host "Downloading latest profile from GitHub..." -ForegroundColor Yellow
    try {
        $content = (Invoke-WebRequest $url -UseBasicParsing).Content
        Set-Content -Path $PROFILE -Value $content -Encoding UTF8 -Force
        Write-Host "Profile updated successfully." -ForegroundColor Green
        Import-Profile
    } catch {
        Write-Error "Failed to update profile: $_"
    }
}
Set-Alias pull-profile Update-ProfileFromRemote -Scope Global

# --- Completions ---
# Register winget autocomplete
# Invokes 'winget complete' to provide context-aware suggestions (packages, commands)
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
# Stamp files prevent reading/writing JSON settings on every startup
# We only run the heavy JSON logic if the stamp is missing or the settings file is newer than the stamp.
if ($env:WT_SESSION) {
    $wtStamp   = "$env:TEMP\wt_appearance.stamp"
    $wtSettings = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    if (-not (Test-Path $wtStamp) -or
        ((Test-Path $wtSettings) -and [System.IO.File]::GetLastWriteTime($wtSettings) -gt [System.IO.File]::GetLastWriteTime($wtStamp))) {
        Set-WTAppearance
        [System.IO.File]::WriteAllText($wtStamp, (Get-Date).ToString())
    }
}
if ($env:TERM_PROGRAM -eq 'vscode') {
    $vsStamp   = "$env:TEMP\vscode_font.stamp"
    $vsSettings = "$env:APPDATA\Code\User\settings.json"
    if (-not (Test-Path $vsStamp) -or
        ((Test-Path $vsSettings) -and [System.IO.File]::GetLastWriteTime($vsSettings) -gt [System.IO.File]::GetLastWriteTime($vsStamp))) {
        Set-VSCodeFont
        [System.IO.File]::WriteAllText($vsStamp, (Get-Date).ToString())
    }
}

# Check for scheduled reboot
$pendingReboot = Get-PendingReboot
if ($pendingReboot) {
    Write-Host "WARNING: System is scheduled to reboot at $($pendingReboot.ToString())" -ForegroundColor Red -BackgroundColor Black
    Write-Host "Run 'areboot' to cancel." -ForegroundColor Yellow
}
