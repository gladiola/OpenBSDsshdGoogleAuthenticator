# OpenBSD sshd + Google Authenticator (TOTP)

Twee-faktor-verifikasie vir SSH op OpenBSD met behulp van Google Authenticator
(TOTP), met aanstuur van mislukte aanmeldingsrekords na 'n afgeleë syslog-bediener.

## Oorsig

Hierdie bewaarplek bied:

| Lêer | Doel |
|------|------|
| `setup.sh` | Geoutomatiseerde installasie-skrip — voer een keer as root uit |
| `login_totp` | BSD Auth-agterkant wat die TOTP-kode verifieer |
| `google-authenticator-setup.sh` | Registrasie-skrip per gebruiker |
| `sshd_config.snippet` | Verwysings-toevoegings vir sshd_config |
| `syslog.conf.snippet` | Verwysings-toevoegings vir syslog.conf vir afgeleë aanstuur |

### Verifikasievloei

```
SSH client
  │
  ▼
sshd  ──── 1. Verifikasie met openbare sleutel (bestaande sleutelpaar)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Versoek: "Google Authenticator code: "
  ├── 3. Gebruiker voer 6-syfer TOTP-kode vanuit die program in
  ├── 4. oathtool verifieer die kode teen ~/.google_authenticator
  │
  ├─ SUCCESS → sessie geopen; auth.info plaaslik aangeteken + aangestuur
  └─ FAILURE → sessie gesluit; auth.warning plaaslik aangeteken + aangestuur
```

## Vereistes

- OpenBSD 7.x (getoets op 7.4 en 7.5)
- Root- of `doas`-toegang
- Pakket `oath-toolkit` (`pkg_add oath-toolkit`) — lewer `oathtool`
- 'n Afgeleë syslog-bediener bereikbaar vanaf die gasheer (rsyslog, syslog-ng, ens.)
- Gebruikers moet reeds 'n SSH-openbare sleutel geïnstalleer hê (`~/.ssh/authorized_keys`)

## Vinnige begin (geoutomatiseerd)

```sh
doas sh setup.sh
```

Die skrip sal:

1. `oath-toolkit` installeer via `pkg_add`.
2. `login_totp` kopieer na `/usr/local/libexec/auth/login_totp`.
3. 'n `totp`-aanmeldingsklas toevoeg aan `/etc/login.conf`.
4. `/etc/ssh/sshd_config` aanpas.
5. `/etc/syslog.conf` aanpas met reëls vir afgeleë aanstuur.
6. `syslogd` en `sshd` herbegin.
7. Opsioneel `google-authenticator-setup.sh` uitvoer om 'n gebruiker te registreer.

## Handmatige installasie

### 1. Installeer oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Installeer die BSD Auth-aanmeldingskrip

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Voeg die `totp`-aanmeldingsklas by

Voeg die volgende by aan die einde van `/etc/login.conf`:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

Herbou dan die login.conf-databasis:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Konfigureer sshd

Voeg die reëls vanuit `sshd_config.snippet` by aan `/etc/ssh/sshd_config`.
Die noodsaaklike direktiewe is:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Verifieer en herbegin sshd:

```sh
doas sshd -t          # konfigurасie verifieer
doas rcctl restart sshd
```

### 5. Konfigureer afgeleë syslog

Voeg die reëls vanuit `syslog.conf.snippet` by aan `/etc/syslog.conf`, en vervang
`REMOTE_SYSLOG_SERVER` met u werklike bedieneradres.

**UDP (verstek):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (betroubaarder):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Skakel vir TCP ook TCP in via `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Herlaai syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Registreer gebruikers

Voer die registrasie-skrip per gebruiker uit (as root of as die gebruiker self):

```sh
doas sh google-authenticator-setup.sh
```

Die skrip sal:
1. 'n Ewekansige 160-bis TOTP-geheim genereer.
2. Dit skryf na `~/.google_authenticator` (mode 0600).
3. 'n `otpauth://`-URI en 'n terminale QR-kode druk (as `qrencode` geïnstalleer is).
4. Die gebruiker aan die `totp`-aanmeldingsklas toewys.

Skandeer die QR-kode (of plak die URI) in Google Authenticator, Aegis,
Authy of enige TOTP-versoenbare program.

### 7. Wys gebruikers aan die totp-aanmeldingsklas toe

As u nie `google-authenticator-setup.sh` gebruik het nie, wys die klas handmatig toe:

```sh
doas usermod -L totp alice
```

## Installasie verifieer

### Toets oathtool plaaslik

