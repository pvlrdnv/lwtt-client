#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT/app"
RUNTIME_DIR="$APP_DIR/lwtt_app"
if [[ ! -d "$APP_DIR" ]]; then echo "app/ folder not found" >&2; exit 1; fi
mkdir -p "$RUNTIME_DIR"
for item in "$APP_DIR"/*; do
  name="$(basename "$item")"
  case "$name" in
    lwtt_tray_start.bat|lwtt_app) ;;
    *) mv "$item" "$RUNTIME_DIR/" ;;
  esac
done
cat > "$APP_DIR/lwtt_tray_start.bat" <<'BAT'
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
BAT
python3 - <<'PY_FIX'
from pathlib import Path
root = Path.cwd()
common = root/'app'/'lwtt_app'/'lwtt_common.ps1'
if common.exists():
    text = common.read_text(encoding='utf-8-sig')
    text = text.replace('$script:LikewebBaseDir = $PSScriptRoot\n$script:LikewebAppVersion = "4.15"', '$script:LikewebBaseDir = $PSScriptRoot\n$script:LikewebInstallRoot = Split-Path -Parent $script:LikewebBaseDir\nif ([string]::IsNullOrWhiteSpace($script:LikewebInstallRoot)) {\n    $script:LikewebInstallRoot = $script:LikewebBaseDir\n}\n$script:LikewebAppVersion = "4.16"')
    text = text.replace('$script:LikewebAppVersion = "4.15"', '$script:LikewebAppVersion = "4.16"')
    text = text.replace('$lines.Add(("Application folder: {0}" -f $script:LikewebBaseDir))', '$lines.Add(("Application folder: {0}" -f $script:LikewebBaseDir))\n    $lines.Add(("Install folder: {0}" -f $script:LikewebInstallRoot))')
    common.write_text('\ufeff'+text, encoding='utf-8')
tray = root/'app'/'lwtt_app'/'lwtt_tray.ps1'
if tray.exists():
    text = tray.read_text(encoding='utf-8-sig')
    text = text.replace('Start-Process "explorer.exe" -ArgumentList (\'"{0}"\' -f $script:LikewebBaseDir)', 'Start-Process "explorer.exe" -ArgumentList (\'"{0}"\' -f $script:LikewebInstallRoot)')
    tray.write_text('\ufeff'+text, encoding='utf-8')
version = root/'VERSION'
if version.exists(): version.write_text('4.16\n', encoding='utf-8')
PY_FIX
echo "Done. app/ now contains lwtt_tray_start.bat and lwtt_app/."
