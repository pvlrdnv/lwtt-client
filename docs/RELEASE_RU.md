# Публичная сборка

Текущая публичная сборка:

```text
LWTT_Client_Manager_v4_15_public.zip
```

Она находится в папке:

```text
dist/
```

Архив содержит только файлы приложения и не содержит пользовательских данных.

## Состав приложения

```text
lwtt_tray_start.bat
lwtt_tray.ps1
lwtt_manager.ps1
lwtt_manager_start.bat
lwtt_common.ps1
lwtt_start.bat
lwtt_stop.bat
lwtt_runner.ps1
lwtt_test_worker.ps1
lwtt_autostart_install.bat
lwtt_autostart_remove.bat
icons8-start-96.ico
icons8-stop2-96.ico
icons8-waiting-96.ico
```

## Проверка перед публикацией

Перед публикацией убедитесь, что в архиве нет:

```text
profiles/
*.pem
*.toml
log/
*_diagnostic_*.txt
```
