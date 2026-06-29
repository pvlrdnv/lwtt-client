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

net session >nul 2>&1
if %errorlevel% neq 0 (
    powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
    exit /b
)

start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "%LWTT_TRAY_SCRIPT%"
exit /b
