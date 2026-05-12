# OpenBSD sshd + Google Authenticator (TOTP)

Двухфакторная аутентификация для SSH на OpenBSD с использованием Google Authenticator
(TOTP) и пересылкой журнала неудачных входов на удалённый syslog-сервер.

## Обзор

Данный репозиторий содержит:

| Файл | Назначение |
|------|-----------|
| `setup.sh` | Автоматизированный скрипт установки — запускается один раз от имени root |
| `login_totp` | Бэкенд BSD Auth для проверки кода TOTP |
| `google-authenticator-setup.sh` | Скрипт регистрации пользователей |
| `sshd_config.snippet` | Справочные дополнения к sshd_config |
| `syslog.conf.snippet` | Справочные дополнения к syslog.conf для удалённой пересылки |

### Процесс аутентификации

```
SSH client
  │
  ▼
sshd  ──── 1. Аутентификация по открытому ключу (существующая пара ключей)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Запрос: "Google Authenticator code: "
  ├── 3. Пользователь вводит 6-значный TOTP-код из приложения
  ├── 4. oathtool проверяет код по файлу ~/.google_authenticator
  │
  ├─ SUCCESS → сессия открыта; auth.info записан локально + переслан
  └─ FAILURE → сессия закрыта; auth.warning записан локально + переслан
```

## Требования

- OpenBSD 7.x (протестировано на 7.4 и 7.5)
- Доступ root или `doas`
- Пакет `oath-toolkit` (`pkg_add oath-toolkit`) — предоставляет `oathtool`
- Удалённый syslog-сервер, доступный с хоста (rsyslog, syslog-ng и т. п.)
- У пользователей должен быть установлен открытый SSH-ключ (`~/.ssh/authorized_keys`)

## Быстрый старт (автоматически)

```sh
doas sh setup.sh
```

Скрипт выполнит следующее:

1. Установит `oath-toolkit` через `pkg_add`.
2. Скопирует `login_totp` в `/usr/local/libexec/auth/login_totp`.
3. Добавит класс входа `totp` в `/etc/login.conf`.
4. Внесёт изменения в `/etc/ssh/sshd_config`.
5. Внесёт изменения в `/etc/syslog.conf` с правилами удалённой пересылки.
6. Перезапустит `syslogd` и `sshd`.
7. При необходимости запустит `google-authenticator-setup.sh` для регистрации пользователя.

## Ручная установка

### 1. Установка oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Установка скрипта BSD Auth login

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Добавление класса входа `totp`

Добавьте следующее в конец файла `/etc/login.conf`:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

Затем пересоберите базу данных login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Настройка sshd

Добавьте строки из `sshd_config.snippet` в `/etc/ssh/sshd_config`.
Ключевые директивы:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Проверьте и перезапустите sshd:

```sh
doas sshd -t          # проверка конфигурации
doas rcctl restart sshd
```

### 5. Настройка удалённого syslog

Добавьте строки из `syslog.conf.snippet` в `/etc/syslog.conf`, заменив
`REMOTE_SYSLOG_SERVER` на фактический адрес вашего сервера.

**UDP (по умолчанию):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (более надёжный вариант):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Для TCP также включите поддержку TCP в `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Перезагрузите syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Регистрация пользователей

Запустите скрипт регистрации для каждого пользователя (от имени root или самого пользователя):

```sh
doas sh google-authenticator-setup.sh
```

Скрипт выполнит следующее:
1. Сгенерирует случайный 160-битный TOTP-секрет.
2. Запишет его в `~/.google_authenticator` (режим 0600).
3. Выведет URI `otpauth://` и QR-код в терминале (если установлен `qrencode`).
4. Назначит пользователю класс входа `totp`.

Отсканируйте QR-код (или вставьте URI) в Google Authenticator, Aegis,
Authy или любое приложение, совместимое с TOTP.

### 7. Назначение пользователей классу входа totp

Если вы не использовали `google-authenticator-setup.sh`, назначьте класс вручную:

```sh
doas usermod -L totp alice
```

## Проверка установки

### Локальное тестирование oathtool

