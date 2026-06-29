# LW TrustTunnel Client

**LW TrustTunnel Client** is a Windows tray and server-profile manager for the TrustTunnel client.

The application does not include any ready-made server profiles, certificates, usernames, passwords, or active TrustTunnel configuration. Each user must add their own server settings in the manager.

## What this repository contains

- `app/` — LW TrustTunnel Client scripts and tray icons.
- `docs/INSTALL_RU.md` — installation guide in Russian.
- `docs/USAGE_RU.md` — usage guide in Russian.
- `docs/SERVER_PROFILES_RU.md` — server profile format and import notes.
- `docs/TROUBLESHOOTING_RU.md` — troubleshooting guide.
- `docs/SECURITY_RU.md` — privacy and security notes.
- `dist/LWTT_Client_Manager_v4_15_public.zip` — ready-to-copy public package without user profiles.

## Important

Install the original TrustTunnel Windows client first. LW TrustTunnel Client is a management wrapper and expects `trusttunnel_client.exe` and `wintun.dll` to be present in the same folder.

See the full installation guide:

- [docs/INSTALL_RU.md](docs/INSTALL_RU.md)

## Quick installation overview

1. Download and unpack the official TrustTunnel Windows client for your Windows architecture.
2. Copy the files from `app/` into the same folder as `trusttunnel_client.exe` and `wintun.dll`.
3. Start the application with:

```bat
lwtt_tray_start.bat
```

4. Add your server profile in the server manager.

## Data and privacy

Server profiles are stored locally on the user machine. This repository intentionally excludes:

- saved server profiles;
- certificates;
- active configuration files;
- logs;
- diagnostic files;
- usernames and passwords.

See [PRIVACY.md](PRIVACY.md) and [docs/SECURITY_RU.md](docs/SECURITY_RU.md).

## Supported platform

- Windows 10 / Windows 11
- Windows PowerShell 5.1
- TrustTunnel client for Windows

## License

See [LICENSE](LICENSE).
