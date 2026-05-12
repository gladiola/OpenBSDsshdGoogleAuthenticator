# OpenBSD sshd + Google Authenticator (TOTP)

Fa'amaonia lua-vaega mo le OpenBSD SSH e fa'aaoga ai le Google Authenticator
(TOTP), fa'atasi ai ma le fa'asalalau o fa'amatalaga o taumafaiga le manuia i se
tufatufaga syslog mamao.

## Iloiloga Aoao

O lenei fale teuina e omai ai:

| Faila | Galuega |
|-------|---------|
| `setup.sh` | Fa'aoga otometi — tamomoe e tasi e fai o se root |
| `login_totp` | BSD Auth fa'amoemoega e fa'amaonia ai le code TOTP |
| `google-authenticator-setup.sh` | Fa'aoga lesitala mo tagata ta'ito'atasi |
| `sshd_config.snippet` | Su'esu'ega fa'aopoopo mo sshd_config |
| `syslog.conf.snippet` | Su'esu'ega fa'aopoopo mo syslog.conf mo le ave mamao |

### Saoasaoa o Fa'amaoniga

```
SSH client
  │
  ▼
sshd  ──── 1. Fa'amaonia i le ki faitino (ki pea o loo i ai)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Fesili: "Google Authenticator code: "
  ├── 3. E tuu atu e le tagata le TOTP numera 6 mai le app
  ├── 4. E fa'amaonia e oathtool le code i le ~/.google_authenticator
  │
  ├─ MANUIA → tatala le taimiga; auth.info fa'amaumauina i luma + ave mamao
  └─ FAALETONU → tapunia le taimiga; auth.warning fa'amaumauina i luma + ave mamao
```

## Manaoga

- OpenBSD 7.x (su'esu'eina i le 7.4 ma le 7.5)
- Avanoa root po o `doas`
- Fa'aputuga `oath-toolkit` (`pkg_add oath-toolkit`) — tu'uina mai ai `oathtool`
- Se tufatufaga syslog mamao e mafai ona maua mai le ao (rsyslog, syslog-ng, sns.)
- E tatau ona uma ona fa'apipi'i e tagata o latou SSH public key (`~/.ssh/authorized_keys`)

## Amata Vave (otometi)

```sh
doas sh setup.sh
```

O le fa'aoga:

1. Fa'apipi'i `oath-toolkit` e ala i `pkg_add`.
2. Kopi `login_totp` i `/usr/local/libexec/auth/login_totp`.
3. Fa'aopoopoina le vasega `totp` i `/etc/login.conf`.
4. Suia `/etc/ssh/sshd_config`.
5. Suia `/etc/syslog.conf` ma tulafono mo le ave mamao.
6. Toe amata `syslogd` ma `sshd`.
7. Fa'aoga faitalia `google-authenticator-setup.sh` e lesitala ai se tagata.

## Fa'apipi'i Lotoloto

### 1. Fa'apipi'i le oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Fa'apipi'i le BSD Auth lesona fa'aulu

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Fa'aopoopo le vasega `totp`

Fa'aopoopo le mea nei i `/etc/login.conf`:

```
# Vasega fa'aulu TOTP (Google Authenticator)
totp:\
    :auth=-totp:\
    :tc=default:
```

Ona toe fausia ai lea o le fa'amaumauga o login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Fa'atulagaina le sshd

Fa'aopoopo laina mai `sshd_config.snippet` i `/etc/ssh/sshd_config`.
O ta'iala e taua:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Fa'amaonia ma toe amata le sshd:

```sh
doas sshd -t          # fa'amaonia le fa'atulagaga
doas rcctl restart sshd
```

### 5. Fa'atulagaina le syslog mamao

Fa'aopoopo laina mai `syslog.conf.snippet` i `/etc/syslog.conf`, suia
`REMOTE_SYSLOG_SERVER` i le tuatusi moni o lau tufatufaga.

**UDP (fa'aletonu):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (e sili ona fa'atuatuaina):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Mo le TCP, fa'aola fo'i le TCP i `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Toe amata le syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Lesitala Tagata Faaaogaina

Fa'aoga le lesitala fa'aoga mo tagata ta'ito'atasi (e fai o root po o le tagata lava ia):

```sh
doas sh google-authenticator-setup.sh
```

O le fa'aoga:
1. E gaosia se TOTP faalilolilo 160-bit fa'avaivai.
2. Tusia i `~/.google_authenticator` (mode 0600).
3. Lolomi se URI `otpauth://` ma le QR code i le terminal (afai e fa'apipi'iina `qrencode`).
4. Tuuina le tagata i le vasega fa'aulu `totp`.

Su'e le QR code (po o fa'atete le URI) i le Google Authenticator, Aegis,
Authy, po o so'o se app TOTP-ogatasi.

### 7. Tu'uina Tagata i le vasega fa'aulu totp

Afai sa e le fa'aaogaina `google-authenticator-setup.sh`, tu'u lotoloto le vasega:

```sh
doas usermod -L totp alice
```

## Su'esu'e le Fa'atulagaga