```sh
# Сгенерировать текущий TOTP-код для секрета пользователя:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Сравните этот код с кодом в приложении-аутентификаторе — они должны совпадать.

### Тестирование пересылки syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Убедитесь, что эти сообщения поступают на удалённый syslog-сервер.

### Тестирование входа по SSH

Откройте **новую** SSH-сессию (оставьте текущую сессию открытой на случай,
если потребуется что-то исправить):

```sh
ssh -v alice@your-server
```

Ожидаемый процесс:
1. sshd принимает ваш открытый ключ.
2. Появляется запрос: `Google Authenticator code: `
3. Введите 6-значный код из приложения-аутентификатора.
4. Вход выполнен успешно или отклонён; результат записывается в `/var/log/authlog` и
   на удалённый syslog-сервер.

## Формат записи о неудачном входе

Когда `login_totp` отклоняет TOTP-код, с помощью `logger(1)` выводится сообщение:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Это сообщение записывается в:
- Локальный syslog (`/var/log/authlog` на OpenBSD).
- Удалённый syslog-сервер по правилу `auth.info` в `syslog.conf`.

Дополнительные события неудачной аутентификации фиксируются самим sshd:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Справочник по файлам

### `login_totp` (бэкенд BSD Auth)

- **Расположение:** `/usr/local/libexec/auth/login_totp`
- **Права доступа:** `root:auth 0550`
- **Файл секрета:** `~/.google_authenticator` (первая строка — base-32 TOTP-секрет)
- **Журналирование:** `logger -p auth.warning` при ошибке, `auth.info` при успехе
- **Допуск по времени:** ±1 × 30-секундный шаг (настраивается через `TOTP_WINDOW`)

### `~/.google_authenticator`

Текстовый файл; **первая строка** должна содержать base-32 TOTP-секрет.
Дополнительные строки (комментарии) игнорируются `login_totp`.

Пример:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Права доступа должны быть `0600`, владелец — сам пользователь.

## Отличия от FreeBSD / установок на основе PAM

| Тема | FreeBSD | OpenBSD |
|------|---------|---------|
| Фреймворк аутентификации | PAM (`pam_google_authenticator.so`) | BSD Auth (скрипт `login_totp`) |
| Класс входа | н/д | Класс `totp` в `/etc/login.conf` |
| Пакет | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Демон syslog | `syslogd` / `newsyslog` | `syslogd` (встроенный) |
| Удалённая пересылка по UDP | `@host` в `syslog.conf` | `@host` в `syslog.conf` |
| Удалённая пересылка по TCP | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Устранение неполадок

**«oathtool not found»**
Установите oath-toolkit: `doas pkg_add oath-toolkit`

**«No secret file for user»**
Запустите `google-authenticator-setup.sh` для этого пользователя или вручную создайте
`~/.google_authenticator` с base-32 секретом в первой строке.

**TOTP-коды всегда отклоняются**
Убедитесь, что системные часы синхронизированы (`ntpd` включён в OpenBSD по
умолчанию). Расхождение часов более чем на 30 секунд приведёт к отклонению
каждого кода. При необходимости увеличьте `TOTP_WINDOW` в `login_totp`.

**SSH запрашивает пароль вместо TOTP-кода**
Убедитесь, что `KbdInteractiveAuthentication yes` и
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` оба
присутствуют в `/etc/ssh/sshd_config`, а пользователь входит в класс `totp`
(`doas usermod -L totp <user>`).

**sshd -t завершается с ошибкой после редактирования sshd_config**
Запустите `doas sshd -t` и исправьте все сообщённые ошибки перед перезапуском sshd.
Резервная копия, созданная `setup.sh`, находится по пути
`/etc/ssh/sshd_config.bak.<timestamp>`.

**Удалённый syslog не получает сообщений**
1. Убедитесь, что UDP/TCP-порт 514 удалённого сервера доступен:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Проверьте правила брандмауэра на обоих концах (OpenBSD pf и удалённый сервер).
3. Для пересылки по TCP убедитесь, что `syslogd_flags="-T"` указан в
   `/etc/rc.conf.local` и `syslogd` перезапущен.

## Лицензия

BSD 2-Clause License. Подробности см. в файле [LICENSE](../LICENSE).