```sh
# Die huidige TOTP-kode vir 'n gebruiker se geheim genereer:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Vergelyk dit met die kode wat in die verifikasie-program verskyn — hulle moet ooreenstem.

### Toets syslog-aanstuur

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Kontroleer dat hierdie boodskappe op die afgeleë syslog-bediener aankom.

### Toets SSH-aanmelding

Maak 'n **nuwe** SSH-sessie oop (hou u bestaande sessie oop vir die geval
dat iets reggestel moet word):

```sh
ssh -v alice@your-server
```

Verwagte vloei:
1. sshd aanvaar u openbare sleutel.
2. U sien die versoek: `Google Authenticator code: `
3. Voer die 6-syfer-kode vanuit die verifikasie-program in.
4. Aanmelding slaag of misluk; die resultaat verskyn in `/var/log/authlog` en
   op die afgeleë syslog-bediener.

## Formaat van mislukte aanmeldingsrekord

Wanneer `login_totp` 'n TOTP-kode verwerp, stuur dit 'n boodskap via `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Hierdie boodskap word geskryf na:
- Die plaaslike syslog (`/var/log/authlog` op OpenBSD).
- Die afgeleë syslog-bediener via die `auth.info`-reël in `syslog.conf`.

Bykomende mislukte verifikasigebeurtenisse word deur sshd self aangeteken:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Lêerverwysing

### `login_totp` (BSD Auth-agterkant)

- **Ligging:** `/usr/local/libexec/auth/login_totp`
- **Regte:** `root:auth 0550`
- **Geheimslêer:** `~/.google_authenticator` (eerste reël = base-32 TOTP-geheim)
- **Aantekening:** `logger -p auth.warning` by mislukking, `auth.info` by sukses
- **Tydtoleransie:** ±1 × 30-sekondes-stap (instelbaar via `TOTP_WINDOW`)

### `~/.google_authenticator`

'n Gewone tekslêer; die **eerste reël** moet die base-32 TOTP-geheim wees.
Bykomende reëls (opmerkings) word deur `login_totp` geïgnoreer.

Voorbeeld:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Regte moet `0600` wees, besit deur die gebruiker.

## Verskille met FreeBSD / PAM-gebaseerde opstellings

| Onderwerp | FreeBSD | OpenBSD |
|-----------|---------|---------|
| Verifikasieraamwerk | PAM (`pam_google_authenticator.so`) | BSD Auth (skrip `login_totp`) |
| Aanmeldingsklas | n.v.t. | Klas `totp` in `/etc/login.conf` |
| Pakket | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Syslog-daemon | `syslogd` / `newsyslog` | `syslogd` (ingebou) |
| Afgeleë UDP-aanstuur | `@host` in `syslog.conf` | `@host` in `syslog.conf` |
| Afgeleë TCP-aanstuur | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Probleemoplossing

**«oathtool not found»**
Installeer oath-toolkit: `doas pkg_add oath-toolkit`

**«No secret file for user»**
Voer `google-authenticator-setup.sh` uit vir daardie gebruiker, of skep handmatig
`~/.google_authenticator` met die base-32-geheim op die eerste reël.

**TOTP-kodes word altyd verwerp**
Maak seker dat die stelselhorlosie gesinkroniseer is (`ntpd` is by verstek ingeskakel op OpenBSD).
'n Horlosie-verskil van meer as 30 sekondes sal veroorsaak dat elke kode misluk.
Vergroot `TOTP_WINDOW` in `login_totp` indien nodig.

**SSH vra vir 'n wagwoord in plaas van 'n TOTP-kode**
Verifieer dat beide `KbdInteractiveAuthentication yes` en
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` aanwesig is
in `/etc/ssh/sshd_config`, en dat die gebruiker in die `totp`-aanmeldingsklas is
(`doas usermod -L totp <user>`).

**sshd -t misluk ná redigering van sshd_config**
Voer `doas sshd -t` uit en herstel enige aangemelde foute voordat u sshd herbegin.
Die rugsteun geskep deur `setup.sh` is by
`/etc/ssh/sshd_config.bak.<timestamp>`.

**Afgeleë syslog ontvang nie boodskappe nie**
1. Bevestig dat die afgeleë bediener se UDP/TCP-poort 514 bereikbaar is:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Kontroleer brandmuurreëls aan beide kante (OpenBSD pf en afgeleë bediener).
3. Bevestig vir TCP-aanstuur dat `syslogd_flags="-T"` in
   `/etc/rc.conf.local` is en dat `syslogd` herbegin is.

## Lisensie

BSD 2-Clause License. Sien [LICENSE](../LICENSE) vir besonderhede.
