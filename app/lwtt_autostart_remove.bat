@echo off
cd /d "%~dp0"

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell.exe -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -Command ^
"Unregister-ScheduledTask -TaskName 'LW TrustTunnel Client Tray' -Confirm:$false -ErrorAction SilentlyContinue"

echo LW TrustTunnel Client tray autostart is disabled.
pause
