# OpenBSD sshd + Google Authenticator (TOTP)

Zwei-Faktor-Authentifizierung für OpenBSD SSH mit Google Authenticator
(TOTP), mit Weiterleitung von Fehlversuchs-Protokollen an einen entfernten Syslog-Server.

## Übersicht

Dieses Repository enthält:

| Datei | Zweck |
|-------|-------|
| `setup.sh` | Automatisiertes Einrichtungsskript — einmalig als root ausführen |
| `login_totp` | BSD-Auth-Backend zur Überprüfung des TOTP-Codes |
| `google-authenticator-setup.sh` | Benutzerweises Registrierungsskript |
| `sshd_config.snippet` | Referenz-Ergänzungen für sshd_config |
| `syslog.conf.snippet` | Referenz-Ergänzungen für syslog.conf zur Remote-Weiterleitung |

### Authentifizierungsablauf

```
SSH-Client
  │
  ▼
sshd  ──── 1. Public-Key-Authentifizierung (vorhandenes Schlüsselpaar)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Eingabeaufforderung: "Google Authenticator code: "
  ├── 3. Benutzer gibt den 6-stelligen TOTP aus der App ein
  ├── 4. oathtool prüft den Code gegen ~/.google_authenticator
  │
  ├─ ERFOLG → Sitzung geöffnet; auth.info lokal protokolliert + weitergeleitet
  └─ FEHLER  → Sitzung geschlossen; auth.warning lokal protokolliert + weitergeleitet
```

## Voraussetzungen

- OpenBSD 7.x (getestet auf 7.4 und 7.5)
- Root- oder `doas`-Zugriff
- Paket `oath-toolkit` (`pkg_add oath-toolkit`) — stellt `oathtool` bereit
- Ein vom Host aus erreichbarer entfernter Syslog-Server (rsyslog, syslog-ng usw.)
- Benutzer müssen bereits einen installierten SSH-Public-Key haben (`~/.ssh/authorized_keys`)

## Schnellstart (automatisiert)

```sh
doas sh setup.sh
```

Das Skript führt folgende Schritte aus:

1. Installation von `oath-toolkit` via `pkg_add`.
2. Kopieren von `login_totp` nach `/usr/local/libexec/auth/login_totp`.
3. Hinzufügen einer `totp`-Login-Klasse zu `/etc/login.conf`.
4. Anpassen von `/etc/ssh/sshd_config`.
5. Anpassen von `/etc/syslog.conf` mit Regeln zur Remote-Weiterleitung.
6. Neustart von `syslogd` und `sshd`.
7. Optionales Ausführen von `google-authenticator-setup.sh` zur Benutzerregistrierung.

## Manuelle Installation

### 1. oath-toolkit installieren

```sh
doas pkg_add oath-toolkit
```

### 2. BSD-Auth-Login-Skript installieren

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Login-Klasse `totp` hinzufügen

Folgendes an `/etc/login.conf` anhängen:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

Anschließend die login.conf-Datenbank neu erstellen:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. sshd konfigurieren

Die Zeilen aus `sshd_config.snippet` zu `/etc/ssh/sshd_config` hinzufügen.
Die wichtigsten Direktiven sind:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Konfiguration prüfen und sshd neu starten:

```sh
doas sshd -t          # Konfiguration prüfen
doas rcctl restart sshd
```

### 5. Remote-Syslog konfigurieren

Die Zeilen aus `syslog.conf.snippet` zu `/etc/syslog.conf` hinzufügen und
`REMOTE_SYSLOG_SERVER` durch die tatsächliche Serveradresse ersetzen.

**UDP (Standard):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (zuverlässiger):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Für TCP zusätzlich TCP in `/etc/rc.conf.local` aktivieren:

```
syslogd_flags="-T"
```

syslogd neu laden:

```sh
doas rcctl restart syslogd
```

### 6. Benutzer registrieren

Das benutzerweise Registrierungsskript ausführen (als root oder als der Benutzer selbst):

```sh
doas sh google-authenticator-setup.sh
```

Das Skript:
1. Erzeugt ein zufälliges 160-Bit-TOTP-Geheimnis.
2. Schreibt es nach `~/.google_authenticator` (Modus 0600).
3. Gibt eine `otpauth://`-URI und einen Terminal-QR-Code aus (falls `qrencode` installiert ist).
4. Weist den Benutzer der Login-Klasse `totp` zu.

Den QR-Code scannen (oder die URI einfügen) in Google Authenticator, Aegis,
Authy oder eine beliebige TOTP-kompatible App.

### 7. Benutzer der totp-Login-Klasse zuweisen

Falls `google-authenticator-setup.sh` nicht verwendet wurde, die Klasse manuell zuweisen:

```sh
doas usermod -L totp alice
```

## Einrichtung überprüfen

### oathtool lokal testen

