# OpenBSD sshd + Google Authenticator (TOTP)

Otantifikasyon de-faktè pou OpenBSD SSH lè l sèvi avèk Google Authenticator
(TOTP), avèk konsiyasyon echèk koneksyon ki transfere sou yon sèvè syslog aleka.

## Apèsi jeneral

Depo sa a bay:

| Fichye | Objektif |
|--------|---------|
| `setup.sh` | Skrip konfigirasyon otomatik — egzekite yon sèl fwa kòm root |
| `login_totp` | Backend BSD Auth ki verifye kòd TOTP la |
| `google-authenticator-setup.sh` | Skrip enskripsyon pou chak itilizatè |
| `sshd_config.snippet` | Referans ajouman sshd_config |
| `syslog.conf.snippet` | Referans ajouman syslog.conf pou transfere aleka |

### Fliks otantifikasyon

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
  ├── 3. Itilizatè antre kòd TOTP 6 chif nan aplikasyon an
  ├── 4. oathtool verifye kòd la kont ~/.google_authenticator
  │
  ├─ SIKSÈ → sesyon ouvri; auth.info konsiye lokalman + transfere
  └─ ECHÈK → sesyon fèmen; auth.warning konsiye lokalman + transfere
```

## Kondisyon

- OpenBSD 7.x (teste sou 7.4 ak 7.5)
- Aksè Root oswa `doas`
- Pake `oath-toolkit` (`pkg_add oath-toolkit`) — bay `oathtool`
- Yon sèvè syslog aleka ki aksesib depi lame a (rsyslog, syslog-ng, elatriye)
- Itilizatè yo dwe genyen yon kle piblik SSH deja enstale (`~/.ssh/authorized_keys`)

## Demaraje rapid (otomatik)

```sh
doas sh setup.sh
```

Skrip la pral:

1. Enstale `oath-toolkit` via `pkg_add`.
2. Kopye `login_totp` nan `/usr/local/libexec/auth/login_totp`.
3. Ajoute yon klas koneksyon `totp` nan `/etc/login.conf`.
4. Korije `/etc/ssh/sshd_config`.
5. Korije `/etc/syslog.conf` avèk règ transfere aleka.
6. Redémarre `syslogd` ak `sshd`.
7. Opsyonèlman egzekite `google-authenticator-setup.sh` pou enskripsyon yon itilizatè.

## Enstalasyon manyèl

### 1. Enstale oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Enstale skrip koneksyon BSD Auth la

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Ajoute klas koneksyon `totp` la

Ajoute sa ki anba a nan `/etc/login.conf`:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

Apre sa rekonstrwi baz done login.conf la:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Konfigire sshd

Ajoute liy yo soti nan `sshd_config.snippet` nan `/etc/ssh/sshd_config`.
Direktiv kritik yo se:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Verifye epi redémarre sshd:

```sh
doas sshd -t          # verifye konfigirasyon
doas rcctl restart sshd
```

### 5. Konfigire syslog aleka

Ajoute liy yo soti nan `syslog.conf.snippet` nan `/etc/syslog.conf`, ranplase
`REMOTE_SYSLOG_SERVER` avèk adrès sèvè reyèl ou a.

**UDP (pa defo):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (pi fyab):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Pou TCP, aktive tou TCP nan `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Rechaje syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Enskri itilizatè yo

Egzekite skrip enskripsyon pou chak itilizatè (kòm root oswa kòm itilizatè li menm):

```sh
doas sh google-authenticator-setup.sh
```

Skrip la:
1. Jenere yon sekrè TOTP 160-bit alakou.
2. Ekri li nan `~/.google_authenticator` (mòd 0600).
3. Enprime yon URI `otpauth://` ak yon kòd QR nan tèminal (si `qrencode` enstale).
4. Asiyen itilizatè a nan klas koneksyon `totp` la.

Eskane kòd QR la (oswa kole URI a) nan Google Authenticator, Aegis,
Authy, oswa nenpòt aplikasyon ki konpatib avèk TOTP.

### 7. Asiyen itilizatè yo nan klas koneksyon totp la

Si ou pa t itilize `google-authenticator-setup.sh`, asiyen klas la manyèlman:

```sh
doas usermod -L totp alice
```

## Verifye konfigirasyon an

### Teste oathtool lokalman

