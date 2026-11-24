@echo off
cd /d "%~dp0"
set "LWTT_RUNTIME=%~dp0"

set "LWTT_SELF=%~f0"
powershell.exe -NoProfile -Command "$identity = [Security.Principal.WindowsIdentity]::GetCurrent(); $principal = New-Object Security.Principal.WindowsPrincipal($identity); if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 }; exit 1" >nul 2>&1
if %errorlevel% neq 0 (
    powershell.exe -NoProfile -Command "Start-Process -FilePath $env:LWTT_SELF -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
"$scriptPath = Join-Path $env:LWTT_RUNTIME 'lwtt_tray.ps1';" ^
"$userId = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name;" ^
"$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument ('-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{0}""' -f $scriptPath);" ^
"$trigger = New-ScheduledTaskTrigger -AtLogOn -User $userId;" ^
"$principal = New-ScheduledTaskPrincipal -UserId $userId -LogonType Interactive -RunLevel Highest;" ^
"Register-ScheduledTask -TaskName 'LW TrustTunnel Client Tray' -Action $action -Trigger $trigger -Principal $principal -Force | Out-Null;" ^
"Start-ScheduledTask -TaskName 'LW TrustTunnel Client Tray'"

if errorlevel 1 (
    echo Failed to enable LW TrustTunnel Client tray autostart.
    pause
    exit /b 1
)

echo LW TrustTunnel Client tray autostart is enabled with elevated rights.
pause
