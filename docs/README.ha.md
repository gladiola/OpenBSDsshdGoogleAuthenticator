# OpenBSD sshd + Google Authenticator (TOTP)

Tantancewar sinaɗara biyu don OpenBSD SSH ta amfani da Google Authenticator
(TOTP), tare da tura rajistar shiga da ta kasa zuwa ga uwar garken syslog nesa.

## Bayanin Gaba Ɗaya

Wannan adanin yana ba da:

| Fayil | Manufa |
|------|---------|
| `setup.sh` | Rubutun shiryawa ta atomatik — gudu sau ɗaya a matsayin root |
| `login_totp` | Bayan BSD Auth wanda yake tabbatar da lambar TOTP |
| `google-authenticator-setup.sh` | Rubutun yin rajista na kowane mai amfani |
| `sshd_config.snippet` | Ƙarin sshd_config na tunani |
| `syslog.conf.snippet` | Ƙarin syslog.conf na tunani don turawa nesa |

### Tsarin Tantancewa

```
SSH client
  │
  ▼
sshd  ──── 1. Tantancewar makulli na jama'a (ma'aurin makulli da ke akwai)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Tambaya: "Google Authenticator code: "
  ├── 3. Mai amfani ya shigar da lambar TOTP mai lamba 6 daga app
  ├── 4. oathtool yana tabbatar da lambar a kan ~/.google_authenticator
  │
  ├─ NASARA → zaman ya buɗe; auth.info an rubuta a gida + an tura
  └─ KASA → zaman ya rufe; auth.warning an rubuta a gida + an tura
```

## Buƙatu

- OpenBSD 7.x (an gwada akan 7.4 da 7.5)
- Damar root ko `doas`
- Kunshin `oath-toolkit` (`pkg_add oath-toolkit`) — yana ba da `oathtool`
- Uwar garken syslog nesa da za a iya kaiwa daga mai masaukin (rsyslog, syslog-ng, da sauransu)
- Masu amfani dole su sami makullin SSH na jama'a da aka shigar a baya (`~/.ssh/authorized_keys`)

## Farawa Mai Sauri (Atomatik)

```sh
doas sh setup.sh
```

Rubutun zai:

1. Shigar `oath-toolkit` ta `pkg_add`.
2. Kwafar `login_totp` zuwa `/usr/local/libexec/auth/login_totp`.
3. Ƙara ajin shiga `totp` zuwa `/etc/login.conf`.
4. Gyara `/etc/ssh/sshd_config`.
5. Gyara `/etc/syslog.conf` da ƙa'idodin turawa nesa.
6. Sake farawa `syslogd` da `sshd`.
7. Zai iya gudu `google-authenticator-setup.sh` don yi wa mai amfani rajista.

## Shigarwa ta Hannu

### 1. Shigar da oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Shigar da Rubutun Shiga BSD Auth

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Ƙara Aji Shiga `totp`

Ƙara mai zuwa zuwa `/etc/login.conf`:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

Sannan sake gina cikakken bayani na login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Saita sshd

Ƙara layi daga `sshd_config.snippet` zuwa `/etc/ssh/sshd_config`.
Umarnin mahimmanci sune:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Tabbatar da sake farawa sshd:

```sh
doas sshd -t          # tabbatar da saiti
doas rcctl restart sshd
```

### 5. Saita Syslog nesa

Ƙara layi daga `syslog.conf.snippet` zuwa `/etc/syslog.conf`, maye gurbin
`REMOTE_SYSLOG_SERVER` da adireshin uwar garken da ke aiki.

**UDP (tsoho):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (mafi aminci):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Don TCP, kuma kunna TCP a `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Sake loda syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Yi wa Masu Amfani Rajista

Gudu rubutun rajista na kowane mai amfani (a matsayin root ko mai amfani da kansa):

```sh
doas sh google-authenticator-setup.sh
```

Rubutun yana:
1. Ƙirƙirar sirrin TOTP na 160-bit ta bazuwar.
2. Rubuta shi zuwa `~/.google_authenticator` (yanayi 0600).
3. Buga URI `otpauth://` da lambar QR na terminal (idan `qrencode` ya shigar).
4. Sanya mai amfani zuwa aji shiga `totp`.

Duba lambar QR (ko manna URI) cikin Google Authenticator, Aegis,
Authy, ko kowane app mai dacewa da TOTP.

### 7. Sanya Masu Amfani zuwa Aji Shiga totp

Idan ba ka yi amfani da `google-authenticator-setup.sh` ba, sanya ajin da hannu:

```sh
doas usermod -L totp alice
```

## Tabbatar da Shiryawa

### Gwada oathtool a Gida

