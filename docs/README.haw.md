# OpenBSD sshd + Google Authenticator (TOTP)

ʻElua-kumu hōʻoia no OpenBSD SSH me ka hoʻohana ʻana i Google Authenticator
(TOTP), me ka hoʻouna ʻana i nā leka hōʻike pale i kēlā me kēia syslog kikowaena.

## Nānā Nui

Hāʻawi kēia waihona:

| Faila | Kumu |
|-------|------|
| `setup.sh` | Palapala hoʻonohonoho aunoa — holo hoʻokahi manawa ma ke ʻano root |
| `login_totp` | BSD Auth hope e hōʻoia ana i ke code TOTP |
| `google-authenticator-setup.sh` | Palapala inoa no kēlā me kēia mea hoʻohana |
| `sshd_config.snippet` | Nā hua hoʻohui sshd_config kuhikuhi |
| `syslog.conf.snippet` | Nā hua hoʻohui syslog.conf no ka hoʻouna ʻana i kahi mamao |

### Ka Kaʻina Hōʻoia

```
SSH client
  │
  ▼
sshd  ──── 1. Public-key auth (existing key pair)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Prompt: "Google Authenticator code: "
  ├── 3. Ke komo nei ka mea hoʻohana i ke code TOTP nā helu 6 mai ka polokalamu
  ├── 4. oathtool e hōʻoia ana i ke code kūlike me ~/.google_authenticator
  │
  ├─ KŌKUA → wehe ʻia ka hālāwai; ua kākau ʻia auth.info ma kēia wahi + hoʻouna ʻia
  └─ HĀʻULE → pani ʻia ka hālāwai; ua kākau ʻia auth.warning ma kēia wahi + hoʻouna ʻia
```

## Nā Koi

- OpenBSD 7.x (hoʻāʻo ʻia ma 7.4 a me 7.5)
- Komo root a i ʻole `doas`
- Pūʻolo `oath-toolkit` (`pkg_add oath-toolkit`) — hāʻawi i `oathtool`
- He kikowaena syslog mamao e hiki ana ke loaʻa mai ka lolo (rsyslog, syslog-ng, a pēlā aku)
- Pono ka mea hoʻohana e loaʻa i kahi kī lehulehu SSH i hoʻokomo mua ʻia (`~/.ssh/authorized_keys`)

## Hoʻomaka Wikiwiki (Aunoa)

```sh
doas sh setup.sh
```

E hana ana ka palapala:

1. E hoʻokomo i `oath-toolkit` ma o `pkg_add`.
2. E kope i `login_totp` i `/usr/local/libexec/auth/login_totp`.
3. E hoʻohui i ke papa komo `totp` i `/etc/login.conf`.
4. E hoʻoponopono i `/etc/ssh/sshd_config`.
5. E hoʻoponopono i `/etc/syslog.conf` me nā lula hoʻouna mamao.
6. E hoʻomaka hou i `syslogd` a me `sshd`.
7. E holo hoihoi i `google-authenticator-setup.sh` no ka hoʻopaʻa inoa ʻana o ka mea hoʻohana.

## Hoʻokomo Lima

### 1. E Hoʻokomo i oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. E Hoʻokomo i ka Palapala Komo BSD Auth

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. E Hoʻohui i ke Papa Komo `totp`

E hoʻohui i ka mea ma lalo nei i `/etc/login.conf`:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

A laila e kūkulu hou i ka waihona kumu login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. E Hoʻonohonoho i sshd

E hoʻohui i nā laina mai `sshd_config.snippet` i `/etc/ssh/sshd_config`.
ʻO nā ʻōlelo kuhikuhi koʻikoʻi:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

E hōʻoia a e hoʻomaka hou i sshd:

```sh
doas sshd -t          # e hōʻoia i ka hoʻonohonoho
doas rcctl restart sshd
```

### 5. E Hoʻonohonoho i syslog Mamao

E hoʻohui i nā laina mai `syslog.conf.snippet` i `/etc/syslog.conf`, e hoʻololi i
`REMOTE_SYSLOG_SERVER` me kou helu kikowaena maoli.

**UDP (paʻamau):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (ʻoi aku ka hilinaʻi):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

No TCP, e hiki pū i TCP ma `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

E hoʻopau hou i syslogd:

```sh
doas rcctl restart syslogd
```

### 6. E Hoʻopaʻa Inoa i Nā Mea Hoʻohana

E holo i ka palapala hoʻopaʻa inoa no kēlā me kēia mea hoʻohana (ma ke ʻano root a i ʻole ʻo ia iho):

```sh
doas sh google-authenticator-setup.sh
```

Ka palapala:
1. E hana i kahi huna TOTP 160-bit alakoʻi.
2. E kākau iā ia i `~/.google_authenticator` (ʻano 0600).
3. E paʻi i kahi URI `otpauth://` a me kahi code QR ma ka terminal (inā ua hoʻokomo ʻia `qrencode`).
4. E hāʻawi i ka mea hoʻohana i ke papa komo `totp`.

E nānā i ke code QR (a i ʻole e pāʻili i ka URI) i Google Authenticator, Aegis,
Authy, a i ʻole kekahi polokalamu e kūpono ana me TOTP.

### 7. E Hāʻawi i Nā Mea Hoʻohana i ke Papa Komo totp

Inā ʻaʻole ʻoe i hoʻohana i `google-authenticator-setup.sh`, e hāʻawi i ke papa lima:

```sh
doas usermod -L totp alice
```

