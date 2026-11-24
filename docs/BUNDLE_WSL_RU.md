# Сборка готового bundle-архива в VS Code WSL

Этот способ нужен разработчику проекта. Он позволяет прямо из Ubuntu/WSL собрать готовый архив для обычных пользователей Windows.

По умолчанию собирается вариант для большинства компьютеров:

```text
windows_x86_64
```

## 1. Откройте проект в VS Code WSL

В терминале WSL:

```bash
cd ~/projects/lwtt-client
code .
```

## 2. Установите зависимости WSL

Один раз выполните:

```bash
sudo apt update
sudo apt install -y curl unzip python3 ca-certificates
```

## 3. Соберите архив по умолчанию

Из корня проекта:

```bash
chmod +x build_bundle_wsl.sh tools/build_bundle_wsl.sh
./build_bundle_wsl.sh
```

Это то же самое, что:

```bash
./tools/build_bundle_wsl.sh x86_64
```

Скрипт скачает закреплённый в `tools/trusttunnel-release.json` релиз TrustTunnel, проверит SHA256, добавит файлы приложения и создаст ZIP в `dist`. В корне ZIP находятся `lwtt_tray_start.bat` и краткая инструкция; технические файлы находятся в `lwtt_app/`.

## 4. Результат сборки

В папке `dist` появятся файлы:

```text
LWTT_Client_Bundle_windows_x86_64.zip
LWTT_Client_Bundle_windows_x86_64.zip.sha256
LWTT_Client_Bundle_v4.20_trusttunnel_v..._windows_x86_64.zip
LWTT_Client_Bundle_v4.20_trusttunnel_v..._windows_x86_64.zip.sha256
```

Главная стабильная ссылка для README:

```text
dist/LWTT_Client_Bundle_windows_x86_64.zip
```

Именно этот файл можно показывать на главной странице проекта как быстрый скачиваемый архив для Windows.

## 5. Проверка перед GitHub

Перед коммитом убедитесь, что не попали пользовательские данные:

```bash
find . \
  -path './.git' -prune -o \
  \( -path './profiles*' -o -path './log*' -o -name '*.pem' -o -name 'lwtt_client.toml' -o -name '*diagnostic*.txt' \) \
  -print
```

Если команда что-то вывела, эти файлы нельзя отправлять в GitHub.

## 6. Отправка в GitHub

Минимальный набор для публикации стабильной ссылки:

```bash
git add README.md tools/build_bundle_wsl.sh build_bundle_wsl.sh docs/BUNDLE_WSL_RU.md \
  dist/LWTT_Client_Bundle_windows_x86_64.zip \
  dist/LWTT_Client_Bundle_windows_x86_64.zip.sha256

git commit -m "Build LWTT bundle v4.20 for windows_x86_64"
git push origin main
```

После этого на главной странице GitHub будет видна ссылка на актуальный готовый архив.

## 7. Другие архитектуры

При необходимости можно собрать другие варианты:

```bash
./tools/build_bundle_wsl.sh i686
./tools/build_bundle_wsl.sh aarch64
```

Но по умолчанию для обычных пользователей используется `x86_64`.

## Закреплённая версия и сборка без сети

Движок закреплён на v1.0.49 в `tools/trusttunnel-release.json`; SHA256 скачанного архива проверяется до распаковки. Для обновления движка отдельно обновите этот файл и проверьте совместимость.

```bash
LWTT_TRUSTTUNNEL_ZIP=/path/to/trusttunnel_client-v1.0.49-windows-x86_64.zip ./build_bundle_wsl.sh
```

Этот режим использует уже скачанный архив и также проверяет SHA256.
