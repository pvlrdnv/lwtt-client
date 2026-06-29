# Единый архив LW TrustTunnel Client + TrustTunnelClient

Для обычных пользователей удобнее выпускать единый архив, в котором уже есть TrustTunnelClient и LW TrustTunnel Client.

## Структура готового архива

В корне архива должен быть только основной пользовательский файл запуска:

```text
lwtt_tray_start.bat
```

Все технические файлы находятся во вложенной папке:

```text
lwtt_app/
```

Внутри `lwtt_app/` находятся:

- `trusttunnel_client.exe`;
- `wintun.dll`;
- PowerShell-скрипты LWTT;
- иконки;
- техническая краткая инструкция `README_QUICK_START_RU.txt`.

Пользователю остается только распаковать архив в `C:\Trusttunnel`, запустить `lwtt_tray_start.bat` и добавить сервер из данных, полученных в тг-боте.

## Прямая ссылка для пользователей

```text
https://github.com/pvlrdnv/lwtt-client/raw/main/dist/LWTT_Client_Bundle_windows_x86_64.zip
```

После нажатия на ссылку скачивание должно начаться сразу.

## Что не входит в единый архив

В архив намеренно не добавляются:

```text
lwtt_app/profiles/
lwtt_app/profiles/certificates/
lwtt_app/profiles/backups/
lwtt_app/log/
lwtt_app/lwtt_client.toml
*.pem
*diagnostic*.txt
*.pid
```

Профили серверов, пароли и сертификаты являются индивидуальными данными пользователя.

## Как собрать единый архив

Из корня репозитория запустите в WSL:

```bash
./build_bundle_wsl.sh
```

По умолчанию собирается `windows_x86_64`.

Итоговый файл для публикации:

```text
dist/LWTT_Client_Bundle_windows_x86_64.zip
```
