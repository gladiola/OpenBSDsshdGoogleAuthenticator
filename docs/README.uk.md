# OpenBSD sshd + Google Authenticator (TOTP)

Двофакторна автентифікація для SSH на OpenBSD за допомогою Google Authenticator
(TOTP) з пересиланням журналу невдалих спроб входу на віддалений syslog-сервер.

## Огляд

Цей репозиторій містить:

| Файл | Призначення |
|------|------------|
| `setup.sh` | Автоматизований скрипт встановлення — запускається один раз від імені root |
| `login_totp` | Бекенд BSD Auth для перевірки коду TOTP |
| `google-authenticator-setup.sh` | Скрипт реєстрації користувачів |
| `sshd_config.snippet` | Довідкові доповнення до sshd_config |
| `syslog.conf.snippet` | Довідкові доповнення до syslog.conf для віддаленого пересилання |

### Процес автентифікації

```
SSH client
  │
  ▼
sshd  ──── 1. Автентифікація за відкритим ключем (наявна пара ключів)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Запит: "Google Authenticator code: "
  ├── 3. Користувач вводить 6-значний TOTP-код з додатку
  ├── 4. oathtool перевіряє код за файлом ~/.google_authenticator
  │
  ├─ SUCCESS → сесію відкрито; auth.info записано локально + переслано
  └─ FAILURE → сесію закрито; auth.warning записано локально + переслано
```

## Вимоги

- OpenBSD 7.x (протестовано на 7.4 і 7.5)
- Доступ root або `doas`
- Пакет `oath-toolkit` (`pkg_add oath-toolkit`) — надає `oathtool`
- Віддалений syslog-сервер, доступний з хоста (rsyslog, syslog-ng тощо)
- Користувачі повинні мати встановлений відкритий SSH-ключ (`~/.ssh/authorized_keys`)

## Швидкий старт (автоматично)

```sh
doas sh setup.sh
```

Скрипт виконає наступне:

1. Встановить `oath-toolkit` через `pkg_add`.
2. Скопіює `login_totp` до `/usr/local/libexec/auth/login_totp`.
3. Додасть клас входу `totp` до `/etc/login.conf`.
4. Внесе зміни до `/etc/ssh/sshd_config`.
5. Внесе зміни до `/etc/syslog.conf` з правилами віддаленого пересилання.
6. Перезапустить `syslogd` та `sshd`.
7. За потреби запустить `google-authenticator-setup.sh` для реєстрації користувача.

## Ручне встановлення

### 1. Встановлення oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Встановлення скрипта BSD Auth login

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Додавання класу входу `totp`

Додайте наступне в кінець файлу `/etc/login.conf`:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

Потім перебудуйте базу даних login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Налаштування sshd

Додайте рядки з `sshd_config.snippet` до `/etc/ssh/sshd_config`.
Ключові директиви:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Перевірте та перезапустіть sshd:

```sh
doas sshd -t          # перевірка конфігурації
doas rcctl restart sshd
```

### 5. Налаштування віддаленого syslog

Додайте рядки з `syslog.conf.snippet` до `/etc/syslog.conf`, замінивши
`REMOTE_SYSLOG_SERVER` на фактичну адресу вашого сервера.

**UDP (за замовчуванням):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (більш надійний варіант):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Для TCP також увімкніть підтримку TCP у `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Перезавантажте syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Реєстрація користувачів

Запустіть скрипт реєстрації для кожного користувача (від імені root або самого користувача):

```sh
doas sh google-authenticator-setup.sh
```

Скрипт виконає наступне:
1. Згенерує випадковий 160-бітний TOTP-секрет.
2. Запише його до `~/.google_authenticator` (режим 0600).
3. Виведе URI `otpauth://` і QR-код у терміналі (якщо встановлено `qrencode`).
4. Призначить користувачу клас входу `totp`.

Відскануйте QR-код (або вставте URI) у Google Authenticator, Aegis,
Authy або будь-який TOTP-сумісний додаток.

### 7. Призначення користувачів класу входу totp

Якщо ви не використовували `google-authenticator-setup.sh`, призначте клас вручну:

```sh
doas usermod -L totp alice
```

## Перевірка встановлення

### Локальне тестування oathtool

