# OpenBSD sshd + Google Authenticator (TOTP)

Tvåfaktorsautentisering för OpenBSD SSH med Google Authenticator
(TOTP), där loggar för misslyckade inloggningar vidarebefordras till en fjärrsyslog-server.

## Översikt

Det här arkivet tillhandahåller:

| Fil | Syfte |
|------|---------|
| `setup.sh` | Automatiserat installationsskript — kör en gång som root |
| `login_totp` | BSD Auth-bakgrund som verifierar TOTP-koden |
| `google-authenticator-setup.sh` | Registreringsskript per användare |
| `sshd_config.snippet` | Referenstillägg för sshd_config |
| `syslog.conf.snippet` | Referenstillägg för syslog.conf för fjärrvidarebefordran |

### Autentiseringsflöde

```
SSH-klient
  │
  ▼
sshd  ──── 1. Autentisering med offentlig nyckel (befintligt nyckelpar)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Uppmaning: "Google Authenticator code: "
  ├── 3. Användaren anger en 6-siffrig TOTP-kod från appen
  ├── 4. oathtool verifierar koden mot ~/.google_authenticator
  │
  ├─ LYCKADES → session öppnad; auth.info loggat lokalt + vidarebefordrat
  └─ MISSLYCKADES → session stängd; auth.warning loggat lokalt + vidarebefordrat
```

## Krav

- OpenBSD 7.x (testat på 7.4 och 7.5)
- Root- eller `doas`-åtkomst
- Paketet `oath-toolkit` (`pkg_add oath-toolkit`) — tillhandahåller `oathtool`
- En fjärrsyslog-server nåbar från värden (rsyslog, syslog-ng osv.)
- Användare måste ha en SSH-offentlig nyckel installerad (`~/.ssh/authorized_keys`)

## Snabbstart (automatiserad)

```sh
doas sh setup.sh
```

Skriptet kommer att:

1. Installera `oath-toolkit` via `pkg_add`.
2. Kopiera `login_totp` till `/usr/local/libexec/auth/login_totp`.
3. Lägga till en `totp`-inloggningsklass i `/etc/login.conf`.
4. Patcha `/etc/ssh/sshd_config`.
5. Patcha `/etc/syslog.conf` med regler för fjärrvidarebefordran.
6. Starta om `syslogd` och `sshd`.
7. Valfritt köra `google-authenticator-setup.sh` för att registrera en användare.

## Manuell installation

### 1. Installera oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Installera BSD Auth-inloggningsskriptet

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Lägg till `totp`-inloggningsklassen

Lägg till följande i slutet av `/etc/login.conf`:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

Bygg sedan om login.conf-databasen:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Konfigurera sshd

Lägg till raderna från `sshd_config.snippet` i `/etc/ssh/sshd_config`.
De kritiska direktiven är:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Verifiera och starta om sshd:

```sh
doas sshd -t          # verifiera konfiguration
doas rcctl restart sshd
```

### 5. Konfigurera fjärrsyslog

Lägg till raderna från `syslog.conf.snippet` i `/etc/syslog.conf` och ersätt
`REMOTE_SYSLOG_SERVER` med din faktiska serveradress.

**UDP (standard):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (mer tillförlitligt):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

För TCP, aktivera även TCP i `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Ladda om syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Registrera användare

Kör registreringsskriptet per användare (som root eller som användaren själv):

```sh
doas sh google-authenticator-setup.sh
```

Skriptet:
1. Genererar en slumpmässig 160-bitars TOTP-hemlighet.
2. Skriver den till `~/.google_authenticator` (behörighet 0600).
3. Skriver ut en `otpauth://`-URI och en QR-kod i terminalen (om `qrencode` är installerat).
4. Tilldelar användaren `totp`-inloggningsklassen.

Skanna QR-koden (eller klistra in URI) i Google Authenticator, Aegis,
Authy eller någon annan TOTP-kompatibel app.

### 7. Tilldela användare till totp-inloggningsklassen

Om du inte använde `google-authenticator-setup.sh`, tilldela klassen manuellt:

```sh
doas usermod -L totp alice
```

## Verifiera konfigurationen

### Testa oathtool lokalt

