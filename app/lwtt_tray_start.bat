@echo off
setlocal
set "ROOT_DIR=%~dp0"
set "LWTT_APP_DIR=%ROOT_DIR%lwtt_app"
set "LWTT_TRAY_SCRIPT=%LWTT_APP_DIR%\lwtt_tray.ps1"

if not exist "%LWTT_TRAY_SCRIPT%" (
    echo Не найден файл приложения:
    echo %LWTT_TRAY_SCRIPT%
    echo.
    echo Проверьте, что архив распакован полностью.
    pause
    exit /b 1
)

set "LWTT_SELF=%~f0"
powershell.exe -NoProfile -Command "$identity = [Security.Principal.WindowsIdentity]::GetCurrent(); $principal = New-Object Security.Principal.WindowsPrincipal($identity); if ($principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) { exit 0 }; exit 1" >nul 2>&1
if %errorlevel% neq 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Process -FilePath $env:LWTT_SELF -Verb RunAs"
    exit /b
)

start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%LWTT_TRAY_SCRIPT%"
exit /b
