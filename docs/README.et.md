# OpenBSD sshd + Google Authenticator (TOTP)

Kahefaktoriline autentimine OpenBSD SSH jaoks Google Authenticatori
(TOTP) abil, ebaõnnestunud sisselogimiste logid edastatakse kaugsyslog-serverile.

## Ülevaade

See repositoorium pakub:

| Fail | Eesmärk |
|------|---------|
| `setup.sh` | Automaatne seadistusskript — käivita üks kord root-kasutajana |
| `login_totp` | BSD Auth taustaprogramm, mis kontrollib TOTP-koodi |
| `google-authenticator-setup.sh` | Kasutajapõhine registreerimisskript |
| `sshd_config.snippet` | Viite-sshd_config lisandused |
| `syslog.conf.snippet` | Viite-syslog.conf lisandused kaugväljandusteks |

### Autentimisprotsess

```
SSH klient
  │
  ▼
sshd  ──── 1. Avaliku võtme autentimine (olemasolev võtmepaar)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Viip: "Google Authenticator code: "
  ├── 3. Kasutaja sisestab rakendusest 6-kohalise TOTP-koodi
  ├── 4. oathtool kontrollib koodi faili ~/.google_authenticator vastu
  │
  ├─ ÕNNESTUS → seanss avati; auth.info logiti kohalikult + edastati
  └─ EBAÕNNESTUS → seanss suleti; auth.warning logiti kohalikult + edastati
```

## Nõuded

- OpenBSD 7.x (testitud versioonidel 7.4 ja 7.5)
- Root- või `doas`-juurdepääs
- `oath-toolkit` pakett (`pkg_add oath-toolkit`) — pakub `oathtool`
- Hostist ligipääsetav kaugsyslog-server (rsyslog, syslog-ng jne.)
- Kasutajatel peab olema SSH avalik võti juba paigaldatud (`~/.ssh/authorized_keys`)

## Kiirjuhend (automaatne)

```sh
doas sh setup.sh
```

Skript teeb järgmist:

1. Paigaldab `oath-toolkit` käsuga `pkg_add`.
2. Kopeerib `login_totp` asukohta `/usr/local/libexec/auth/login_totp`.
3. Lisab `totp` sisselogimisklassi faili `/etc/login.conf`.
4. Paigaldab plaastreid faili `/etc/ssh/sshd_config`.
5. Paigaldab plaastreid faili `/etc/syslog.conf` kaugväljanduseeskirjadega.
6. Taaskäivitab `syslogd` ja `sshd`.
7. Käivitab valikuliselt `google-authenticator-setup.sh` kasutaja registreerimiseks.

## Käsitsi paigaldamine

### 1. Paigalda oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Paigalda BSD Auth sisselogimisskript

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Lisa `totp` sisselogimisklass

Lisa järgnev tekst faili `/etc/login.conf` lõppu:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

Seejärel ehita login.conf andmebaas uuesti üles:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Seadista sshd

Lisa `sshd_config.snippet` read faili `/etc/ssh/sshd_config`.
Kriitilised direktiivid on:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Kontrolli ja taaskäivita sshd:

```sh
doas sshd -t          # kontrolli konfiguratsiooni
doas rcctl restart sshd
```

### 5. Seadista kaugsyslog

Lisa `syslog.conf.snippet` read faili `/etc/syslog.conf`, asendades
`REMOTE_SYSLOG_SERVER` oma tegeliku serveri aadressiga.

**UDP (vaikimisi):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (usaldusväärsem):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

TCP jaoks luba TCP ka failis `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Laadi syslogd uuesti:

```sh
doas rcctl restart syslogd
```

### 6. Registreeri kasutajad

Käivita kasutajapõhine registreerimisskript (root-kasutajana või kasutajana ise):

```sh
doas sh google-authenticator-setup.sh
```

Skript:
1. Genereerib juhusliku 160-bitise TOTP-saladuse.
2. Kirjutab selle faili `~/.google_authenticator` (õigused 0600).
3. Prindib `otpauth://` URI ja terminali QR-koodi (kui `qrencode` on paigaldatud).
4. Määrab kasutaja `totp` sisselogimisklassi.

Skanni QR-kood (või kleebi URI) Google Authenticatori, Aegise,
Authy või mõnda muusse TOTP-ühilduvasse rakendusse.

### 7. Määra kasutajad totp sisselogimisklassi

Kui sa ei kasutanud `google-authenticator-setup.sh`, määra klass käsitsi:

```sh
doas usermod -L totp alice
```

## Seadistuse kontrollimine

### Testi oathtool kohalikult

