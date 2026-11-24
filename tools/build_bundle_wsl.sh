#!/usr/bin/env bash
set -euo pipefail

# LW TrustTunnel Client bundle builder for VS Code WSL / Ubuntu.
# Default target: windows_x86_64.
# Bundle structure:
#   lwtt_tray_start.bat                    - user-facing launcher in the ZIP root
#   ИНСТРУКЦИЯ БЫСТРОГО СТАРТА.txt         - user-facing quick start guide in the ZIP root
#   lwtt_app/                              - technical files, TrustTunnel, profiles and logs

ARCH="${1:-x86_64}"
case "$ARCH" in
  x86_64|i686|aarch64) ;;
  windows_x86_64) ARCH="x86_64" ;;
  windows_i686) ARCH="i686" ;;
  windows_aarch64) ARCH="aarch64" ;;
  *)
    echo "Unsupported architecture: $ARCH" >&2
    echo "Allowed: x86_64, i686, aarch64" >&2
    exit 2
    ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
APP_DIR="$REPO_ROOT/app"
DIST_DIR="$REPO_ROOT/dist"
WORK_DIR="$REPO_ROOT/.bundle_work"
QUICK_START_SOURCE="$REPO_ROOT/docs/QUICK_START_BUNDLE_RU.txt"
QUICK_START_NAME="ИНСТРУКЦИЯ БЫСТРОГО СТАРТА.txt"

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    echo "Install dependencies in WSL with:" >&2
    echo "  sudo apt update && sudo apt install -y curl unzip zip python3 ca-certificates" >&2
    exit 1
  fi
}

need_cmd curl
need_cmd unzip
need_cmd python3

if [[ ! -d "$APP_DIR" ]]; then
  echo "Folder not found: $APP_DIR" >&2
  echo "Run this script from the repository that contains app/." >&2
  exit 1
fi

if [[ ! -f "$APP_DIR/lwtt_tray_start.bat" ]]; then
  echo "Missing user launcher: app/lwtt_tray_start.bat" >&2
  exit 1
fi

if [[ ! -d "$APP_DIR/lwtt_app" ]]; then
  echo "Missing runtime folder: app/lwtt_app" >&2
  exit 1
fi

if [[ ! -f "$QUICK_START_SOURCE" ]]; then
  echo "Missing quick start guide source: docs/QUICK_START_BUNDLE_RU.txt" >&2
  exit 1
fi

LWTT_VERSION="$(tr -d '\r\n ' < "$REPO_ROOT/VERSION" 2>/dev/null || true)"
if [[ -z "$LWTT_VERSION" ]]; then
  LWTT_VERSION="dev"
fi

mkdir -p "$WORK_DIR"
WORK_DIR="$(mktemp -d "$WORK_DIR/build.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT
mkdir -p "$WORK_DIR/download" "$WORK_DIR/extract" "$WORK_DIR/out" "$DIST_DIR"

RELEASE_JSON="$WORK_DIR/release.json"
LOCK_FILE="$SCRIPT_DIR/trusttunnel-release.json"
TT_VERSION="${2:-$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["version"])' "$LOCK_FILE")}"
EXPECTED_SHA="$(python3 - "$LOCK_FILE" "$TT_VERSION" "$ARCH" <<'PY_LOCK'
import json,sys
lock=json.load(open(sys.argv[1]))
if sys.argv[2] != lock['version']:
    raise SystemExit('Update tools/trusttunnel-release.json before changing the engine version')
print(lock['sha256'][sys.argv[3]])
PY_LOCK
)"
if [[ -n "${LWTT_TRUSTTUNNEL_ZIP:-}" ]]; then
  ASSET_NAME="trusttunnel_client-${TT_VERSION}-windows-${ARCH}.zip"
  TT_TAG="$TT_VERSION"
  ASSET_PATH="$WORK_DIR/download/$ASSET_NAME"
  cp "$LWTT_TRUSTTUNNEL_ZIP" "$ASSET_PATH"
else
  echo "Downloading TrustTunnelClient $TT_VERSION release metadata..."
curl -fsSL "https://api.github.com/repos/TrustTunnel/TrustTunnelClient/releases/tags/$TT_VERSION" -o "$RELEASE_JSON"

