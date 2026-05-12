# OpenBSD sshd + Google Authenticator (TOTP)

Tofaktorautentisering for OpenBSD SSH ved hjelp av Google Authenticator
(TOTP), med videresending av mislykkede innloggingsforsøk til en ekstern syslog-server.

## Oversikt

Dette depotet inneholder:

| Fil | Formål |
|-----|--------|
| `setup.sh` | Automatisert oppsettskript — kjøres én gang som root |
| `login_totp` | BSD Auth-backend som verifiserer TOTP-koden |
| `google-authenticator-setup.sh` | Registreringsskript per bruker |
| `sshd_config.snippet` | Referansetillegg for sshd_config |
| `syslog.conf.snippet` | Referansetillegg for syslog.conf for ekstern videresending |

### Autentiseringsflyt

```
SSH-klient
  │
  ▼
sshd  ──── 1. Autentisering med offentlig nøkkel (eksisterende nøkkelpar)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Forespørsel: "Google Authenticator code: "
  ├── 3. Brukeren skriver inn 6-sifret TOTP fra appen
  ├── 4. oathtool verifiserer koden mot ~/.google_authenticator
  │
  ├─ SUKSESS → økt åpnet; auth.info logget lokalt + videresendt
  └─ FEIL → økt lukket; auth.warning logget lokalt + videresendt
```

## Krav

- OpenBSD 7.x (testet på 7.4 og 7.5)
- Root- eller `doas`-tilgang
- `oath-toolkit`-pakken (`pkg_add oath-toolkit`) — gir `oathtool`
- En ekstern syslog-server tilgjengelig fra verten (rsyslog, syslog-ng, osv.)
- Brukere må ha en SSH-offentlig nøkkel installert (`~/.ssh/authorized_keys`)

## Hurtigstart (automatisert)

```sh
doas sh setup.sh
```

Skriptet vil:

1. Installere `oath-toolkit` via `pkg_add`.
2. Kopiere `login_totp` til `/usr/local/libexec/auth/login_totp`.
3. Legge til en `totp`-innloggingsklasse i `/etc/login.conf`.
4. Patche `/etc/ssh/sshd_config`.
5. Patche `/etc/syslog.conf` med regler for ekstern videresending.
6. Starte `syslogd` og `sshd` på nytt.
7. Eventuelt kjøre `google-authenticator-setup.sh` for å registrere en bruker.

## Manuell installasjon

### 1. Installer oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Installer BSD Auth-innloggingsskriptet

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Legg til `totp`-innloggingsklassen

Legg til følgende i `/etc/login.conf`:

```
# TOTP (Google Authenticator) innloggingsklasse
totp:\
    :auth=-totp:\
    :tc=default:
```

Deretter gjenoppbygg login.conf-databasen:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Konfigurer sshd

Legg til linjene fra `sshd_config.snippet` i `/etc/ssh/sshd_config`.
De kritiske direktivene er:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Verifiser og start sshd på nytt:

```sh
doas sshd -t          # verifiser konfigurasjon
doas rcctl restart sshd
```

### 5. Konfigurer ekstern syslog

Legg til linjene fra `syslog.conf.snippet` i `/etc/syslog.conf`, og erstatt
`REMOTE_SYSLOG_SERVER` med din faktiske serveradresse.

**UDP (standard):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (mer pålitelig):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

For TCP, aktiver også TCP i `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Last inn syslogd på nytt:

```sh
doas rcctl restart syslogd
```

### 6. Registrer brukere

Kjør registreringsskriptet per bruker (som root eller som brukeren selv):

```sh
doas sh google-authenticator-setup.sh
```

Skriptet:
1. Genererer en tilfeldig 160-bits TOTP-hemmelighet.
2. Skriver den til `~/.google_authenticator` (modus 0600).
3. Skriver ut en `otpauth://`-URI og en terminal-QR-kode (hvis `qrencode` er installert).
4. Tilordner brukeren til `totp`-innloggingsklassen.

Skann QR-koden (eller lim inn URI-en) i Google Authenticator, Aegis,
Authy, eller en annen TOTP-kompatibel app.

### 7. Tilordne brukere til totp-innloggingsklassen

Hvis du ikke brukte `google-authenticator-setup.sh`, tilordne klassen manuelt:

```sh
doas usermod -L totp alice
```

## Verifisering av oppsettet

### Test oathtool lokalt

