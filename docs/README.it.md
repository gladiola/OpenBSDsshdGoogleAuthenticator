# OpenBSD sshd + Google Authenticator (TOTP)

Autenticazione a due fattori per SSH su OpenBSD tramite Google Authenticator
(TOTP), con inoltro dei log di accesso fallito a un server syslog remoto.

## Panoramica

Questo repository fornisce:

| File | Scopo |
|------|-------|
| `setup.sh` | Script di configurazione automatizzata — da eseguire una volta come root |
| `login_totp` | Backend BSD Auth che verifica il codice TOTP |
| `google-authenticator-setup.sh` | Script di registrazione per singolo utente |
| `sshd_config.snippet` | Aggiunte di riferimento per sshd_config |
| `syslog.conf.snippet` | Aggiunte di riferimento per syslog.conf con inoltro remoto |

### Flusso di autenticazione

```
Client SSH
  │
  ▼
sshd  ──── 1. Autenticazione con chiave pubblica (coppia di chiavi esistente)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Richiesta: "Google Authenticator code: "
  ├── 3. L'utente inserisce il TOTP a 6 cifre dall'app
  ├── 4. oathtool verifica il codice contro ~/.google_authenticator
  │
  ├─ SUCCESSO → sessione aperta; auth.info registrato localmente + inoltrato
  └─ FALLIMENTO → sessione chiusa; auth.warning registrato localmente + inoltrato
```

## Requisiti

- OpenBSD 7.x (testato su 7.4 e 7.5)
- Accesso come root o tramite `doas`
- Pacchetto `oath-toolkit` (`pkg_add oath-toolkit`) — fornisce `oathtool`
- Un server syslog remoto raggiungibile dall'host (rsyslog, syslog-ng, ecc.)
- Gli utenti devono avere una chiave pubblica SSH già installata (`~/.ssh/authorized_keys`)

## Avvio rapido (automatizzato)

```sh
doas sh setup.sh
```

Lo script eseguirà le seguenti operazioni:

1. Installare `oath-toolkit` tramite `pkg_add`.
2. Copiare `login_totp` in `/usr/local/libexec/auth/login_totp`.
3. Aggiungere una classe di login `totp` a `/etc/login.conf`.
4. Modificare `/etc/ssh/sshd_config`.
5. Modificare `/etc/syslog.conf` con le regole di inoltro remoto.
6. Riavviare `syslogd` e `sshd`.
7. Eseguire opzionalmente `google-authenticator-setup.sh` per registrare un utente.

## Installazione manuale

### 1. Installare oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Installare lo script di login BSD Auth

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Aggiungere la classe di login `totp`

Aggiungere quanto segue alla fine di `/etc/login.conf`:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

Quindi ricostruire il database di login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Configurare sshd

Aggiungere le righe di `sshd_config.snippet` a `/etc/ssh/sshd_config`.
Le direttive essenziali sono:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Verificare e riavviare sshd:

```sh
doas sshd -t          # verificare la configurazione
doas rcctl restart sshd
```

### 5. Configurare il syslog remoto

Aggiungere le righe di `syslog.conf.snippet` a `/etc/syslog.conf`, sostituendo
`REMOTE_SYSLOG_SERVER` con l'indirizzo reale del server.

**UDP (predefinito):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (più affidabile):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Per TCP, abilitare anche TCP in `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Ricaricare syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Registrare gli utenti

Eseguire lo script di registrazione per singolo utente (come root o come l'utente stesso):

```sh
doas sh google-authenticator-setup.sh
```

Lo script:
1. Genera un segreto TOTP casuale da 160 bit.
2. Lo scrive in `~/.google_authenticator` (modalità 0600).
3. Stampa un URI `otpauth://` e un codice QR nel terminale (se `qrencode` è installato).
4. Assegna l'utente alla classe di login `totp`.

