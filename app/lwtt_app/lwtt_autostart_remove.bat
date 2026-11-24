@echo off
cd /d "%~dp0"

set "LWTT_SELF=%~f0"
powershell.exe -NoProfile -Command "$identity = [Security.Principal.WindowsIdentity]::GetCurrent(); $principal = New-Object Security.Principal.WindowsPrincipal($identity); if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 }; exit 1" >nul 2>&1
if %errorlevel% neq 0 (
    powershell.exe -NoProfile -Command "Start-Process -FilePath $env:LWTT_SELF -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
"Unregister-ScheduledTask -TaskName 'LW TrustTunnel Client Tray' -Confirm:$false -ErrorAction SilentlyContinue"

echo LW TrustTunnel Client tray autostart is disabled.
pause
