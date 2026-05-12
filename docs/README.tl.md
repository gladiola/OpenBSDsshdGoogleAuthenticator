# OpenBSD sshd + Google Authenticator (TOTP)

Dalawang-salik na pagpapatunay para sa OpenBSD SSH gamit ang Google Authenticator
(TOTP), na may mga log ng nabigong pag-login na ipinапараte sa isang malayong syslog server.

## Pangkalahatang-ideya

Ang repositoryong ito ay nagbibigay ng:

| File | Layunin |
|------|---------|
| `setup.sh` | Awtomatikong script ng pag-setup — patakbuhin nang isang beses bilang root |
| `login_totp` | Backend ng BSD Auth na nagbe-verify ng TOTP code |
| `google-authenticator-setup.sh` | Script ng pagpapalista para sa bawat user |
| `sshd_config.snippet` | Mga karagdagan sa sshd_config bilang sanggunian |
| `syslog.conf.snippet` | Mga karagdagan sa syslog.conf para sa malayong pagpapasa bilang sanggunian |

### Daloy ng pagpapatunay

```
SSH client
  │
  ▼
sshd  ──── 1. Pagpapatunay ng pampublikong susi (mayroon nang pares ng susi)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Prompt: "Google Authenticator code: "
  ├── 3. Naglalagay ang user ng 6-digit na TOTP mula sa app
  ├── 4. Bine-verify ng oathtool ang code laban sa ~/.google_authenticator
  │
  ├─ TAGUMPAY → nabuksan ang session; naka-log ang auth.info nang lokal + naipasa
  └─ KABIGUAN → nasara ang session; naka-log ang auth.warning nang lokal + naipasa
```

## Mga Kinakailangan

- OpenBSD 7.x (nasubok sa 7.4 at 7.5)
- Akses bilang root o `doas`
- Package na `oath-toolkit` (`pkg_add oath-toolkit`) — nagbibigay ng `oathtool`
- Malayong syslog server na maaabot mula sa host (rsyslog, syslog-ng, atbp.)
- Kailangang mayroon nang naka-install na pampublikong susi ng SSH ang mga user (`~/.ssh/authorized_keys`)

## Mabilis na pagsisimula (awtomatiko)

```sh
doas sh setup.sh
```

Ang script ay:

1. Mag-i-install ng `oath-toolkit` sa pamamagitan ng `pkg_add`.
2. Kokopya ng `login_totp` sa `/usr/local/libexec/auth/login_totp`.
3. Magdadagdag ng klase ng pag-login na `totp` sa `/etc/login.conf`.
4. Magbabago ng `/etc/ssh/sshd_config`.
5. Magbabago ng `/etc/syslog.conf` na may mga panuntunan ng malayong pagpapasa.
6. Mag-re-restart ng `syslogd` at `sshd`.
7. Opsyonal: magpapatakbo ng `google-authenticator-setup.sh` para mapalista ang isang user.

## Manu-manong pag-install

### 1. I-install ang oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. I-install ang BSD Auth login script

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Idagdag ang klase ng pag-login na `totp`

Idagdag ang sumusunod sa dulo ng `/etc/login.conf`:

```
# Klase ng pag-login na TOTP (Google Authenticator)
totp:\
    :auth=-totp:\
    :tc=default:
```

Pagkatapos ay i-rebuild ang database ng login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. I-configure ang sshd

Idagdag ang mga linya mula sa `sshd_config.snippet` sa `/etc/ssh/sshd_config`.
Ang mga kritikal na direktiba ay:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

I-verify at i-restart ang sshd:

```sh
doas sshd -t          # i-verify ang config
doas rcctl restart sshd
```

### 5. I-configure ang malayong syslog

Idagdag ang mga linya mula sa `syslog.conf.snippet` sa `/etc/syslog.conf`, palitan ang
`REMOTE_SYSLOG_SERVER` ng iyong aktwal na address ng server.

**UDP (default):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (mas maaasahan):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Para sa TCP, paganahin din ang TCP sa `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

I-reload ang syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Ipalista ang mga user

Patakbuhin ang script ng pagpapalista para sa bawat user (bilang root o bilang mismong user):

```sh
doas sh google-authenticator-setup.sh
```

Ang script ay:
1. Bubuo ng random na 160-bit na TOTP secret.
2. Isusulat ito sa `~/.google_authenticator` (mode 0600).
3. Magpi-print ng `otpauth://` URI at terminal QR code (kung naka-install ang `qrencode`).
4. Magtatalaga ng user sa klase ng pag-login na `totp`.

I-scan ang QR code (o i-paste ang URI) sa Google Authenticator, Aegis,
Authy, o anumang app na compatible sa TOTP.

### 7. Italaga ang mga user sa klase ng pag-login na totp

Kung hindi mo ginamit ang `google-authenticator-setup.sh`, italaga ang klase nang manu-mano:

```sh
doas usermod -L totp alice
```

## Pag-verify ng setup

### Subukan ang oathtool nang lokal