```sh
# Genereeri kasutaja saladuse põhjal praegune TOTP-kood:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Võrdle seda autentimisrakenduses näidatava koodiga — need peaksid ühtima.

### Testi syslog-edastust

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Kontrolli, kas need sõnumid jõuavad kaugsyslog-serverile.

### Testi SSH sisselogimist

Ava **uus** SSH-seanss (hoia olemasolev seanss avatud juhuks, kui
midagi vajab parandamist):

```sh
ssh -v alice@your-server
```

Oodatav kulg:
1. sshd aktsepteerib sinu avaliku võtme.
2. Näed viipi: `Google Authenticator code: `
3. Sisesta autentimisrakendusest 6-kohaline kood.
4. Sisselogimine õnnestub või ebaõnnestub; tulemus ilmub failis `/var/log/authlog`
   ja kaugsyslog-serveril.

## Ebaõnnestunud sisselogimise logiformaat

Kui `login_totp` lükkab TOTP-koodi tagasi, saadab ta sõnumi käsu `logger(1)` kaudu:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

See sõnum kirjutatakse:
- Kohalikku syslogisse (`/var/log/authlog` OpenBSD-s).
- Kaugsyslog-serverile `syslog.conf` faili `auth.info` eeskirja kaudu.

Lisaks logib sshd ise täiendavaid ebaõnnestunud autentimissündmusi:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Failide viide

### `login_totp` (BSD Auth taustaprogramm)

- **Asukoht:** `/usr/local/libexec/auth/login_totp`
- **Õigused:** `root:auth 0550`
- **Saladusefail:** `~/.google_authenticator` (esimene rida = base-32 TOTP-saladus)
- **Logimine:** `logger -p auth.warning` ebaõnnestumisel, `auth.info` õnnestumisel
- **Ajataluvus:** ±1 × 30-sekundiline samm (seadistatav `TOTP_WINDOW` kaudu)

### `~/.google_authenticator`

Lihttekstifail; **esimene rida** peab olema base-32 TOTP-saladus.
`login_totp` eirab lisaridu (kommentaare).

Näide:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Õigused peavad olema `0600` ja omanikuks peab olema kasutaja ise.

## Erinevused FreeBSD / PAM-põhistest seadistustest

| Teema | FreeBSD | OpenBSD |
|-------|---------|---------|
| Autentimisraamistik | PAM (`pam_google_authenticator.so`) | BSD Auth (`login_totp` skript) |
| Sisselogimisklass | puudub | `/etc/login.conf` `totp` klass |
| Pakett | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Syslog-deemon | `syslogd` / `newsyslog` | `syslogd` (sisseehitatud) |
| Kaug-UDP-edastus | `@host` failis `syslog.conf` | `@host` failis `syslog.conf` |
| Kaug-TCP-edastus | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Tõrkeotsing

**"oathtool not found"**
Paigalda oath-toolkit: `doas pkg_add oath-toolkit`

**"No secret file for user"**
Käivita `google-authenticator-setup.sh` selle kasutaja jaoks või loo käsitsi
`~/.google_authenticator` fail, mille esimesel real on base-32 saladus.

**TOTP-koodid lükatakse alati tagasi**
Veendu, et süsteemikell on sünkroonitud (`ntpd` on OpenBSD-s vaikimisi lubatud).
Rohkem kui 30-sekundiline kellaviga põhjustab iga koodi ebaõnnestumise.
Vajaduse korral suurenda `TOTP_WINDOW` väärtust failis `login_totp`.

**SSH küsib parooli TOTP-koodi asemel**
Kontrolli, et nii `KbdInteractiveAuthentication yes` kui ka
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` oleksid
failis `/etc/ssh/sshd_config`, ning et kasutaja kuuluks `totp` sisselogimisklassi
(`doas usermod -L totp <kasutaja>`).

**sshd -t ebaõnnestub pärast sshd_config muutmist**
Käivita `doas sshd -t` ja paranda kõik teatatud vead enne sshd taaskäivitamist.
`setup.sh` loodud varukoopia asub aadressil
`/etc/ssh/sshd_config.bak.<ajatempel>`.

**Kaugsyslog ei saa sõnumeid**
1. Kinnita, et kaug-serveri UDP/TCP port 514 on ligipääsetav:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Kontrolli tulemüüri reegleid mõlemas otsas (OpenBSD pf ja kaugserver).
3. TCP-edastuse jaoks veendu, et `syslogd_flags="-T"` on failis
   `/etc/rc.conf.local` ja `syslogd` on taaskäivitatud.

## Litsents

BSD 2-klausli litsents. Vaata üksikasju failist [LICENSE](LICENSE).