```sh
# Generera den aktuella TOTP-koden för en användares hemlighet:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Jämför detta med koden som visas i autentiseringsappen — de ska stämma överens.

### Testa syslog-vidarebefordran

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Kontrollera att dessa meddelanden anländer till fjärrsyslog-servern.

### Testa SSH-inloggning

Öppna en **ny** SSH-session (håll din befintliga session öppen ifall
något behöver åtgärdas):

```sh
ssh -v alice@your-server
```

Förväntat flöde:
1. sshd accepterar din offentliga nyckel.
2. Du ser uppmaningen: `Google Authenticator code: `
3. Ange den 6-siffriga koden från autentiseringsappen.
4. Inloggningen lyckas eller misslyckas; resultatet visas i `/var/log/authlog`
   och på fjärrsyslog-servern.

## Loggformat för misslyckade inloggningar

När `login_totp` avvisar en TOTP-kod skickar den ett meddelande via `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Det här meddelandet skrivs till:
- Den lokala sysloggen (`/var/log/authlog` på OpenBSD).
- Fjärrsyslog-servern via `auth.info`-regeln i `syslog.conf`.

Ytterligare misslyckade autentiseringshändelser loggas av sshd självt:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Filreferens

### `login_totp` (BSD Auth-bakgrund)

- **Plats:** `/usr/local/libexec/auth/login_totp`
- **Behörigheter:** `root:auth 0550`
- **Hemlighetsfil:** `~/.google_authenticator` (första raden = base-32 TOTP-hemlighet)
- **Loggning:** `logger -p auth.warning` vid misslyckande, `auth.info` vid framgång
- **Tidstolerans:** ±1 × 30-sekunders steg (konfigurerbart via `TOTP_WINDOW`)

### `~/.google_authenticator`

En klarextfil; **första raden** måste vara base-32 TOTP-hemligheten.
Ytterligare rader (kommentarer) ignoreras av `login_totp`.

Exempel:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Behörigheterna måste vara `0600` och ägas av användaren.

## Skillnader från FreeBSD / PAM-baserade konfigurationer

| Ämne | FreeBSD | OpenBSD |
|-------|---------|---------|
| Autentiseringsramverk | PAM (`pam_google_authenticator.so`) | BSD Auth (`login_totp`-skript) |
| Inloggningsklass | saknas | `/etc/login.conf` `totp`-klass |
| Paket | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Syslog-demon | `syslogd` / `newsyslog` | `syslogd` (inbyggd) |
| Fjärr-UDP-vidarebefordran | `@host` i `syslog.conf` | `@host` i `syslog.conf` |
| Fjärr-TCP-vidarebefordran | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Felsökning

**"oathtool not found"**
Installera oath-toolkit: `doas pkg_add oath-toolkit`

**"No secret file for user"**
Kör `google-authenticator-setup.sh` för den användaren, eller skapa manuellt
`~/.google_authenticator` med base-32-hemligheten på första raden.

**TOTP-koder avvisas alltid**
Se till att systemklockan är synkroniserad (`ntpd` är aktiverat som standard på OpenBSD).
En klockdrift på mer än 30 sekunder gör att varje kod misslyckas.
Öka `TOTP_WINDOW` i `login_totp` om det behövs.

**SSH frågar efter lösenord istället för TOTP-kod**
Kontrollera att både `KbdInteractiveAuthentication yes` och
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` finns
i `/etc/ssh/sshd_config`, och att användaren tillhör `totp`-inloggningsklassen
(`doas usermod -L totp <användare>`).

**sshd -t misslyckas efter redigering av sshd_config**
Kör `doas sshd -t` och åtgärda eventuella rapporterade fel innan du startar om sshd.
Säkerhetskopian som skapades av `setup.sh` finns på
`/etc/ssh/sshd_config.bak.<tidsstämpel>`.

**Fjärrsyslog tar inte emot meddelanden**
1. Bekräfta att fjärrserverns UDP/TCP-port 514 är nåbar:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Kontrollera brandväggsregler i båda ändar (OpenBSD pf och fjärrservern).
3. För TCP-vidarebefordran, bekräfta att `syslogd_flags="-T"` finns i
   `/etc/rc.conf.local` och att `syslogd` har startats om.

## Licens

BSD 2-klausuls licens. Se [LICENSE](LICENSE) för detaljer.