### Su'e le oathtool i luma

```sh
# Gaosia le code TOTP o le taimi nei mo le faalilolilo a se tagata:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Fa'atusatusa ma le code o loo fa'aali i le app fa'amaonia — e tatau ona tutusa.

### Su'e le ave syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Siaki e mafai ona o'o atu nei o poloaiga i le tufatufaga syslog mamao.

### Su'e le ulufale SSH

Tatala se taimiga SSH **fou** (taofi lou taimiga o loo i ai tatala pe a mana'omia se
toe fa'aleleia):

```sh
ssh -v alice@your-server
```

Saoasaoa fa'ataunu'u:
1. E talia e le sshd lou ki faitino.
2. E vaai oe i le fesili: `Google Authenticator code: `
3. Ulufale le code numera 6 mai le app fa'amaonia.
4. Manuia pe le manuia le ulufale; o le taunuuga e foliga mai i `/var/log/authlog` ma
   i le tufatufaga syslog mamao.

## Fa'atulagaga o le Fa'amaumauga o Taumafaiga Le Manuia

Pe a teena e `login_totp` se code TOTP, e auina atu ai se fe'au e ala i `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

O lenei fe'au e tusia i:
- Le syslog i luma (`/var/log/authlog` i OpenBSD).
- Le tufatufaga syslog mamao e ala i le tulafono `auth.info` i `syslog.conf`.

E fa'amaumau fo'i e sshd lava ia isi fa'alavelave o fa'amaoniga le manuia:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Fa'amatalaga o Faila

### `login_totp` (BSD Auth fa'amoemoega)

- **Tulaga:** `/usr/local/libexec/auth/login_totp`
- **Faatagaga:** `root:auth 0550`
- **Faila faalilolilo:** `~/.google_authenticator` (laina muamua = TOTP faalilolilo base-32)
- **Fa'amaumau:** `logger -p auth.warning` i le faaletonu, `auth.info` i le manuia
- **Tolerane o le taimi:** ±1 × laasaga 30-sekone (e mafai ona fa'atulagaina i `TOTP_WINDOW`)

### `~/.google_authenticator`

O se faila tusitusi masani; o le **laina muamua** e tatau ona avea ma le TOTP faalilolilo base-32.
E le amanaia e `login_totp` isi laina (faamatalaga).

Fa'ata'ita'iga:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

E tatau ona `0600` le faatagaga, e umia e le tagata faaaogaina.

## Eseesega mai FreeBSD / Fa'atulagaga PAM

| Autu | FreeBSD | OpenBSD |
|------|---------|---------|
| Faavaa fa'amaonia | PAM (`pam_google_authenticator.so`) | BSD Auth (lesona `login_totp`) |
| Vasega ulufale | e leai | `/etc/login.conf` vasega `totp` |
| Fa'aputuga | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Tautua syslog | `syslogd` / `newsyslog` | `syslogd` (fa'apipi'iina) |
| Ave mamao UDP | `@host` i `syslog.conf` | `@host` i `syslog.conf` |
| Ave mamao TCP | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Toe Fo'ia Faafitauli

**«oathtool not found»**
Fa'apipi'i le oath-toolkit: `doas pkg_add oath-toolkit`

**«No secret file for user»**
Fa'aoga `google-authenticator-setup.sh` mo lena tagata, po o fausia lotoloto
`~/.google_authenticator` ma le faalilolilo base-32 i luga o le laina muamua.

**E fa'ato'a teena pea code TOTP uma**
Ia mautinoa le saoasaoa o le uati o le poloaiga (`ntpd` e fa'aola i OpenBSD e
le sa'o). O le eseesega o le uati e sili atu i le 30 sekone o le a maua ai le faaaogaina o
code uma. Fa'ateleina le `TOTP_WINDOW` i `login_totp` pe a manaomia.

**E fesili le SSH i le upu sili fa'aenoa le code TOTP**
Fa'amaonia o lo'o i ai `KbdInteractiveAuthentication yes` ma
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` i le `/etc/ssh/sshd_config`,
ma o lo'o i ai le tagata i le vasega fa'aulu `totp`
(`doas usermod -L totp <tagata>`).

**E faaletonu le sshd -t pe a uma ona suia le sshd_config**
Fa'aoga `doas sshd -t` ma foia so'o se sese ua lipotia a'o le'i toe amata sshd.
O le kopi sao na faia e `setup.sh` o lo'o i ai i
`/etc/ssh/sshd_config.bak.<taimi>`.

**E le mauaina e le syslog mamao ni fe'au**
1. Fa'amaonia o le port UDP/TCP 514 o le tufatufaga mamao e mafai ona maua:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Siaki tulafono o le ogaumu i itu uma e lua (OpenBSD pf ma le tufatufaga mamao).
3. Mo le ave TCP, fa'amaonia o lo'o i ai `syslogd_flags="-T"` i
   `/etc/rc.conf.local` ma ua toe amata `syslogd`.

## Laisene

Laisene BSD 2-Clause. Va'ai [LICENSE](LICENSE) mo fa'amatalaga atoa.
