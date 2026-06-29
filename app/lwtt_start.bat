@echo off
cd /d "%~dp0"

if not exist "trusttunnel_client.exe" exit /b 2
if not exist "lwtt_client.toml" exit /b 3
if not exist "wintun.dll" exit /b 4
if not exist "lwtt_runner.ps1" exit /b 5

start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%~dp0lwtt_runner.ps1"
exit /b