eval "$(python3 - "$RELEASE_JSON" "$ARCH" <<'PY_EVAL'
import json
import shlex
import sys
from pathlib import Path

release_path = Path(sys.argv[1])
arch = sys.argv[2]
release = json.loads(release_path.read_text(encoding='utf-8'))
tag = release.get('tag_name') or 'unknown'
needle = f"windows-{arch}".lower()
assets = release.get('assets') or []
match = None
for asset in assets:
    name = asset.get('name') or ''
    lower = name.lower()
    if lower.endswith('.zip') and needle in lower and 'source' not in lower:
        match = asset
        break
if match is None:
    print(f"echo {shlex.quote('Could not find TrustTunnelClient asset for ' + needle)} >&2")
    print("exit 1")
    raise SystemExit(0)
print(f"TT_TAG={shlex.quote(tag)}")
print(f"ASSET_NAME={shlex.quote(match['name'])}")
print(f"ASSET_URL={shlex.quote(match['browser_download_url'])}")
PY_EVAL
)"

[[ "$TT_TAG" == "$TT_VERSION" ]] || { echo "Unexpected release tag" >&2; exit 1; }
echo "TrustTunnelClient release: $TT_TAG"
echo "Selected asset: $ASSET_NAME"

ASSET_PATH="$WORK_DIR/download/$ASSET_NAME"
curl -fL "$ASSET_URL" -o "$ASSET_PATH"
fi
ACTUAL_SHA="$(sha256sum "$ASSET_PATH" | cut -d ' ' -f 1)"
if [[ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]]; then
  echo "TrustTunnel SHA256 mismatch; refusing to package." >&2
  exit 1
fi

unzip -q "$ASSET_PATH" -d "$WORK_DIR/extract"

CLIENT_EXE="$(find "$WORK_DIR/extract" -type f -iname 'trusttunnel_client.exe' | head -n 1 || true)"
if [[ -z "$CLIENT_EXE" ]]; then
  echo "trusttunnel_client.exe was not found in the TrustTunnel archive." >&2
  exit 1
fi
TRUST_DIR="$(dirname "$CLIENT_EXE")"

BUNDLE_DIR="$WORK_DIR/out"
RUNTIME_DIR="$BUNDLE_DIR/lwtt_app"
mkdir -p "$RUNTIME_DIR"

# Copy LWTT files first: root receives only user-facing files; runtime receives technical files.
cp "$APP_DIR/lwtt_tray_start.bat" "$BUNDLE_DIR/"
while IFS= read -r runtime_file; do
  runtime_file="${runtime_file%$'\r'}"
  [[ -z "$runtime_file" || "$runtime_file" == "VERSION" ]] && continue
  cp "$APP_DIR/lwtt_app/$runtime_file" "$RUNTIME_DIR/"
done < "$SCRIPT_DIR/runtime-files.txt"
for runtime_doc in README_LWTT_CLIENT.txt ИЗМЕНЕНИЯ_V4.15.txt; do
  [[ ! -f "$APP_DIR/lwtt_app/$runtime_doc" ]] || cp "$APP_DIR/lwtt_app/$runtime_doc" "$RUNTIME_DIR/"
done
cp "$REPO_ROOT/VERSION" "$RUNTIME_DIR/VERSION"

# Copy TrustTunnel files into technical runtime folder, not into ZIP root.
cp -a "$TRUST_DIR/." "$RUNTIME_DIR/"

# The quick start guide must be visible next to lwtt_tray_start.bat in the ZIP root.
# Remove obsolete copies from the technical folder and put the final guide in the root.
rm -f "$RUNTIME_DIR/README_QUICK_START_RU.txt" \
      "$RUNTIME_DIR/$QUICK_START_NAME" 2>/dev/null || true
cp "$QUICK_START_SOURCE" "$BUNDLE_DIR/$QUICK_START_NAME"

cat > "$RUNTIME_DIR/BUILD_INFO.txt" <<INFO
LW TrustTunnel Client version: $LWTT_VERSION
TrustTunnelClient release: $TT_TAG
TrustTunnelClient asset: $ASSET_NAME
Target: windows_$ARCH
Built at: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
Builder: tools/build_bundle_wsl.sh
INFO

