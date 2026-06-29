# LW TrustTunnel Client

**Language:** [Русский](README.md) | English

**LW TrustTunnel Client** is a Windows tray application for managing the TrustTunnel Client and saved server profiles.

The application does not include ready-made server profiles, certificates, usernames, passwords, or an active configuration file. Each user adds their own server settings manually.

## Quick start for Windows

Most Windows users should use the ready-to-run combined archive:

**[Download LWTT Client Bundle for Windows x86_64](dist/LWTT_Client_Bundle_windows_x86_64.zip)**

User steps:

1. Download the archive from the link above.
2. Extract it to `C:\Trusttunnel`.
3. Run `lwtt_tray_start.bat`.
4. Get the server settings and `.pem` certificate file in the **Telegram bot**.
5. In the application, choose **Add server**.
6. Paste the server settings message.
7. Select the certificate file if the bot provided a `.pem` file.
8. Click **Save and connect**.

If the file linked above does not exist yet, the developer needs to build it in VS Code WSL:

```bash
./build_bundle_wsl.sh
```

The default build target is:

```text
windows_x86_64
```

See: [docs/BUNDLE_WSL_RU.md](docs/BUNDLE_WSL_RU.md).

## Repository contents

- `app/` — LW TrustTunnel Client scripts and tray icons.
- `docs/INSTALL_RU.md` — detailed Russian installation guide.
- `docs/USAGE_RU.md` — usage guide in Russian.
- `docs/SERVER_PROFILES_RU.md` — server profile format and import notes.
- `docs/TROUBLESHOOTING_RU.md` — troubleshooting guide.
- `docs/SECURITY_RU.md` — privacy and security notes.
- `docs/BUNDLE_WSL_RU.md` — instructions for building the ready-to-run bundle in VS Code WSL.
- `dist/LWTT_Client_Manager_v4_15_public.zip` — public package with the LWTT wrapper only, without user profiles.
- `tools/build_bundle_wsl.sh` — WSL builder for the ready-to-run Windows x86_64 archive.

## Important note

LW TrustTunnel Client is a management wrapper. To work, the following files must be located in the same folder as the application files:

```text
trusttunnel_client.exe
wintun.dll
```

The ready-to-run bundle archive includes these files automatically. If you use the LWTT-only package, install the official TrustTunnel Client for Windows first.

Recommended installation folder:

```text
C:\Trusttunnel
```

Start the application with:

```text
lwtt_tray_start.bat
```

## What is intentionally not included

For safety, the repository and public ZIP archives must not include:

- `profiles/`
- `profiles/certificates/`
- `profiles/backups/`
- `lwtt_client.toml`
- `*.pem`
- logs and diagnostic files
- server settings
- usernames and passwords

The ready-to-run bundle may include `trusttunnel_client.exe` and `wintun.dll` because it is intended for simple end-user installation. Local user profiles, certificates, and configurations are not included.

## For developers

Build the ready-to-run Windows archive from VS Code WSL:

```bash
sudo apt update
sudo apt install -y curl unzip zip python3 ca-certificates
chmod +x build_bundle_wsl.sh tools/build_bundle_wsl.sh
./build_bundle_wsl.sh
```

After the build, the main file to publish is:

```text
dist/LWTT_Client_Bundle_windows_x86_64.zip
```

Before committing, always check that local user data has not been added to Git:

```bash
find . \
  -path './.git' -prune -o \
  \( -path './profiles*' -o -path './log*' -o -name '*.pem' -o -name 'lwtt_client.toml' -o -name '*diagnostic*.txt' \) \
  -print
```

If the command prints anything, those files must not be pushed to GitHub.

## License

See [LICENSE](LICENSE). No open-source license has been selected for this project yet. All rights are reserved by the repository owner.
