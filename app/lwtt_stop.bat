@echo off
cd /d "%~dp0"

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

set "PIDFILE=%~dp0log\client\trusttunnel_client.pid"
set "CLIENTPID="

if exist "%PIDFILE%" (
    set /p CLIENTPID=<"%PIDFILE%"
)

if defined CLIENTPID (
    taskkill /PID %CLIENTPID% /T /F >nul 2>&1
)

taskkill /IM trusttunnel_client.exe /F >nul 2>&1
del /f /q "%PIDFILE%" >nul 2>&1
exit /b