```sh
# Jenere kòd TOTP aktyèl pou sekrè yon itilizatè:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Konpare sa a avèk kòd ki montre nan aplikasyon otantifikatè a — yo dwe matche.

### Teste transfere syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Verifye ke mesaj sa yo rive sou sèvè syslog aleka a.

### Teste koneksyon SSH

Ouvri yon **nouvo** sesyon SSH (kenbe sesyon aktyèl ou a ouvri nan ka
yon bagay bezwen korije):

```sh
ssh -v alice@your-server
```

Fliks espere:
1. sshd aksepte kle piblik ou a.
2. Ou wè pwonpt la: `Google Authenticator code: `
3. Antre kòd 6 chif soti nan aplikasyon otantifikatè a.
4. Koneksyon reyisi oswa echwe; rezilta a parèt nan `/var/log/authlog` ak
   sou sèvè syslog aleka a.

## Fòma konsiyasyon echèk koneksyon

Lè `login_totp` rejte yon kòd TOTP, li emèt yon mesaj via `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Mesaj sa a ekri nan:
- Syslog lokal la (`/var/log/authlog` sou OpenBSD).
- Sèvè syslog aleka a via règ `auth.info` nan `syslog.conf`.

Evènman echèk otantifikasyon adisyonèl yo konsiye pa sshd li menm:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Referans fichye

### `login_totp` (Backend BSD Auth)

- **Kote:** `/usr/local/libexec/auth/login_totp`
- **Pèmisyon:** `root:auth 0550`
- **Fichye sekrè:** `~/.google_authenticator` (premye liy = sekrè TOTP base-32)
- **Konsiyasyon:** `logger -p auth.warning` sou echèk, `auth.info` sou siksè
- **Tolerans tan:** ±1 × etap 30-segond (konfigirab via `TOTP_WINDOW`)

### `~/.google_authenticator`

Yon fichye tèks senp; **premye liy** la dwe se sekrè TOTP base-32 la.
Liy adisyonèl (kòmantè) yo inyore pa `login_totp`.

Egzanp:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Pèmisyon yo dwe `0600`, pwopriyete itilizatè a.

## Diferans ak FreeBSD / konfigirasyon ki baze sou PAM

| Sijè | FreeBSD | OpenBSD |
|------|---------|---------|
| Kad otantifikasyon | PAM (`pam_google_authenticator.so`) | BSD Auth (skrip `login_totp`) |
| Klas koneksyon | s.o. | Klas `totp` nan `/etc/login.conf` |
| Pake | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Demòn syslog | `syslogd` / `newsyslog` | `syslogd` (entegre) |
| Transfere UDP aleka | `@host` nan `syslog.conf` | `@host` nan `syslog.conf` |
| Transfere TCP aleka | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Depannaj

**"oathtool not found"**
Enstale oath-toolkit: `doas pkg_add oath-toolkit`

**"No secret file for user"**
Egzekite `google-authenticator-setup.sh` pou itilizatè sa a, oswa kreye manyèlman
`~/.google_authenticator` avèk sekrè base-32 la sou premye liy lan.

**Kòd TOTP toujou rejte**
Asire w ke lòj sistèm nan senkronize (`ntpd` aktive sou OpenBSD pa
defo). Yon dekaje lòj plis pase 30 segond pral koze chak kòd echwe.
Ogmante `TOTP_WINDOW` nan `login_totp` si nesesè.

**SSH mande yon modpas olye de yon kòd TOTP**
Verifye ke `KbdInteractiveAuthentication yes` ak
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` tou de
prezan nan `/etc/ssh/sshd_config`, epi ke itilizatè a nan klas koneksyon `totp`
(`doas usermod -L totp <user>`).

**sshd -t echwe apre modifikasyon sshd_config**
Egzekite `doas sshd -t` epi korije tout erè rapòte anvan redémarre sshd.
Sòvgad ki kreye pa `setup.sh` la nan
`/etc/ssh/sshd_config.bak.<timestamp>`.

**Syslog aleka pa resevwa mesaj yo**
1. Konfime pò UDP/TCP 514 sèvè aleka a aksesib:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Verifye règ pare-fè sou tou de bò yo (OpenBSD pf ak sèvè aleka).
3. Pou transfere TCP, konfime `syslogd_flags="-T"` nan
   `/etc/rc.conf.local` epi `syslogd` redémarre.

## Lisans

Lisans BSD 2-Clause. Gade [LICENSE](LICENSE) pou detay.
