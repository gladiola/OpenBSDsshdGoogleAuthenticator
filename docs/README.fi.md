# OpenBSD sshd + Google Authenticator (TOTP)

Kaksivaiheinen todennus OpenBSD SSH:lle käyttäen Google Authenticatoria
(TOTP), epäonnistuneiden kirjautumisyritysten lokitiedot välitetään etäsyslog-palvelimelle.

## Yleiskatsaus

Tämä repositorio tarjoaa:

| Tiedosto | Tarkoitus |
|------|---------|
| `setup.sh` | Automaattinen asennusskripti — aja kerran pääkäyttäjänä |
| `login_totp` | BSD Auth -taustajärjestelmä, joka tarkistaa TOTP-koodin |
| `google-authenticator-setup.sh` | Käyttäjäkohtainen rekisteröintiskripti |
| `sshd_config.snippet` | Viitteelliset sshd_config-lisäykset |
| `syslog.conf.snippet` | Viitteelliset syslog.conf-lisäykset etävälitystä varten |

### Todennusprosessi

```
SSH-asiakas
  │
  ▼
sshd  ──── 1. Julkisen avaimen todennus (olemassa oleva avainpari)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Kehote: "Google Authenticator code: "
  ├── 3. Käyttäjä syöttää 6-numeroisen TOTP-koodin sovelluksesta
  ├── 4. oathtool tarkistaa koodin tiedostoa ~/.google_authenticator vasten
  │
  ├─ ONNISTUI → istunto avattu; auth.info kirjattu paikallisesti + välitetty
  └─ EPÄONNISTUI → istunto suljettu; auth.warning kirjattu paikallisesti + välitetty
```

## Vaatimukset

- OpenBSD 7.x (testattu versioilla 7.4 ja 7.5)
- Pääkäyttäjän tai `doas`-oikeus
- `oath-toolkit`-paketti (`pkg_add oath-toolkit`) — tarjoaa `oathtool`-komennon
- Etäsyslog-palvelin, johon isäntä pystyy ottamaan yhteyden (rsyslog, syslog-ng jne.)
- Käyttäjillä täytyy olla SSH-julkinen avain asennettuna (`~/.ssh/authorized_keys`)

## Pikaohje (automaattinen)

```sh
doas sh setup.sh
```

Skripti suorittaa seuraavat toimet:

1. Asentaa `oath-toolkit`-paketin komennolla `pkg_add`.
2. Kopioi `login_totp`-tiedoston hakemistoon `/usr/local/libexec/auth/login_totp`.
3. Lisää `totp`-kirjautumisluokan tiedostoon `/etc/login.conf`.
4. Paikkaa tiedoston `/etc/ssh/sshd_config`.
5. Paikkaa tiedoston `/etc/syslog.conf` etävälityssäännöillä.
6. Käynnistää `syslogd`- ja `sshd`-palvelut uudelleen.
7. Ajaa valinnaisesti `google-authenticator-setup.sh`-skriptin käyttäjän rekisteröimiseksi.

## Manuaalinen asennus

### 1. Asenna oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Asenna BSD Auth -kirjautumiskripti

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Lisää `totp`-kirjautumisluokka

Lisää seuraava teksti tiedoston `/etc/login.conf` loppuun:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

Muodosta sitten login.conf-tietokanta uudelleen:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Määritä sshd

Lisää `sshd_config.snippet`-tiedoston rivit tiedostoon `/etc/ssh/sshd_config`.
Kriittiset direktiivit ovat:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Tarkista ja käynnistä sshd uudelleen:

```sh
doas sshd -t          # tarkista asetukset
doas rcctl restart sshd
```

### 5. Määritä etäsyslog

Lisää `syslog.conf.snippet`-tiedoston rivit tiedostoon `/etc/syslog.conf`,
korvaten `REMOTE_SYSLOG_SERVER` todellisella palvelimen osoitteella.

**UDP (oletus):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (luotettavampi):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

TCP-välitystä varten ota TCP käyttöön myös tiedostossa `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Lataa syslogd uudelleen:

```sh
doas rcctl restart syslogd
```

### 6. Rekisteröi käyttäjät

Aja käyttäjäkohtainen rekisteröintiskripti (pääkäyttäjänä tai käyttäjänä itse):

```sh
doas sh google-authenticator-setup.sh
```

Skripti suorittaa seuraavat toimet:
1. Luo satunnaisen 160-bittisen TOTP-salaisuuden.
2. Kirjoittaa sen tiedostoon `~/.google_authenticator` (oikeudet 0600).
3. Tulostaa `otpauth://`-URI:n ja terminaalin QR-koodin (jos `qrencode` on asennettu).
4. Liittää käyttäjän `totp`-kirjautumisluokkaan.

Skannaa QR-koodi (tai liitä URI) Google Authenticator-, Aegis-,
Authy- tai mihin tahansa TOTP-yhteensopivaan sovellukseen.

### 7. Liitä käyttäjät totp-kirjautumisluokkaan

Jos et käyttänyt `google-authenticator-setup.sh`-skriptiä, liitä luokka manuaalisesti:

```sh
doas usermod -L totp alice
```