Scansionare il codice QR (o incollare l'URI) in Google Authenticator, Aegis,
Authy o qualsiasi app compatibile con TOTP.

### 7. Assegnare gli utenti alla classe di login totp

Se `google-authenticator-setup.sh` non è stato utilizzato, assegnare la classe manualmente:

```sh
doas usermod -L totp alice
```

## Verifica della configurazione

### Testare oathtool in locale

```sh
# Generare il codice TOTP attuale per il segreto di un utente:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Confrontare questo codice con quello mostrato nell'app di autenticazione — devono corrispondere.

### Testare l'inoltro syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Verificare che questi messaggi arrivino al server syslog remoto.

### Testare l'accesso SSH

Aprire una **nuova** sessione SSH (tenere aperta la sessione esistente nel caso in cui sia necessario correggere qualcosa):

```sh
ssh -v alice@your-server
```

Flusso atteso:
1. sshd accetta la chiave pubblica.
2. Compare la richiesta: `Google Authenticator code: `
3. Inserire il codice a 6 cifre dall'app di autenticazione.
4. L'accesso ha successo o fallisce; il risultato appare in `/var/log/authlog` e
   sul server syslog remoto.

## Formato dei log di accesso fallito

Quando `login_totp` rifiuta un codice TOTP, emette un messaggio tramite `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Questo messaggio viene scritto in:
- Il syslog locale (`/var/log/authlog` su OpenBSD).
- Il server syslog remoto tramite la regola `auth.info` in `syslog.conf`.

Altri eventi di autenticazione fallita vengono registrati direttamente da sshd:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Riferimento ai file

### `login_totp` (backend BSD Auth)

- **Posizione:** `/usr/local/libexec/auth/login_totp`
- **Permessi:** `root:auth 0550`
- **File segreto:** `~/.google_authenticator` (prima riga = segreto TOTP in base-32)
- **Registrazione:** `logger -p auth.warning` in caso di fallimento, `auth.info` in caso di successo
- **Tolleranza temporale:** ±1 × passo di 30 secondi (configurabile tramite `TOTP_WINDOW`)

### `~/.google_authenticator`

Un file di testo normale; la **prima riga** deve essere il segreto TOTP in base-32.
Le righe aggiuntive (commenti) vengono ignorate da `login_totp`.

Esempio:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

I permessi devono essere `0600`, di proprietà dell'utente.

## Differenze rispetto a FreeBSD / configurazioni basate su PAM

| Argomento | FreeBSD | OpenBSD |
|-----------|---------|---------|
| Framework di autenticazione | PAM (`pam_google_authenticator.so`) | BSD Auth (script `login_totp`) |
| Classe di login | n/a | Classe `totp` in `/etc/login.conf` |
| Pacchetto | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Daemon syslog | `syslogd` / `newsyslog` | `syslogd` (integrato) |
| Inoltro remoto UDP | `@host` in `syslog.conf` | `@host` in `syslog.conf` |
| Inoltro remoto TCP | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Risoluzione dei problemi

**"oathtool not found"**
Installare oath-toolkit: `doas pkg_add oath-toolkit`

**"No secret file for user"**
Eseguire `google-authenticator-setup.sh` per quell'utente, o creare manualmente
`~/.google_authenticator` con il segreto in base-32 nella prima riga.

**I codici TOTP vengono sempre rifiutati**
Assicurarsi che l'orologio di sistema sia sincronizzato (`ntpd` è abilitato su OpenBSD per
impostazione predefinita). Una differenza di orario superiore a 30 secondi farà fallire tutti i codici.
Aumentare `TOTP_WINDOW` in `login_totp` se necessario.

**SSH chiede una password invece di un codice TOTP**
Verificare che `KbdInteractiveAuthentication yes` e
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` siano entrambe
presenti in `/etc/ssh/sshd_config`, e che l'utente appartenga alla classe di login
`totp` (`doas usermod -L totp <user>`).

**sshd -t fallisce dopo aver modificato sshd_config**
Eseguire `doas sshd -t` e correggere tutti gli errori segnalati prima di riavviare sshd.
Il backup creato da `setup.sh` si trova in
`/etc/ssh/sshd_config.bak.<timestamp>`.

**Il syslog remoto non riceve i messaggi**
1. Confermare che la porta UDP/TCP 514 del server remoto sia raggiungibile:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Controllare le regole del firewall su entrambi i lati (OpenBSD pf e server remoto).
3. Per l'inoltro TCP, confermare che `syslogd_flags="-T"` sia presente in
   `/etc/rc.conf.local` e che `syslogd` sia stato riavviato.

## Licenza

Licenza BSD a 2 clausole. Vedere [LICENSE](../LICENSE) per i dettagli.
