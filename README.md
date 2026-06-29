# LW TrustTunnel Client

**LW TrustTunnel Client** is a Windows tray and server-profile manager for the TrustTunnel client.

The application does not include any ready-made server profiles, certificates, usernames, passwords, or active TrustTunnel configuration. Each user must add their own server settings in the manager.


## Быстрый старт для Windows

Для большинства пользователей Windows нужен готовый объединенный архив:

**[Скачать LWTT Client Bundle для Windows x86_64](dist/LWTT_Client_Bundle_windows_x86_64.zip)**

Что сделать пользователю:

1. Скачать архив по ссылке выше.
2. Распаковать его в папку `C:\Trusttunnel`.
3. Запустить `lwtt_tray_start.bat`.
4. Получить настройки сервера и файл сертификата `.pem` в LikeWeb Bot.
5. В приложении выбрать **Добавить сервер**, вставить сообщение с настройками и выбрать файл сертификата.
6. Нажать **Сохранить и подключить**.

Если файла по ссылке еще нет, разработчик должен собрать его в VS Code WSL:

```bash
./build_bundle_wsl.sh
```

По умолчанию собирается `windows_x86_64`. Подробнее: [docs/BUNDLE_WSL_RU.md](docs/BUNDLE_WSL_RU.md).

## What this repository contains

- `app/` — LW TrustTunnel Client scripts and tray icons.
- `docs/INSTALL_RU.md` — installation guide in Russian.
- `docs/USAGE_RU.md` — usage guide in Russian.
- `docs/SERVER_PROFILES_RU.md` — server profile format and import notes.
- `docs/TROUBLESHOOTING_RU.md` — troubleshooting guide.
- `docs/SECURITY_RU.md` — privacy and security notes.
- `dist/LWTT_Client_Manager_v4_15_public.zip` — ready-to-copy public package without user profiles.
- `tools/build_bundle_wsl.sh` — WSL builder for the ready-to-run Windows x86_64 bundle.

## Important

Install the original TrustTunnel Windows client first. LW TrustTunnel Client is a management wrapper and expects `trusttunnel_client.exe` and `wintun.dll` to be present in the same folder as the files from `app/`.

Recommended folder:

```text
C:\Trusttunnel
```

After installing TrustTunnel and copying LWTT files, start:

```text
lwtt_tray_start.bat
```

## Not included

For safety, the repository and public ZIP intentionally do **not** include:

- `profiles/`
- `profiles/certificates/`
- `profiles/backups/`
- `lwtt_client.toml`
- `*.pem`
- diagnostic logs
- server credentials

## License

No open-source license has been selected yet. Unless a license is added by the repository owner, all rights are reserved.
