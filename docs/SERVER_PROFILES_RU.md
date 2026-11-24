# Профили серверов

Публичная сборка LW TrustTunnel Client не содержит готовых профилей серверов.

## Где хранятся профили

Профили создаются локально у пользователя в папке:

```text
lwtt_app\profiles
```

Сертификаты профилей сохраняются в:

```text
lwtt_app\profiles\certificates
```

Резервные копии активной конфигурации сохраняются в:

```text
lwtt_app\profiles\backups
```

Эти папки не должны попадать в публичный GitHub-репозиторий.

## Формат сообщения администратора

Пользователь может добавить сервер, вставив сообщение администратора примерно такого вида:

```text
Название сервера (user123) – ручной ввод

Server name
server_internal_name

Address
example.org:443

Domain name from server certificate
example.org

Username
user123

Password
password123

Protocol
HTTP/2

Allow IPv6 connections via the server
Yes

Self-signed certificate
Custom certificate included – импортируйте файл .pem из следующего сообщения.
```

PEM-файл необязателен: по умолчанию используется системное доверие Windows. Для сервера с недоверенным сертификатом можно добавить PEM через свёрнутый раздел сертификата. Подробнее: [сертификаты](CERTIFICATES_RU.md).

## Что нельзя публиковать

Не публикуйте в репозитории:

```text
profiles/
*.pem
lwtt_client.toml
LW_TrustTunnel_Client_diagnostic_*.txt
```

Эти файлы могут содержать адреса серверов, учетные данные или диагностическую информацию конкретного пользователя.
