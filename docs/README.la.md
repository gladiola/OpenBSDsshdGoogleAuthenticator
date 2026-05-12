# OpenBSD sshd + Google Authenticator (TOTP)

Autenticatio duplicis gradus pro OpenBSD SSH utens Google Authenticator
(TOTP), cum nuntio defectionis transmisso ad servitorem syslog remotum.

## Conspectus

Hoc repositorium praebet:

| Fasciculus | Munus |
|------------|-------|
| `setup.sh` | Scriptum institutionis automaticum — semel ut radix exsequendum |
| `login_totp` | Pars postica BSD Auth quae codicem TOTP probat |
| `google-authenticator-setup.sh` | Scriptum inscriptionis per usum singulorum |
| `sshd_config.snippet` | Additamenta exemplaria pro sshd_config |
| `syslog.conf.snippet` | Additamenta exemplaria pro syslog.conf ad transmissionem remotam |

### Fluxus authenticationis

```
Cliens SSH
  │
  ▼
sshd  ──── 1. Authenticatio per clavem publicam (par clavium existens)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Interrogatio: "Google Authenticator code: "
  ├── 3. Usor intrat codicem TOTP sex digitorum ex app
  ├── 4. oathtool codicem probat contra ~/.google_authenticator
  │
  ├─ SUCCESSUS → sessio aperta; auth.info scriptum localiter + transmissum
  └─ DEFECTUS → sessio clausa; auth.warning scriptum localiter + transmissum
```

## Requisita

- OpenBSD 7.x (probatum in 7.4 et 7.5)
- Accessus radici aut `doas`
- Fasciculum `oath-toolkit` (`pkg_add oath-toolkit`) — praebet `oathtool`
- Servitor syslog remotus ex hospite attingibilis (rsyslog, syslog-ng, etc.)
- Usores debent habere clavem publicam SSH iam institutam (`~/.ssh/authorized_keys`)

## Initium celere (automaticum)

```sh
doas sh setup.sh
```

Scriptum:

1. Installabit `oath-toolkit` per `pkg_add`.
2. Copiabit `login_totp` ad `/usr/local/libexec/auth/login_totp`.
3. Addet classem `totp` in `/etc/login.conf`.
4. Mutabit `/etc/ssh/sshd_config`.
5. Mutabit `/etc/syslog.conf` cum regulis transmissionis remotae.
6. Restartet `syslogd` et `sshd`.
7. Optio: exsequetur `google-authenticator-setup.sh` ad unum usorem inscribendum.

## Institutio manualis

### 1. Installa oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Installa scriptum BSD Auth

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Adde classem `totp`

Appende haec in `/etc/login.conf`:

```
# Classis TOTP (Google Authenticator)
totp:\
    :auth=-totp:\
    :tc=default:
```

Deinde instaurato basim datorum login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Configura sshd

Adde lineas ex `sshd_config.snippet` in `/etc/ssh/sshd_config`.
Directiva maximi momenti sunt:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Proba et sshd reinitiato:

```sh
doas sshd -t          # proba configurationem
doas rcctl restart sshd
```

### 5. Configura syslog remotum

Adde lineas ex `syslog.conf.snippet` in `/etc/syslog.conf`, substituendo
`REMOTE_SYSLOG_SERVER` cum vera inscriptione servitoris tui.

**UDP (praedefinitum):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (fidelius):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Pro TCP, etiam TCP in `/etc/rc.conf.local` enarreto:

```
syslogd_flags="-T"
```

Syslogd reinitiato:

```sh
doas rcctl restart syslogd
```

### 6. Inscribe usores

Exsequere scriptum inscriptionis per usorem (ut radix aut ut usor ipse):

```sh
doas sh google-authenticator-setup.sh
```

Scriptum:
1. Generat secretum TOTP fortuitum 160-bit.
2. Scribit illud in `~/.google_authenticator` (modus 0600).
3. Exprimit URI `otpauth://` et codicem QR in terminali (si `qrencode` installatum est).
4. Assignat usorem classi `totp`.

Legas codicem QR (aut inseras URI) in Google Authenticator, Aegis,
Authy, aut quamcumque app TOTP-compatibilem.

### 7. Assigna usores classi totp

Si non usus es `google-authenticator-setup.sh`, classem manu assigna:

