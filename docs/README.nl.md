# OpenBSD sshd + Google Authenticator (TOTP)

Tweefactorauthenticatie voor SSH op OpenBSD met behulp van Google Authenticator
(TOTP), waarbij mislukte aanmeldingspogingen worden doorgestuurd naar een externe syslog-server.

## Overzicht

Deze repository biedt:

| Bestand | Doel |
|---------|------|
| `setup.sh` | Geautomatiseerd installatiesscript — eenmalig uitvoeren als root |
| `login_totp` | BSD Auth-backend die de TOTP-code verifieert |
| `google-authenticator-setup.sh` | Registratiescript per gebruiker |
| `sshd_config.snippet` | Referentietoevoegingen aan sshd_config |
| `syslog.conf.snippet` | Referentietoevoegingen aan syslog.conf voor externe doorstuur |

### Authenticatiestroom

```
SSH client
  │
  ▼
sshd  ──── 1. Authenticatie met openbare sleutel (bestaand sleutelpaar)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Prompt: "Google Authenticator code: "
  ├── 3. Gebruiker voert 6-cijferige TOTP-code in vanuit de app
  ├── 4. oathtool verifieert de code aan de hand van ~/.google_authenticator
  │
  ├─ SUCCESS → sessie geopend; auth.info lokaal gelogd + doorgestuurd
  └─ FAILURE → sessie gesloten; auth.warning lokaal gelogd + doorgestuurd
```

## Vereisten

- OpenBSD 7.x (getest op 7.4 en 7.5)
- Root- of `doas`-toegang
- Pakket `oath-toolkit` (`pkg_add oath-toolkit`) — levert `oathtool`
- Een externe syslog-server bereikbaar vanaf de host (rsyslog, syslog-ng, enz.)
- Gebruikers moeten een SSH-openbare sleutel al geïnstalleerd hebben (`~/.ssh/authorized_keys`)

## Snelstart (geautomatiseerd)

```sh
doas sh setup.sh
```

Het script zal:

1. `oath-toolkit` installeren via `pkg_add`.
2. `login_totp` kopiëren naar `/usr/local/libexec/auth/login_totp`.
3. Een aanmeldingsklasse `totp` toevoegen aan `/etc/login.conf`.
4. `/etc/ssh/sshd_config` aanpassen.
5. `/etc/syslog.conf` aanpassen met regels voor externe doorstuur.
6. `syslogd` en `sshd` herstarten.
7. Optioneel `google-authenticator-setup.sh` uitvoeren om een gebruiker te registreren.

## Handmatige installatie

### 1. Installeer oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Installeer het BSD Auth-aanmeldingsscript

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Voeg de aanmeldingsklasse `totp` toe

Voeg het volgende toe aan het einde van `/etc/login.conf`:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

Herbouw vervolgens de login.conf-database:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Configureer sshd

Voeg de regels uit `sshd_config.snippet` toe aan `/etc/ssh/sshd_config`.
De essentiële directives zijn:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Verifieer en herstart sshd:

```sh
doas sshd -t          # configuratie verifiëren
doas rcctl restart sshd
```

### 5. Configureer externe syslog

Voeg de regels uit `syslog.conf.snippet` toe aan `/etc/syslog.conf`, waarbij u
`REMOTE_SYSLOG_SERVER` vervangt door het werkelijke adres van uw server.

**UDP (standaard):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (betrouwbaarder):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Schakel voor TCP ook TCP in via `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Herlaad syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Gebruikers registreren

Voer het registratiescript per gebruiker uit (als root of als de gebruiker zelf):

```sh
doas sh google-authenticator-setup.sh
```

Het script:
1. Genereert een willekeurig 160-bits TOTP-geheim.
2. Schrijft het naar `~/.google_authenticator` (mode 0600).
3. Drukt een `otpauth://`-URI en een terminale QR-code af (als `qrencode` is geïnstalleerd).
4. Wijst de aanmeldingsklasse `totp` toe aan de gebruiker.

Scan de QR-code (of plak de URI) in Google Authenticator, Aegis,
Authy of een andere TOTP-compatibele app.

### 7. Gebruikers toewijzen aan de aanmeldingsklasse totp

Als u `google-authenticator-setup.sh` niet hebt gebruikt, wijs de klasse dan handmatig toe:

```sh
doas usermod -L totp alice
```

## De installatie verifiëren

### Oathtool lokaal testen