## Asennuksen tarkistaminen

### Testaa oathtool paikallisesti

```sh
# Luo nykyinen TOTP-koodi käyttäjän salaisuudelle:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Vertaa tätä todentajasovelluksessa näkyvään koodiin — niiden pitäisi täsmätä.

### Testaa syslog-välitys

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Tarkista, että nämä viestit saapuvat etäsyslog-palvelimelle.

### Testaa SSH-kirjautuminen

Avaa **uusi** SSH-istunto (pidä nykyinen istunto auki siltä varalta, että
jotain täytyy korjata):

```sh
ssh -v alice@your-server
```

Odotettu toiminta:
1. sshd hyväksyy julkisen avaimesi.
2. Näet kehotteen: `Google Authenticator code: `
3. Syötä 6-numeroinen koodi todentajasovelluksesta.
4. Kirjautuminen onnistuu tai epäonnistuu; tulos näkyy tiedostossa `/var/log/authlog`
   ja etäsyslog-palvelimella.

## Epäonnistuneen kirjautumisen lokimuoto

Kun `login_totp` hylkää TOTP-koodin, se lähettää viestin `logger(1)`-komennon kautta:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Tämä viesti kirjoitetaan:
- Paikalliseen syslogiin (`/var/log/authlog` OpenBSD:ssä).
- Etäsyslog-palvelimelle `syslog.conf`-tiedoston `auth.info`-säännön kautta.

Sshd kirjaa myös lisäksi epäonnistuneita todennustapahtumia:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Tiedostoviite

### `login_totp` (BSD Auth -taustajärjestelmä)

- **Sijainti:** `/usr/local/libexec/auth/login_totp`
- **Oikeudet:** `root:auth 0550`
- **Salaisuustiedosto:** `~/.google_authenticator` (ensimmäinen rivi = base-32 TOTP-salaisuus)
- **Lokitus:** `logger -p auth.warning` epäonnistumisesta, `auth.info` onnistumisesta
- **Aikatoleranssi:** ±1 × 30 sekunnin askel (määritettävissä `TOTP_WINDOW`-muuttujalla)

### `~/.google_authenticator`

Pelkkätekstitiedosto; **ensimmäisen rivin** on oltava base-32 TOTP-salaisuus.
`login_totp` jättää huomiotta lisärivit (kommentit).

Esimerkki:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Oikeuksien on oltava `0600` ja omistajana täytyy olla käyttäjä itse.

## Erot FreeBSD:hen / PAM-pohjaisiin asennuksiin

| Aihe | FreeBSD | OpenBSD |
|-------|---------|---------|
| Todennuskehys | PAM (`pam_google_authenticator.so`) | BSD Auth (`login_totp`-skripti) |
| Kirjautumisluokka | ei ole | `/etc/login.conf` `totp`-luokka |
| Paketti | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Syslog-daemoni | `syslogd` / `newsyslog` | `syslogd` (sisäänrakennettu) |
| Etä-UDP-välitys | `@host` tiedostossa `syslog.conf` | `@host` tiedostossa `syslog.conf` |
| Etä-TCP-välitys | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Vianmääritys

**"oathtool not found"**
Asenna oath-toolkit: `doas pkg_add oath-toolkit`

**"No secret file for user"**
Aja `google-authenticator-setup.sh` kyseiselle käyttäjälle tai luo manuaalisesti
`~/.google_authenticator`-tiedosto, jonka ensimmäisellä rivillä on base-32-salaisuus.

**TOTP-koodit hylätään aina**
Varmista, että järjestelmän kello on synkronoitu (`ntpd` on oletuksena käytössä
OpenBSD:ssä). Yli 30 sekunnin kellonero aiheuttaa jokaisen koodin epäonnistumisen.
Kasvata tarvittaessa `TOTP_WINDOW`-arvoa tiedostossa `login_totp`.

**SSH pyytää salasanaa TOTP-koodin sijasta**
Tarkista, että sekä `KbdInteractiveAuthentication yes` että
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` ovat
tiedostossa `/etc/ssh/sshd_config`, ja että käyttäjä kuuluu `totp`-kirjautumisluokkaan
(`doas usermod -L totp <käyttäjä>`).

**sshd -t epäonnistuu sshd_config-muokkauksen jälkeen**
Aja `doas sshd -t` ja korjaa kaikki raportoidut virheet ennen sshd:n uudelleenkäynnistystä.
`setup.sh`-skriptin luoma varmuuskopio löytyy osoitteesta
`/etc/ssh/sshd_config.bak.<aikaleima>`.

**Etäsyslog ei vastaanota viestejä**
1. Varmista, että etäpalvelimen UDP/TCP-portti 514 on saavutettavissa:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Tarkista palomuurisäännöt molemmissa päissä (OpenBSD pf ja etäpalvelin).
3. TCP-välitystä varten varmista, että `syslogd_flags="-T"` on tiedostossa
   `/etc/rc.conf.local` ja että `syslogd` on käynnistetty uudelleen.

## Lisenssi

BSD 2-lausekkeen lisenssi. Katso tiedosto [LICENSE](LICENSE) lisätietoja varten.