```sh
# Bumuo ng kasalukuyang TOTP code para sa secret ng isang user:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Ihambing ito sa code na ipinapakita sa authenticator app — dapat magkatugma ang mga ito.

### Subukan ang pagpapasa ng syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Suriin na dumating ang mga mensaheng ito sa malayong syslog server.

### Subukan ang SSH login

Magbukas ng **bagong** SSH session (panatilihing bukas ang iyong kasalukuyang session sakaling may kailangang ayusin):

```sh
ssh -v alice@your-server
```

Inaasahang daloy:
1. Tinatanggap ng sshd ang iyong pampublikong susi.
2. Makikita mo ang prompt: `Google Authenticator code: `
3. Ilagay ang 6-digit na code mula sa authenticator app.
4. Nagtagumpay o nabigo ang pag-login; ang resulta ay lilitaw sa `/var/log/authlog` at
   sa malayong syslog server.

## Format ng log ng nabigong pag-login

Kapag tinanggihan ng `login_totp` ang isang TOTP code, naglalabas ito ng mensahe sa pamamagitan ng `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Ang mensaheng ito ay isinusulat sa:
- Lokal na syslog (`/var/log/authlog` sa OpenBSD).
- Malayong syslog server sa pamamagitan ng panuntunan na `auth.info` sa `syslog.conf`.

Ang mga karagdagang event ng nabigong pagpapatunay ay ini-log ng mismong sshd:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Sanggunian ng file

### `login_totp` (backend ng BSD Auth)

- **Lokasyon:** `/usr/local/libexec/auth/login_totp`
- **Mga pahintulot:** `root:auth 0550`
- **Secret file:** `~/.google_authenticator` (unang linya = base-32 na TOTP secret)
- **Pag-log:** `logger -p auth.warning` kapag nabigo, `auth.info` kapag nagtagumpay
- **Toleransya sa oras:** ±1 × 30-second na hakbang (maaaring i-configure sa pamamagitan ng `TOTP_WINDOW`)

### `~/.google_authenticator`

Isang plain-text na file; ang **unang linya** ay dapat na base-32 na TOTP secret.
Ang mga karagdagang linya (mga komento) ay binabalewala ng `login_totp`.

Halimbawa:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Ang mga pahintulot ay dapat na `0600`, pag-aari ng user.

## Mga pagkakaiba mula sa FreeBSD / mga setup na nakabatay sa PAM

| Paksa | FreeBSD | OpenBSD |
|-------|---------|---------|
| Framework ng pagpapatunay | PAM (`pam_google_authenticator.so`) | BSD Auth (script na `login_totp`) |
| Klase ng pag-login | wala | klase ng `totp` sa `/etc/login.conf` |
| Package | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Syslog daemon | `syslogd` / `newsyslog` | `syslogd` (built-in) |
| Malayong pagpapasa ng UDP | `@host` sa `syslog.conf` | `@host` sa `syslog.conf` |
| Malayong pagpapasa ng TCP | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Pag-aayos ng mga problema

**"oathtool not found"**
I-install ang oath-toolkit: `doas pkg_add oath-toolkit`

**"No secret file for user"**
Patakbuhin ang `google-authenticator-setup.sh` para sa user na iyon, o manu-manong gumawa ng
`~/.google_authenticator` na may base-32 na secret sa unang linya.

**Laging tinatanggihan ang mga TOTP code**
Tiyaking naka-synchronize ang orasan ng system (ang `ntpd` ay pinagana bilang default sa OpenBSD).
Ang pagkakaiba ng orasan na higit sa 30 segundo ay magiging sanhi ng pagkabigo ng bawat code. Dagdagan ang `TOTP_WINDOW`
sa `login_totp` kung kinakailangan.

**Humihingi ang SSH ng password sa halip na TOTP code**
I-verify na parehong `KbdInteractiveAuthentication yes` at
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` ay naroroon
sa `/etc/ssh/sshd_config`, at na ang user ay nasa klase ng pag-login na `totp`
(`doas usermod -L totp <user>`).

**Nabibigo ang sshd -t pagkatapos i-edit ang sshd_config**
Patakbuhin ang `doas sshd -t` at ayusin ang anumang iniulat na mga error bago i-restart ang sshd.
Ang backup na nilikha ng `setup.sh` ay nasa
`/etc/ssh/sshd_config.bak.<timestamp>`.

**Hindi tumatanggap ng mensahe ang malayong syslog**
1. Kumpirmahin na maaabot ang UDP/TCP port 514 ng malayong server:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Suriin ang mga panuntunan ng firewall sa magkabilang dulo (OpenBSD pf at malayong server).
3. Para sa pagpapasa ng TCP, kumpirmahin na ang `syslogd_flags="-T"` ay nasa
   `/etc/rc.conf.local` at na na-restart na ang `syslogd`.

## Lisensya

BSD 2-Clause License. Tingnan ang [LICENSE](../LICENSE) para sa mga detalye.