```sh
doas usermod -L totp alice
```

## Probatio institutionis

### Proba oathtool localiter

```sh
# Genera codicem TOTP hodiernum pro secreto usoris:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Confer hoc cum codice qui in app authenticationis apparet — debent concordare.

### Proba transmissionem syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Verifica quod haec nuntia ad servitorem syslog remotum perveniunt.

### Proba accessum SSH

Aperi sessionem SSH **novam** (retine sessionem existentem apertam ne quid opus sit emendare):

```sh
ssh -v alice@your-server
```

Fluxus expectatus:
1. sshd clavem publicam tuam accipit.
2. Vides interrogationem: `Google Authenticator code: `
3. Intra codicem sex digitorum ex app authenticationis.
4. Accessus succedit aut deficit; eventus apparet in `/var/log/authlog` et
   in servitore syslog remoto.

## Forma nuntii de defectu accessus

Cum `login_totp` codicem TOTP recusat, nuntium per `logger(1)` emittit:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Hoc nuntium scribitur ad:
- Syslog locale (`/var/log/authlog` in OpenBSD).
- Servitorem syslog remotum per regulam `auth.info` in `syslog.conf`.

Eventus additi defectus authenticationis a sshd ipso scribentur:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Referentia fasciculorum

### `login_totp` (pars postica BSD Auth)

- **Locus:** `/usr/local/libexec/auth/login_totp`
- **Permissiones:** `root:auth 0550`
- **Fasciculus secreti:** `~/.google_authenticator` (prima linea = secretum TOTP base-32)
- **Scriptura:** `logger -p auth.warning` in defectu, `auth.info` in successu
- **Tolerantia temporis:** ±1 × gradus 30 secundarum (configurabile per `TOTP_WINDOW`)

### `~/.google_authenticator`

Fasciculus textus puri; **prima linea** esse debet secretum TOTP base-32.
Lineae additionis (annotationes) ignorantur a `login_totp`.

Exemplum:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Permissiones debent esse `0600`, possessio usoris.

## Differentiae a FreeBSD / institutionibus PAM-basatis

| Res | FreeBSD | OpenBSD |
|-----|---------|---------|
| Compages authenticationis | PAM (`pam_google_authenticator.so`) | BSD Auth (scriptum `login_totp`) |
| Classis accessus | non adhibetur | `/etc/login.conf` classis `totp` |
| Fasciculum | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Daemon syslog | `syslogd` / `newsyslog` | `syslogd` (integrum) |
| Transmissio UDP remota | `@host` in `syslog.conf` | `@host` in `syslog.conf` |
| Transmissio TCP remota | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Emendatio errorum

**«oathtool not found»**
Installa oath-toolkit: `doas pkg_add oath-toolkit`

**«No secret file for user»**
Exsequere `google-authenticator-setup.sh` pro illo usore, aut manu crea
`~/.google_authenticator` cum secreto base-32 in prima linea.

**Codices TOTP semper recusantur**
Certifica horologium systematis synchronizatum esse (`ntpd` in OpenBSD per
defectum activum est). Discrepantia horologii maior quam 30 secondae omnes codices
fallere faciet. Auge `TOTP_WINDOW` in `login_totp` si opus est.

**SSH tesseram petit pro codice TOTP**
Verifica quod `KbdInteractiveAuthentication yes` et
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` ambo
praesentes sunt in `/etc/ssh/sshd_config`, et quod usor in classe `totp` est
(`doas usermod -L totp <usor>`).

**sshd -t deficit post editionem sshd_config**
Exsequere `doas sshd -t` et corriges errores nuntiatos antequam sshd reinitietur.
Apographum creatum a `setup.sh` est in
`/etc/ssh/sshd_config.bak.<temporis_nota>`.

**Syslog remotum nuntia non accipit**
1. Confirma portum UDP/TCP 514 servitoris remoti attingibilem esse:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Inspice regulas ignis utrimque (OpenBSD pf et servitor remotus).
3. Pro transmissione TCP, confirma `syslogd_flags="-T"` esse in
   `/etc/rc.conf.local` et `syslogd` reinitiari.

## Licentia

Licentia BSD 2 clausularum. Vide [LICENSE](LICENSE) pro omnibus.