```sh
# Ƙirƙiro lambar TOTP ta yanzu don asirin mai amfani:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Kwatanta wannan da lambar da ke bayyana a cikin app na tantancewa — ya kamata su dace.

### Gwada Turawa ta syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Duba cewa waɗannan saƙonni sun isa uwar garken syslog nesa.

### Gwada Shiga SSH

Buɗe zaman SSH **sabon** (kiyaye zaman da ke akwai a buɗe idan
wani abu yana buƙatar gyarawa):

```sh
ssh -v alice@your-server
```

Tsarin da ake tsammani:
1. sshd ya karɓi makullin jama'arka.
2. Ka ga tambayar: `Google Authenticator code: `
3. Shigar da lambar mai lamba 6 daga app na tantancewa.
4. Shiga ta yi nasara ko ta kasa; sakamakon yana bayyana a `/var/log/authlog` da
   uwar garken syslog nesa.

## Format na Rajistar Shiga Mai Kasa

Lokacin da `login_totp` ya ƙi lambar TOTP, yana fitar da sako ta `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

An rubuta wannan sako zuwa:
- Syslog na gida (`/var/log/authlog` akan OpenBSD).
- Uwar garken syslog nesa ta ƙa'idar `auth.info` a cikin `syslog.conf`.

Abubuwan da aka kasa tantancewa ƙarin an rubuta su ta sshd kanta:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Tunani na Fayil

### `login_totp` (Bayan BSD Auth)

- **Wuri:** `/usr/local/libexec/auth/login_totp`
- **Izini:** `root:auth 0550`
- **Fayil ɗin sirri:** `~/.google_authenticator` (layi na farko = sirrin TOTP base-32)
- **Rajista:** `logger -p auth.warning` a kan kasa, `auth.info` a kan nasara
- **Haƙuri na lokaci:** ±1 × mataki na daƙiƙa 30 (za a iya daidaita ta `TOTP_WINDOW`)

### `~/.google_authenticator`

Fayil rubutu na gari; **layi na farko** dole ya zama sirrin TOTP base-32.
Layi ƙarin (sharhi) an yi watsi da su ta `login_totp`.

Misali:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Izini dole su zama `0600`, mallakin mai amfani.

## Bambancin daga Shiryawan FreeBSD / PAM

| Batu | FreeBSD | OpenBSD |
|-------|---------|---------|
| Tsarin tantancewa | PAM (`pam_google_authenticator.so`) | BSD Auth (rubutun `login_totp`) |
| Aji shiga | ba shi ba | Ajin `totp` na `/etc/login.conf` |
| Kunshin | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Daemon na syslog | `syslogd` / `newsyslog` | `syslogd` (an gina shi) |
| Turawa UDP nesa | `@host` a `syslog.conf` | `@host` a `syslog.conf` |
| Turawa TCP nesa | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Warware Matsaloli

**"oathtool not found"**
Shigar oath-toolkit: `doas pkg_add oath-toolkit`

**"No secret file for user"**
Gudu `google-authenticator-setup.sh` don wannan mai amfani, ko ƙirƙiro da hannu
`~/.google_authenticator` tare da sirrin base-32 a layi na farko.

**Ana ƙin lambobin TOTP koyaushe**
Tabbatar cewa agogon tsarin yana daidai (`ntpd` yana kunna akan OpenBSD ta tsoho).
Bambancin agogo fiye da daƙiƙa 30 zai sa duk lambar ta kasa.
Ƙara `TOTP_WINDOW` a cikin `login_totp` idan ya cancanta.

**SSH na neman kalmar wucewa maimakon lambar TOTP**
Tabbatar cewa `KbdInteractiveAuthentication yes` da
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` dukkansu
suna a `/etc/ssh/sshd_config`, kuma mai amfani yana cikin aji shiga `totp`
(`doas usermod -L totp <user>`).

**sshd -t ya kasa bayan gyara sshd_config**
Gudu `doas sshd -t` da gyara duk kurakurai da aka ruwaito kafin sake farawa sshd.
Ajiyar da `setup.sh` ya ƙirƙira tana a
`/etc/ssh/sshd_config.bak.<timestamp>`.

**Syslog nesa baya karɓar saƙonni**
1. Tabbatar cewa ana iya kaiwa ɗaukar ɓangare UDP/TCP 514 na uwar garken nesa:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Duba ƙa'idodin mai tsaro a ɓangarorin biyu (OpenBSD pf da uwar garken nesa).
3. Don turawa TCP, tabbatar cewa `syslogd_flags="-T"` yana a
   `/etc/rc.conf.local` kuma an sake farawa `syslogd`.

## Lasisi

Lasisi BSD 2-Clause. Duba [LICENSE](LICENSE) don cikakkun bayanai.
