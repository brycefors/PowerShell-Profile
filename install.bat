@echo off
setlocal EnableDelayedExpansion

set "PROFILE_URL=https://raw.githubusercontent.com/brycefors/PowerShell-Profile/main/Microsoft.PowerShell_profile.ps1"

echo Checking for PowerShell 7...
where pwsh.exe >nul 2>&1
if %ERRORLEVEL% EQU 0 goto :HavePwsh

echo PowerShell 7 not found.
where winget.exe >nul 2>&1
if %ERRORLEVEL% NEQ 0 goto :MsiInstall

echo Installing via winget...
winget install --id Microsoft.PowerShell --source winget --accept-source-agreements --accept-package-agreements
if %ERRORLEVEL% EQU 0 goto :RefreshPath
echo winget install failed. Falling back to direct MSI download...

:MsiInstall
rem Resolve the latest PowerShell 7 MSI for this architecture from the GitHub releases API and install it silently.
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
 "$ErrorActionPreference='Stop';" ^
 "[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;" ^
 "$arch = switch ($env:PROCESSOR_ARCHITECTURE) { 'AMD64' {'x64'} 'ARM64' {'arm64'} default {'x86'} };" ^
 "Write-Host \"Querying latest PowerShell release for win-$arch...\" -ForegroundColor Yellow;" ^
 "$rel = Invoke-RestMethod 'https://api.github.com/repos/PowerShell/PowerShell/releases/latest' -UseBasicParsing -Headers @{ 'User-Agent' = 'PowerShell-Profile-Installer' };" ^
 "$asset = $rel.assets | Where-Object { $_.name -like \"*win-$arch.msi\" } | Select-Object -First 1;" ^
 "if (-not $asset) { throw \"No MSI asset found for win-$arch\" };" ^
 "$msi = Join-Path $env:TEMP $asset.name;" ^
 "Write-Host \"Downloading $($asset.name)...\" -ForegroundColor Yellow;" ^
 "Invoke-WebRequest $asset.browser_download_url -OutFile $msi -UseBasicParsing;" ^
 "Write-Host 'Installing (this may prompt for elevation)...' -ForegroundColor Yellow;" ^
 "$p = Start-Process msiexec.exe -ArgumentList @('/i', \"`\"$msi`\"\", '/qn', '/norestart', 'ADD_PATH=1') -Verb RunAs -Wait -PassThru;" ^
 "Remove-Item $msi -Force -ErrorAction SilentlyContinue;" ^
 "if ($p.ExitCode -ne 0 -and $p.ExitCode -ne 3010) { throw \"msiexec exited with code $($p.ExitCode)\" }"

if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to install PowerShell 7. Install it manually from https://aka.ms/powershell
    exit /b 1
)

:RefreshPath
rem Refresh PATH from the registry so the freshly installed pwsh.exe is resolvable in this session.
for /f "usebackq tokens=2,*" %%A in (`reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v Path 2^>nul`) do set "MACHINE_PATH=%%B"
for /f "usebackq tokens=2,*" %%A in (`reg query "HKCU\Environment" /v Path 2^>nul`) do set "USER_PATH=%%B"
set "PATH=%MACHINE_PATH%;%USER_PATH%"

where pwsh.exe >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    if exist "%ProgramFiles%\PowerShell\7\pwsh.exe" (
        set "PATH=%ProgramFiles%\PowerShell\7;%PATH%"
    ) else (
        echo PowerShell 7 was installed but pwsh.exe could not be located. Close and reopen this window, then re-run this script.
        exit /b 1
    )
)

:HavePwsh
for /f "delims=" %%V in ('pwsh.exe -NoProfile -Command "$PSVersionTable.PSVersion.ToString()"') do set "PWSH_VERSION=%%V"
echo Using PowerShell !PWSH_VERSION!

echo Installing profile...
pwsh.exe -NoProfile -ExecutionPolicy Bypass -Command ^
 "$ErrorActionPreference='Stop';" ^
 "$content = (Invoke-WebRequest '%PROFILE_URL%' -UseBasicParsing).Content -replace \"`r`n\", \"`n\" -replace \"`n\", \"`r`n\";" ^
 "$ps7Dir = Split-Path -Parent $PROFILE.CurrentUserCurrentHost;" ^
 "$docs = Split-Path -Parent $ps7Dir;" ^
 "$targets = @((Join-Path $ps7Dir 'Microsoft.PowerShell_profile.ps1'), (Join-Path $ps7Dir 'Microsoft.VSCode_profile.ps1'));" ^
 "if (Get-Command powershell.exe -ErrorAction SilentlyContinue) {" ^
 "  $ps5Dir = Join-Path $docs 'WindowsPowerShell';" ^
 "  $targets += (Join-Path $ps5Dir 'Microsoft.PowerShell_profile.ps1'), (Join-Path $ps5Dir 'Microsoft.VSCode_profile.ps1') };" ^
 "$stamp = Get-Date -Format yyyyMMddHHmmss;" ^
 "$utf8Bom = New-Object System.Text.UTF8Encoding $true;" ^
 "foreach ($t in $targets) {" ^
 "  $dir = Split-Path -Parent $t;" ^
 "  if (-not (Test-Path $dir)) { $null = New-Item -ItemType Directory -Path $dir -Force };" ^
 "  if (Test-Path $t) { Copy-Item $t \"$t.bak_$stamp\" -Force; Write-Host \"  Backed up $t\" -ForegroundColor DarkGray };" ^
 "  [System.IO.File]::WriteAllText($t, $content, $utf8Bom);" ^
 "  Write-Host \"  Installed $t\" -ForegroundColor Green }"

if %ERRORLEVEL% NEQ 0 (
    echo ERROR: Failed to install the profile.
    exit /b 1
)

echo Done. Start a new pwsh, powershell, or VS Code terminal session to load the profile.
endlocal