```sh
# De huidige TOTP-code genereren voor het geheim van een gebruiker:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Vergelijk dit met de code in de authenticator-app — ze moeten overeenkomen.

### Syslog-doorstuur testen

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Controleer of deze berichten aankomen op de externe syslog-server.

### SSH-aanmelding testen

Open een **nieuwe** SSH-sessie (houd uw bestaande sessie open voor het geval
er iets hersteld moet worden):

```sh
ssh -v alice@your-server
```

Verwachte stroom:
1. sshd accepteert uw openbare sleutel.
2. U ziet de prompt: `Google Authenticator code: `
3. Voer de 6-cijferige code in vanuit de authenticator-app.
4. Aanmelding slaagt of mislukt; het resultaat verschijnt in `/var/log/authlog` en
   op de externe syslog-server.

## Indeling van mislukte aanmeldingslogboeken

Wanneer `login_totp` een TOTP-code weigert, geeft het via `logger(1)` een bericht af:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Dit bericht wordt geschreven naar:
- De lokale syslog (`/var/log/authlog` op OpenBSD).
- De externe syslog-server via de `auth.info`-regel in `syslog.conf`.

Aanvullende mislukte authenticatiegebeurtenissen worden gelogd door sshd zelf:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Bestandsreferentie

### `login_totp` (BSD Auth-backend)

- **Locatie:** `/usr/local/libexec/auth/login_totp`
- **Rechten:** `root:auth 0550`
- **Geheimbestand:** `~/.google_authenticator` (eerste regel = base-32 TOTP-geheim)
- **Logging:** `logger -p auth.warning` bij mislukking, `auth.info` bij succes
- **Tijdtolerantie:** ±1 × 30-secondenstap (configureerbaar via `TOTP_WINDOW`)

### `~/.google_authenticator`

Een bestand met gewone tekst; de **eerste regel** moet het base-32 TOTP-geheim zijn.
Aanvullende regels (commentaar) worden genegeerd door `login_totp`.

Voorbeeld:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Rechten moeten `0600` zijn, in eigendom van de gebruiker.

## Verschillen met FreeBSD / op PAM gebaseerde instellingen

| Onderwerp | FreeBSD | OpenBSD |
|-----------|---------|---------|
| Authenticatieraamwerk | PAM (`pam_google_authenticator.so`) | BSD Auth (script `login_totp`) |
| Aanmeldingsklasse | n.v.t. | Klasse `totp` in `/etc/login.conf` |
| Pakket | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Syslog-daemon | `syslogd` / `newsyslog` | `syslogd` (ingebouwd) |
| Externe UDP-doorstuur | `@host` in `syslog.conf` | `@host` in `syslog.conf` |
| Externe TCP-doorstuur | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Problemen oplossen

**«oathtool not found»**
Installeer oath-toolkit: `doas pkg_add oath-toolkit`

**«No secret file for user»**
Voer `google-authenticator-setup.sh` uit voor die gebruiker, of maak handmatig
`~/.google_authenticator` aan met het base-32 geheim op de eerste regel.

**TOTP-codes worden altijd geweigerd**
Zorg ervoor dat de systeemklok gesynchroniseerd is (`ntpd` is standaard ingeschakeld op OpenBSD).
Een klokafwijking van meer dan 30 seconden zal ervoor zorgen dat elke code mislukt.
Verhoog `TOTP_WINDOW` in `login_totp` indien nodig.

**SSH vraagt om een wachtwoord in plaats van een TOTP-code**
Controleer of zowel `KbdInteractiveAuthentication yes` als
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` aanwezig zijn
in `/etc/ssh/sshd_config`, en dat de gebruiker in de aanmeldingsklasse `totp` zit
(`doas usermod -L totp <user>`).

**sshd -t mislukt na het bewerken van sshd_config**
Voer `doas sshd -t` uit en herstel eventuele gemelde fouten voordat u sshd herstart.
De back-up gemaakt door `setup.sh` bevindt zich op
`/etc/ssh/sshd_config.bak.<timestamp>`.

**Externe syslog ontvangt geen berichten**
1. Bevestig dat UDP/TCP-poort 514 van de externe server bereikbaar is:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Controleer firewallregels aan beide kanten (OpenBSD pf en externe server).
3. Bevestig voor TCP-doorstuur dat `syslogd_flags="-T"` staat in
   `/etc/rc.conf.local` en dat `syslogd` is herstart.

## Licentie

BSD 2-Clause License. Zie [LICENSE](../LICENSE) voor details.
