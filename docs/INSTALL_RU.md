# Установка LW TrustTunnel Client на Windows

Эта инструкция специально начинается с установки основного клиента TrustTunnel. LW TrustTunnel Client — это оболочка управления, а не замена `trusttunnel_client.exe`.

## 1. Сначала установите клиент TrustTunnel

Перед скачиванием проверьте тип системы Windows:

```text
Параметры → Система → О системе → Тип системы
```

Выберите архив TrustTunnel для Windows:

- `trusttunnel_client-v1.0.31-windows-x86_64.zip` — для большинства современных компьютеров с 64-разрядной Windows;
- `trusttunnel_client-v1.0.31-windows-i686.zip` — для 32-разрядной Windows;
- `trusttunnel_client-v1.0.31-windows-aarch64.zip` — для устройств на ARM-процессоре.

Для обычного современного ноутбука или ПК с Windows 10/11 чаще всего нужен вариант `x86_64`.

## 2. Создайте папку программы

Рекомендуемый путь:

```text
C:\Trusttunnel
```

Можно использовать и другой путь, например:

```text
C:\Portable	rusttunnel-manager
```

Важно: в корне выбранной папки должен лежать основной файл запуска `lwtt_tray_start.bat`. Все технические файлы приложения находятся во вложенной папке `lwtt_app`.

## 3. Распакуйте TrustTunnel

Если вы используете готовый bundle-архив, этот шаг уже выполнен внутри архива.

Если вы собираете папку вручную, распакуйте TrustTunnel во вложенную папку:

```text
C:\Trusttunnel\lwtt_app
```

После этого в папке `lwtt_app` должны быть как минимум:

```text
trusttunnel_client.exe
wintun.dll
```

Также могут быть дополнительные файлы TrustTunnel, например:

```text
setup_wizard.exe
LICENSE.txt
WINTUN_LICENSE.txt
```

## 4. Добавьте файлы LW TrustTunnel Client

Если вы используете готовый bundle-архив, просто распакуйте его в `C:\Trusttunnel`.

Если вы собираете папку вручную, скопируйте файлы из `app/` так, чтобы структура была такой:

```text
C:\Trusttunnel\lwtt_tray_start.bat
C:\Trusttunnel\lwtt_app\lwtt_tray.ps1
C:\Trusttunnel\lwtt_app\lwtt_manager.ps1
C:\Trusttunnel\lwtt_app\lwtt_common.ps1
C:\Trusttunnel\lwtt_app\lwtt_start.bat
C:\Trusttunnel\lwtt_app\lwtt_stop.bat
C:\Trusttunnel\lwtt_app\trusttunnel_client.exe
C:\Trusttunnel\lwtt_app\wintun.dll
```

В корне папки `C:\Trusttunnel` для пользователя должен быть только основной файл запуска:

```text
lwtt_tray_start.bat
```

## 5. Первый запуск

Запустите обычным двойным кликом:

```text
lwtt_tray_start.bat
```

Windows может запросить права администратора. Подтвердите запрос. Это нужно для работы сетевого туннеля и Wintun-адаптера.

## 6. Добавьте свой сервер

Профили серверов в публичную сборку не входят.

Откройте меню значка возле часов и выберите:

```text
Добавить сервер
```

Затем вставьте сообщение администратора с параметрами сервера и, если требуется, выберите файл сертификата `.pem`.

## 7. Автозапуск

Чтобы запускать клиент автоматически при входе в Windows, запустите:

```text
lwtt_autostart_install.bat
```

Чтобы удалить автозапуск:

```text
lwtt_autostart_remove.bat
```

## 8. Обновление

1. Закройте приложение через меню трея.
2. Скопируйте новые файлы LWTT поверх старых.
3. Не удаляйте папку `lwtt_app\profiles`, если хотите сохранить свои серверы.
4. Запустите `lwtt_tray_start.bat`.

## 9. Что не нужно переименовывать

Не переименовывайте:

```text
trusttunnel_client.exe
wintun.dll
```

Имена файлов LWTT также лучше не менять, потому что скрипты ссылаются друг на друга по этим именам.
