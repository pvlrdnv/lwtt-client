@echo off
cd /d "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0lwtt_start.ps1"
set "LWTT_EXIT=%errorlevel%"
if not "%LWTT_EXIT%"=="0" pause
exit /b %LWTT_EXIT%