```sh
# Aktuellen TOTP-Code für das Geheimnis eines Benutzers erzeugen:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Diesen Code mit dem in der Authenticator-App angezeigten Code vergleichen — sie sollten übereinstimmen.

### Syslog-Weiterleitung testen

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Prüfen, ob diese Meldungen auf dem entfernten Syslog-Server ankommen.

### SSH-Anmeldung testen

Eine **neue** SSH-Sitzung öffnen (die bestehende Sitzung offen lassen, falls etwas behoben werden muss):

```sh
ssh -v alice@your-server
```

Erwarteter Ablauf:
1. sshd akzeptiert den Public Key.
2. Die Eingabeaufforderung erscheint: `Google Authenticator code: `
3. Den 6-stelligen Code aus der Authenticator-App eingeben.
4. Anmeldung erfolgreich oder fehlgeschlagen; das Ergebnis erscheint in `/var/log/authlog` und
   auf dem entfernten Syslog-Server.

## Format der Fehlversuchs-Protokollmeldungen

Wenn `login_totp` einen TOTP-Code ablehnt, sendet es eine Meldung über `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Diese Meldung wird geschrieben nach:
- Den lokalen Syslog (`/var/log/authlog` auf OpenBSD).
- Den entfernten Syslog-Server über die `auth.info`-Regel in `syslog.conf`.

Weitere fehlgeschlagene Authentifizierungsereignisse werden von sshd selbst protokolliert:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Dateireferenz

### `login_totp` (BSD-Auth-Backend)

- **Speicherort:** `/usr/local/libexec/auth/login_totp`
- **Berechtigungen:** `root:auth 0550`
- **Geheimdatei:** `~/.google_authenticator` (erste Zeile = Base-32-TOTP-Geheimnis)
- **Protokollierung:** `logger -p auth.warning` bei Fehler, `auth.info` bei Erfolg
- **Zeittoleranz:** ±1 × 30-Sekunden-Schritt (konfigurierbar über `TOTP_WINDOW`)

### `~/.google_authenticator`

Eine Klartextdatei; die **erste Zeile** muss das Base-32-TOTP-Geheimnis sein.
Weitere Zeilen (Kommentare) werden von `login_totp` ignoriert.

Beispiel:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Berechtigungen müssen `0600` sein, im Besitz des jeweiligen Benutzers.

## Unterschiede zu FreeBSD / PAM-basierten Setups

| Thema | FreeBSD | OpenBSD |
|-------|---------|---------|
| Auth-Framework | PAM (`pam_google_authenticator.so`) | BSD Auth (`login_totp`-Skript) |
| Login-Klasse | k. A. | `/etc/login.conf` Klasse `totp` |
| Paket | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Syslog-Daemon | `syslogd` / `newsyslog` | `syslogd` (eingebaut) |
| Remote-UDP-Weiterleitung | `@host` in `syslog.conf` | `@host` in `syslog.conf` |
| Remote-TCP-Weiterleitung | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Fehlerbehebung

**„oathtool not found"**
oath-toolkit installieren: `doas pkg_add oath-toolkit`

**„No secret file for user"**
`google-authenticator-setup.sh` für diesen Benutzer ausführen oder manuell
`~/.google_authenticator` mit dem Base-32-Geheimnis in der ersten Zeile erstellen.

**TOTP-Codes werden immer abgelehnt**
Sicherstellen, dass die Systemuhr synchronisiert ist (`ntpd` ist auf OpenBSD standardmäßig
aktiviert). Eine Uhrabweichung von mehr als 30 Sekunden führt dazu, dass jeder Code fehlschlägt.
Bei Bedarf `TOTP_WINDOW` in `login_totp` erhöhen.

**SSH fordert ein Passwort statt eines TOTP-Codes an**
Überprüfen, ob `KbdInteractiveAuthentication yes` und
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` beide
in `/etc/ssh/sshd_config` vorhanden sind und der Benutzer in der Login-Klasse `totp`
ist (`doas usermod -L totp <user>`).

**sshd -t schlägt nach dem Bearbeiten von sshd_config fehl**
`doas sshd -t` ausführen und alle gemeldeten Fehler beheben, bevor sshd neu gestartet wird.
Das von `setup.sh` erstellte Backup befindet sich unter
`/etc/ssh/sshd_config.bak.<timestamp>`.

**Entfernter Syslog empfängt keine Meldungen**
1. Erreichbarkeit von UDP/TCP-Port 514 des entfernten Servers prüfen:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Firewall-Regeln auf beiden Seiten prüfen (OpenBSD pf und entfernter Server).
3. Bei TCP-Weiterleitung sicherstellen, dass `syslogd_flags="-T"` in
   `/etc/rc.conf.local` steht und `syslogd` neu gestartet wurde.

## Lizenz

BSD-2-Clause-Lizenz. Siehe [LICENSE](../LICENSE) für Details.