# Safety cleanup: never include local user data in a public bundle.
rm -rf "$RUNTIME_DIR/profiles" \
       "$RUNTIME_DIR/log" \
       "$RUNTIME_DIR/settings" \
       "$RUNTIME_DIR/.bundle_work" \
       "$RUNTIME_DIR/profiles_backup" 2>/dev/null || true
find "$BUNDLE_DIR" -type f \( \
  -iname '*.tmp' -o \
  -iname '*.bak' -o \
  -iname '*.log' -o \
  -iname '*.pem' -o \
  -iname '*diagnostic*.txt' -o \
  -iname '*.pid' -o \
  -iname 'lwtt_client.toml' -o \
  -iname 'trusttunnel_client.likeweb.toml' \
\) -delete

if [[ ! -f "$BUNDLE_DIR/lwtt_tray_start.bat" || ! -f "$BUNDLE_DIR/$QUICK_START_NAME" || ! -f "$RUNTIME_DIR/trusttunnel_client.exe" || ! -f "$RUNTIME_DIR/wintun.dll" || ! -f "$RUNTIME_DIR/lwtt_tray.ps1" ]]; then
  echo "Bundle validation failed: required files are missing." >&2
  exit 1
fi

while IFS= read -r required; do
  required="${required%$'\r'}"
  [[ -z "$required" ]] && continue
  [[ -f "$RUNTIME_DIR/$required" ]] || { echo "Missing runtime file: $required" >&2; exit 1; }
done < "$SCRIPT_DIR/runtime-files.txt"

# Keep ZIP root clean: user-facing files stay in root; all technical files are in lwtt_app/.
for item in "$BUNDLE_DIR"/*; do
  name="$(basename "$item")"
  if [[ "$name" != "lwtt_tray_start.bat" && "$name" != "$QUICK_START_NAME" && "$name" != "lwtt_app" ]]; then
    echo "Unexpected item in ZIP root: $name" >&2
    exit 1
  fi
done

SAFE_TT_TAG="${TT_TAG//\//_}"
VERSIONED_NAME="LWTT_Client_Bundle_v${LWTT_VERSION}_trusttunnel_${SAFE_TT_TAG}_windows_${ARCH}.zip"
LATEST_NAME="LWTT_Client_Bundle_windows_${ARCH}.zip"
VERSIONED_ZIP="$DIST_DIR/$VERSIONED_NAME"
LATEST_ZIP="$DIST_DIR/$LATEST_NAME"

rm -f "$VERSIONED_ZIP" "$LATEST_ZIP" "$VERSIONED_ZIP.sha256" "$LATEST_ZIP.sha256"
# Python writes UTF-8 filename flags so Windows preserves the Russian guide name.
python3 - "$BUNDLE_DIR" "$VERSIONED_ZIP" <<'PY_ZIP'
from pathlib import Path
import sys, zipfile
source = Path(sys.argv[1])
with zipfile.ZipFile(sys.argv[2], 'w', zipfile.ZIP_DEFLATED) as archive:
    for file in sorted(source.rglob('*')):
        if file.is_file():
            archive.write(file, file.relative_to(source).as_posix())
PY_ZIP
cp "$VERSIONED_ZIP" "$LATEST_ZIP"

(
  cd "$DIST_DIR"
  sha256sum "$VERSIONED_NAME" > "$VERSIONED_NAME.sha256"
  sha256sum "$LATEST_NAME" > "$LATEST_NAME.sha256"
)

cat <<DONE

Done.

Created:
  dist/$VERSIONED_NAME
  dist/$LATEST_NAME
  dist/$VERSIONED_NAME.sha256
  dist/$LATEST_NAME.sha256

ZIP root structure:
  lwtt_tray_start.bat
  $QUICK_START_NAME
  lwtt_app/

Default public link for README:
  dist/$LATEST_NAME

Next steps:
  git add app tools/build_bundle_wsl.sh build_bundle_wsl.sh docs dist/$LATEST_NAME dist/$LATEST_NAME.sha256
  git commit -m "Build LWTT bundle v$LWTT_VERSION for windows_$ARCH"
  git push origin main
DONE