```sh
# Згенерувати поточний TOTP-код для секрету користувача:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Порівняйте цей код з кодом у додатку-автентифікаторі — вони повинні збігатися.

### Тестування пересилання syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Переконайтеся, що ці повідомлення надходять на віддалений syslog-сервер.

### Тестування входу по SSH

Відкрийте **нову** SSH-сесію (залиште поточну сесію відкритою на випадок,
якщо потрібно буде щось виправити):

```sh
ssh -v alice@your-server
```

Очікуваний процес:
1. sshd приймає ваш відкритий ключ.
2. З'являється запит: `Google Authenticator code: `
3. Введіть 6-значний код з додатку-автентифікатора.
4. Вхід виконано успішно або відхилено; результат записується до `/var/log/authlog` і
   на віддалений syslog-сервер.

## Формат запису про невдалий вхід

Коли `login_totp` відхиляє TOTP-код, за допомогою `logger(1)` виводиться повідомлення:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Це повідомлення записується до:
- Локального syslog (`/var/log/authlog` на OpenBSD).
- Віддаленого syslog-сервера за правилом `auth.info` у `syslog.conf`.

Додаткові події невдалої автентифікації фіксуються самим sshd:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Довідник по файлах

### `login_totp` (бекенд BSD Auth)

- **Розташування:** `/usr/local/libexec/auth/login_totp`
- **Права доступу:** `root:auth 0550`
- **Файл секрету:** `~/.google_authenticator` (перший рядок — base-32 TOTP-секрет)
- **Журналювання:** `logger -p auth.warning` при помилці, `auth.info` при успіху
- **Допуск за часом:** ±1 × 30-секундний крок (налаштовується через `TOTP_WINDOW`)

### `~/.google_authenticator`

Текстовий файл; **перший рядок** повинен містити base-32 TOTP-секрет.
Додаткові рядки (коментарі) ігноруються `login_totp`.

Приклад:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Права доступу повинні бути `0600`, власник — сам користувач.

## Відмінності від FreeBSD / налаштувань на основі PAM

| Тема | FreeBSD | OpenBSD |
|------|---------|---------|
| Фреймворк автентифікації | PAM (`pam_google_authenticator.so`) | BSD Auth (скрипт `login_totp`) |
| Клас входу | н/д | Клас `totp` у `/etc/login.conf` |
| Пакет | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Демон syslog | `syslogd` / `newsyslog` | `syslogd` (вбудований) |
| Віддалене пересилання по UDP | `@host` у `syslog.conf` | `@host` у `syslog.conf` |
| Віддалене пересилання по TCP | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Усунення неполадок

**«oathtool not found»**
Встановіть oath-toolkit: `doas pkg_add oath-toolkit`

**«No secret file for user»**
Запустіть `google-authenticator-setup.sh` для цього користувача або вручну створіть
`~/.google_authenticator` з base-32 секретом у першому рядку.

**TOTP-коди завжди відхиляються**
Переконайтеся, що системний годинник синхронізовано (`ntpd` увімкнено в OpenBSD за
замовчуванням). Розбіжність годинника більше ніж на 30 секунд призведе до відхилення
кожного коду. За потреби збільшіть `TOTP_WINDOW` у `login_totp`.

**SSH запитує пароль замість TOTP-коду**
Переконайтеся, що `KbdInteractiveAuthentication yes` і
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` обидва
присутні у `/etc/ssh/sshd_config`, а користувач входить до класу `totp`
(`doas usermod -L totp <user>`).

**sshd -t завершується з помилкою після редагування sshd_config**
Запустіть `doas sshd -t` і виправте всі зазначені помилки перед перезапуском sshd.
Резервна копія, створена `setup.sh`, знаходиться за шляхом
`/etc/ssh/sshd_config.bak.<timestamp>`.

**Віддалений syslog не отримує повідомлень**
1. Переконайтеся, що UDP/TCP-порт 514 віддаленого сервера доступний:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Перевірте правила брандмауера на обох кінцях (OpenBSD pf та віддалений сервер).
3. Для пересилання по TCP переконайтеся, що `syslogd_flags="-T"` вказано у
   `/etc/rc.conf.local` та `syslogd` перезапущено.

## Ліцензія

BSD 2-Clause License. Докладніше див. у файлі [LICENSE](../LICENSE).
