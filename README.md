# LW TrustTunnel Client

**Язык:** Русский | [English](README_EN.md)

**LW TrustTunnel Client** — это Windows-приложение в системном трее для управления TrustTunnel Client и сохраненными профилями серверов.

Приложение не содержит готовых профилей серверов, сертификатов, логинов, паролей или активного файла конфигурации. Каждый пользователь добавляет свои настройки сервера самостоятельно.

## Быстрый старт для Windows

Для большинства пользователей Windows нужен готовый объединенный архив:

**[Скачать LWTT Client Bundle для Windows x86_64](dist/LWTT_Client_Bundle_windows_x86_64.zip)**

Прямая ссылка для скачивания:

```text
https://github.com/pvlrdnv/lwtt-client/raw/main/dist/LWTT_Client_Bundle_windows_x86_64.zip
```

Что сделать пользователю:

1. Скачать архив по ссылке выше.
2. Распаковать его в папку `C:\Trusttunnel`.
3. Запустить `lwtt_tray_start.bat`.
4. Получить в **тг-боте** настройки сервера и файл сертификата `.pem`, если он требуется.
5. В приложении выбрать **Добавить сервер**.
6. Вставить целиком сообщение из тг-бота с настройками сервера.
7. Выбрать файл сертификата, если бот прислал `.pem`.
8. Нажать **Сохранить и подключить**.

Краткая инструкция для пользователей: [docs/QUICK_START_RU.md](docs/QUICK_START_RU.md).

Если файла по ссылке еще нет, разработчик должен собрать его в VS Code WSL:

```bash
./build_bundle_wsl.sh
```

По умолчанию собирается вариант для большинства компьютеров:

```text
windows_x86_64
```

Подробнее о сборке: [docs/BUNDLE_WSL_RU.md](docs/BUNDLE_WSL_RU.md).

## Структура архива для пользователя

В корне папки установки остается только основной файл запуска:

```text
lwtt_tray_start.bat
```

Все технические файлы спрятаны во вложенной папке:

```text
lwtt_app\
```

Итоговая структура после распаковки:

```text
C:\Trusttunnel\lwtt_tray_start.bat
C:\Trusttunnel\lwtt_app\...
```

## Что находится в репозитории

- `app/` — файлы LW TrustTunnel Client в структуре для готового архива.
- `docs/QUICK_START_RU.md` — очень краткая инструкция для пользователей.
- `docs/INSTALL_RU.md` — подробная инструкция установки на русском языке.
- `docs/USAGE_RU.md` — инструкция по использованию.
- `docs/SERVER_PROFILES_RU.md` — описание профилей серверов и импорта настроек.
- `docs/TROUBLESHOOTING_RU.md` — диагностика и решение проблем.
- `docs/SECURITY_RU.md` — заметки по безопасности и приватности.
- `docs/BUNDLE_WSL_RU.md` — сборка готового bundle-архива в VS Code WSL.
- `dist/LWTT_Client_Manager_v4_16_public.zip` — публичный архив только с оболочкой LWTT, без профилей пользователей.
- `tools/build_bundle_wsl.sh` — WSL-сборщик готового архива для Windows x86_64.

## Что специально не включается в репозиторий

В целях безопасности в репозиторий и публичные ZIP-архивы не должны попадать:

- `profiles/`
- `profiles/certificates/`
- `profiles/backups/`
- `lwtt_client.toml`
- `*.pem`
- журналы и диагностические файлы
- настройки серверов
- логины и пароли

Готовый bundle-архив может содержать `trusttunnel_client.exe` и `wintun.dll`, потому что он предназначен для быстрого запуска обычными пользователями. Но локальные профили, сертификаты и конфигурации пользователей туда не включаются.

## Для разработчика

Сборка готового архива для пользователей Windows из VS Code WSL:

```bash
sudo apt update
sudo apt install -y curl unzip zip python3 ca-certificates
chmod +x build_bundle_wsl.sh tools/build_bundle_wsl.sh
./build_bundle_wsl.sh
```

После сборки основной файл для публикации:

```text
dist/LWTT_Client_Bundle_windows_x86_64.zip
```

Перед коммитом обязательно проверьте, что в Git не попали локальные данные:

```bash
find . \
  -path './.git' -prune -o \
  \( -path './profiles*' -o -path './log*' -o -name '*.pem' -o -name 'lwtt_client.toml' -o -name '*diagnostic*.txt' \) \
  -print
```

Если команда что-то вывела, эти файлы нельзя отправлять в GitHub.

## Лицензия

См. [LICENSE](LICENSE). На данный момент открытая лицензия для проекта не выбрана. Все права защищены владельцем репозитория.
