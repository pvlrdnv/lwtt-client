# LW TrustTunnel Client

**Language:** [Русский](README.md) | English

**LW TrustTunnel Client** is a Windows tray application for managing the TrustTunnel Client and saved server profiles.

The application does not include ready-made server profiles, certificates, usernames, passwords, or an active configuration file. Each user adds their own server settings manually.

## Quick start for Windows

Most Windows users should use the ready-to-run combined archive:

**[Download LWTT Client Bundle for Windows x86_64](dist/LWTT_Client_Bundle_windows_x86_64.zip)**

Direct download link:

```text
https://github.com/pvlrdnv/lwtt-client/raw/main/dist/LWTT_Client_Bundle_windows_x86_64.zip
```

User steps:

1. Download the archive from the link above.
2. Extract it to `C:\Trusttunnel`.
3. Run `lwtt_tray_start.bat`.
4. Get the server settings and `.pem` certificate file in the Telegram bot, if required.
5. In the application, choose **Add server**.
6. Paste the full Telegram bot message with the server settings.
7. Select the certificate file if the bot provided a `.pem` file.
8. Click **Save and connect**.

## User-facing bundle structure

The installation folder root contains only the main launcher:

```text
lwtt_tray_start.bat
```

All technical files are hidden in the nested folder:

```text
lwtt_app\
```

## Repository contents

- `app/` — LW TrustTunnel Client files in bundle-ready structure.
- `docs/QUICK_START_RU.md` — short user guide in Russian.
- `docs/INSTALL_RU.md` — detailed Russian installation guide.
- `docs/USAGE_RU.md` — usage guide in Russian.
- `docs/SERVER_PROFILES_RU.md` — server profile format and import notes.
- `docs/TROUBLESHOOTING_RU.md` — troubleshooting guide.
- `docs/SECURITY_RU.md` — privacy and security notes.
- `docs/BUNDLE_WSL_RU.md` — instructions for building the ready-to-run bundle in VS Code WSL.
- `dist/LWTT_Client_Manager_v4_16_public.zip` — public package with the LWTT wrapper only, without user profiles.
- `tools/build_bundle_wsl.sh` — WSL builder for the ready-to-run Windows x86_64 archive.

## License

See [LICENSE](LICENSE). No open-source license has been selected for this project yet. All rights are reserved by the repository owner.