## Ka Hōʻoia ʻana i ka Hoʻonohonoho

### E Hoʻāʻo i oathtool ma Kēia Wahi

```sh
# E hana i ke code TOTP o kēia manawa no ka huna o kahi mea hoʻohana:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

E hoʻohālikelike i kēia me ke code i hōʻike ʻia ma ka polokalamu hōʻoia — pono lāua e like.

### E Hoʻāʻo i ka Hoʻouna ʻana o syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

E nānā inā hiki mai nā leka i ke kikowaena syslog mamao.

### E Hoʻāʻo i ka Komo SSH

E wehe i kahi hālāwai SSH **hou** (e mālama i kāu hālāwai mau e wehe ana inā
pono e hoʻoponopono i kekahi mea):

```sh
ssh -v alice@your-server
```

Ka kaʻina i manaʻo ʻia:
1. E ʻae ana sshd i kāu kī lehulehu.
2. E ʻike ana ʻoe i ka noi: `Google Authenticator code: `
3. E hoʻokomo i ke code nā helu 6 mai ka polokalamu hōʻoia.
4. Lanakila a i ʻole hāʻule ka komo; e ʻike ʻia ke hopena ma `/var/log/authlog` a
   ma ke kikowaena syslog mamao.

## Ka ʻAno o ka Leka Hōʻike Pale

Ke hōʻole ʻo `login_totp` i kahi code TOTP, e hoʻopuka ana ia i kahi leka ma o `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Ua kākau ʻia kēia leka i:
- Ka syslog kūloko (`/var/log/authlog` ma OpenBSD).
- Ke kikowaena syslog mamao ma o ka lula `auth.info` ma `syslog.conf`.

Ua kākau ʻia nā hanana hāʻule hōʻoia hou aku e sshd iā ia iho:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Kuhikuhi Faila

### `login_totp` (BSD Auth Hope)

- **Wahi:** `/usr/local/libexec/auth/login_totp`
- **Nā Kuleana:** `root:auth 0550`
- **Faila Huna:** `~/.google_authenticator` (laina mua = huna TOTP base-32)
- **Kākau Hōʻike:** `logger -p auth.warning` i ka hāʻule, `auth.info` i ka lanakila
- **Ahonui Manawa:** ±1 × kaʻina 30-kekona (hiki ke hoʻonohonoho ma o `TOTP_WINDOW`)

### `~/.google_authenticator`

He faila kikokikona maʻalahi; pono ʻo ka **laina mua** ka huna TOTP base-32.
Hoʻopalena ʻia nā laina hou aku (nā ʻōlelo) e `login_totp`.

Laʻana:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Pono nā kuleana ʻo `0600`, nona ka mea hoʻohana.

## Nā ʻOkoʻa mai FreeBSD / Nā Hoʻonohonoho PAM

| Kumuhana | FreeBSD | OpenBSD |
|----------|---------|---------|
| ʻOihana Hōʻoia | PAM (`pam_google_authenticator.so`) | BSD Auth (palapala `login_totp`) |
| Papa Komo | ʻaʻohe | Papa `totp` ma `/etc/login.conf` |
| Pūʻolo | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Deamon syslog | `syslogd` / `newsyslog` | `syslogd` (komo pū) |
| Hoʻouna UDP Mamao | `@host` ma `syslog.conf` | `@host` ma `syslog.conf` |
| Hoʻouna TCP Mamao | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Hoʻoponopono Pilikia

**"oathtool not found"**
E hoʻokomo i oath-toolkit: `doas pkg_add oath-toolkit`

**"No secret file for user"**
E holo i `google-authenticator-setup.sh` no kēlā mea hoʻohana, a i ʻole e hana lima i
`~/.google_authenticator` me ka huna base-32 ma ka laina mua.

**Ua hōʻole mau ʻia nā code TOTP**
E hōʻoia e like ana ka uaki o ka ʻōnaehana (`ntpd` hiki ma OpenBSD ma
ka paʻamau). E hopena ana kahi pio uaki nui aku i 30 kekona i ka hāʻule ʻana o nā code āpau.
E hoʻonui i `TOTP_WINDOW` ma `login_totp` inā pono.

**Ke noi nei SSH i kahi hua huna ma mua o ke code TOTP**
E hōʻoia ʻo `KbdInteractiveAuthentication yes` a me
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` ʻelua
i loaʻa ma `/etc/ssh/sshd_config`, a ʻo ka mea hoʻohana ma ke papa komo `totp`
(`doas usermod -L totp <user>`).

**Ua hāʻule sshd -t ma hope o ka hoʻoponopono i sshd_config**
E holo i `doas sshd -t` a e hoʻoponopono i nā hewa i hōʻike ʻia ma mua o ka hoʻomaka hou ʻana i sshd.
Aia ka kope mālama i hana ʻia e `setup.sh` ma
`/etc/ssh/sshd_config.bak.<timestamp>`.

**ʻAʻole loaʻa nā leka i ka syslog mamao**
1. E hōʻoia hiki ʻia ka puka UDP/TCP 514 o ke kikowaena mamao:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. E nānā i nā lula pā ahi ma nā ʻaoʻao ʻelua (OpenBSD pf a me ke kikowaena mamao).
3. No ka hoʻouna TCP, e hōʻoia ʻo `syslogd_flags="-T"` ma
   `/etc/rc.conf.local` a ua hoʻomaka hou ʻia `syslogd`.

## Laikini

Laikini BSD 2-Clause. E nānā i [LICENSE](LICENSE) no nā kikoʻī.