```sh
# Generer gjeldende TOTP-kode for en brukers hemmelighet:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Sammenlign dette med koden som vises i autentiseringsappen — de skal stemme overens.

### Test syslog-videresending

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Kontroller at disse meldingene ankommer på den eksterne syslog-serveren.

### Test SSH-innlogging

Åpne en **ny** SSH-økt (hold den eksisterende øKten åpen i tilfelle
noe trenger å fikses):

```sh
ssh -v alice@your-server
```

Forventet flyt:
1. sshd godtar din offentlige nøkkel.
2. Du ser forespørselen: `Google Authenticator code: `
3. Skriv inn den 6-sifrede koden fra autentiseringsappen.
4. Innlogging lykkes eller mislykkes; resultatet vises i `/var/log/authlog` og
   på den eksterne syslog-serveren.

## Format for mislykkede innloggingslogger

Når `login_totp` avviser en TOTP-kode, sender den en melding via `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Denne meldingen skrives til:
- Den lokale syslogen (`/var/log/authlog` på OpenBSD).
- Den eksterne syslog-serveren via `auth.info`-regelen i `syslog.conf`.

Ytterligere mislykkede autentiseringshendelser logges av sshd selv:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Filreferanse

### `login_totp` (BSD Auth-backend)

- **Plassering:** `/usr/local/libexec/auth/login_totp`
- **Tillatelser:** `root:auth 0550`
- **Hemmelighetsfil:** `~/.google_authenticator` (første linje = base-32 TOTP-hemmelighet)
- **Logging:** `logger -p auth.warning` ved feil, `auth.info` ved suksess
- **Tidstoleranse:** ±1 × 30-sekunders steg (konfigurerbart via `TOTP_WINDOW`)

### `~/.google_authenticator`

En ren tekstfil; den **første linjen** må være base-32 TOTP-hemmeligheten.
Ytterligere linjer (kommentarer) ignoreres av `login_totp`.

Eksempel:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Tillatelsene må være `0600`, eid av brukeren.

## Forskjeller fra FreeBSD / PAM-baserte oppsett

| Emne | FreeBSD | OpenBSD |
|------|---------|---------|
| Autentiseringsrammeverk | PAM (`pam_google_authenticator.so`) | BSD Auth (`login_totp`-skript) |
| Innloggingsklasse | ikke aktuelt | `/etc/login.conf` `totp`-klasse |
| Pakke | `security/google-authenticator-pam` | `security/oath-toolkit` |
| syslog-tjeneste | `syslogd` / `newsyslog` | `syslogd` (innebygd) |
| Ekstern UDP-videresending | `@host` i `syslog.conf` | `@host` i `syslog.conf` |
| Ekstern TCP-videresending | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Feilsøking

**«oathtool not found»**
Installer oath-toolkit: `doas pkg_add oath-toolkit`

**«No secret file for user»**
Kjør `google-authenticator-setup.sh` for den brukeren, eller opprett manuelt
`~/.google_authenticator` med base-32-hemmeligheten på første linje.

**TOTP-koder alltid avvist**
Sørg for at systemklokken er synkronisert (`ntpd` er aktivert på OpenBSD som
standard). En klokkeforskyvning på mer enn 30 sekunder vil føre til at alle koder
mislykkes. Øk `TOTP_WINDOW` i `login_totp` om nødvendig.

**SSH ber om passord i stedet for TOTP-kode**
Verifiser at `KbdInteractiveAuthentication yes` og
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` begge
er til stede i `/etc/ssh/sshd_config`, og at brukeren er i `totp`-innloggingsklassen
(`doas usermod -L totp <bruker>`).

**sshd -t mislykkes etter redigering av sshd_config**
Kjør `doas sshd -t` og fiks eventuelle rapporterte feil før sshd startes på nytt.
Sikkerhetskopien opprettet av `setup.sh` er på
`/etc/ssh/sshd_config.bak.<tidsstempel>`.

**Ekstern syslog mottar ikke meldinger**
1. Bekreft at den eksterne serverens UDP/TCP-port 514 er tilgjengelig:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Kontroller brannmurregler på begge ender (OpenBSD pf og ekstern server).
3. For TCP-videresending, bekreft at `syslogd_flags="-T"` er i
   `/etc/rc.conf.local` og at `syslogd` er startet på nytt.

## Lisens

BSD 2-klausul-lisens. Se [LICENSE](LICENSE) for detaljer.
