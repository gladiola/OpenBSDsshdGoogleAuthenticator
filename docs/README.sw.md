# OpenBSD sshd + Google Authenticator (TOTP)

Uthibitishaji wa hatua mbili kwa OpenBSD SSH ukitumia Google Authenticator
(TOTP), pamoja na kupeleka kumbukumbu za kuingia zilizoshindwa kwa seva ya
syslog ya mbali.

## Muhtasari

Hazina hii inakupa:

| Faili | Madhumuni |
|------|---------|
| `setup.sh` | Hati-andishi ya usanidi wa kiotomatiki — endesha mara moja kama root |
| `login_totp` | Msingi wa BSD Auth unaothibitisha msimbo wa TOTP |
| `google-authenticator-setup.sh` | Hati-andishi ya usajili kwa kila mtumiaji |
| `sshd_config.snippet` | Nyongeza za sshd_config za kumbukumbu |
| `syslog.conf.snippet` | Nyongeza za syslog.conf za kumbukumbu kwa upelekaji wa mbali |

### Mtiririko wa Uthibitishaji

```
SSH client
  │
  ▼
sshd  ──── 1. Uthibitishaji wa funguo ya umma (jozi ya funguo iliyopo)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Ombi: "Google Authenticator code: "
  ├── 3. Mtumiaji anaweka msimbo wa TOTP wa tarakimu 6 kutoka kwa programu
  ├── 4. oathtool inathibitisha msimbo dhidi ya ~/.google_authenticator
  │
  ├─ MAFANIKIO → kipindi kimefunguliwa; auth.info imerekodiwa mahali + kupelekwa
  └─ KUSHINDWA → kipindi kimefungwa; auth.warning imerekodiwa mahali + kupelekwa
```

## Mahitaji

- OpenBSD 7.x (imejaribiwa kwenye 7.4 na 7.5)
- Ufikiaji wa root au `doas`
- Kifurushi cha `oath-toolkit` (`pkg_add oath-toolkit`) — kinachotoa `oathtool`
- Seva ya syslog ya mbali inayofikiwa kutoka kwa mwenyeji (rsyslog, syslog-ng, n.k.)
- Watumiaji lazima wawe na funguo ya umma ya SSH iliyosanikishwa tayari (`~/.ssh/authorized_keys`)

## Kuanza Haraka (Kiotomatiki)

```sh
doas sh setup.sh
```

Hati-andishi itafanya:

1. Kusanikisha `oath-toolkit` kupitia `pkg_add`.
2. Kunakili `login_totp` hadi `/usr/local/libexec/auth/login_totp`.
3. Kuongeza darasa la kuingia `totp` kwenye `/etc/login.conf`.
4. Kurekebisha `/etc/ssh/sshd_config`.
5. Kurekebisha `/etc/syslog.conf` na sheria za upelekaji wa mbali.
6. Kuanzisha upya `syslogd` na `sshd`.
7. Kuendesha `google-authenticator-setup.sh` ikibidi kusajili mtumiaji.

## Usakinishaji wa Mkono

### 1. Sakinisha oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Sakinisha Hati-andishi ya Kuingia BSD Auth

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Ongeza Darasa la Kuingia `totp`

Ambatanisha yafuatayo kwenye `/etc/login.conf`:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

Kisha jenga upya hifadhidata ya login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Sanidi sshd

Ongeza mistari kutoka `sshd_config.snippet` hadi `/etc/ssh/sshd_config`.
Maelekezo muhimu ni:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Thibitisha na uanzishe upya sshd:

```sh
doas sshd -t          # thibitisha usanidi
doas rcctl restart sshd
```

### 5. Sanidi Syslog ya Mbali

Ongeza mistari kutoka `syslog.conf.snippet` hadi `/etc/syslog.conf`, ukibadilisha
`REMOTE_SYSLOG_SERVER` na anwani halisi ya seva yako.

**UDP (chaguo-msingi):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (ya kutegemewa zaidi):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Kwa TCP, pia wezesha TCP katika `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Pakia upya syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Sajili Watumiaji

Endesha hati-andishi ya usajili kwa kila mtumiaji (kama root au mtumiaji mwenyewe):

```sh
doas sh google-authenticator-setup.sh
```

Hati-andishi:
1. Inazalisha siri ya TOTP ya nasibu ya biti 160.
2. Inaandika kwenye `~/.google_authenticator` (hali 0600).
3. Inachapisha URI ya `otpauth://` na msimbo wa QR wa terminal (ikiwa `qrencode` imesanikishwa).
4. Inampanga mtumiaji katika darasa la kuingia `totp`.

Changanua msimbo wa QR (au bandika URI) kwenye Google Authenticator, Aegis,
Authy, au programu yoyote inayooana na TOTP.

### 7. Panga Watumiaji kwa Darasa la Kuingia totp

Ikiwa hukutumia `google-authenticator-setup.sh`, panga darasa kwa mkono:

```sh
doas usermod -L totp alice
```

## Kuthibitisha Usanidi

### Jaribu oathtool Mahali

```sh
# Zalisha msimbo wa TOTP wa sasa kwa siri ya mtumiaji:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Linganisha hii na msimbo unaoonyeshwa katika programu ya uthibitishaji — zinapaswa kulingana.

### Jaribu Upelekaji wa Syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Angalia kwamba ujumbe huu unafika kwenye seva ya syslog ya mbali.

### Jaribu Kuingia kwa SSH

Fungua kipindi cha SSH **kipya** (weka kipindi chako kilichopo wazi ikiwa
kitu kinahitaji kutengenezwa):

```sh
ssh -v alice@your-server
```

Mtiririko unaotarajiwa:
1. sshd inakubali funguo yako ya umma.
2. Unaona ombi: `Google Authenticator code: `
3. Weka msimbo wa tarakimu 6 kutoka kwa programu ya uthibitishaji.
4. Kuingia kunafaulu au kushindwa; matokeo yanaonekana katika `/var/log/authlog` na
   kwenye seva ya syslog ya mbali.

## Muundo wa Kumbukumbu za Kuingia Zilizoshindwa

Wakati `login_totp` inakataa msimbo wa TOTP, inatoa ujumbe kupitia `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Ujumbe huu unaandikwa kwenye:
- Syslog ya mahali (`/var/log/authlog` kwenye OpenBSD).
- Seva ya syslog ya mbali kupitia sheria ya `auth.info` katika `syslog.conf`.

Matukio ya ziada ya uthibitishaji uliyoshindwa yanarekodwa na sshd yenyewe:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Kumbukumbu ya Faili

### `login_totp` (Msingi wa BSD Auth)

- **Mahali:** `/usr/local/libexec/auth/login_totp`
- **Ruhusa:** `root:auth 0550`
- **Faili la siri:** `~/.google_authenticator` (mstari wa kwanza = siri ya TOTP ya base-32)
- **Urekodi:** `logger -p auth.warning` wakati wa kushindwa, `auth.info` wakati wa mafanikio
- **Uvumilivu wa wakati:** ±1 × hatua ya sekunde 30 (inaweza kusanidiwa kupitia `TOTP_WINDOW`)

### `~/.google_authenticator`

Faili la maandishi wazi; **mstari wa kwanza** lazima uwe siri ya TOTP ya base-32.
Mistari ya ziada (maoni) inaporomoshwa na `login_totp`.

Mfano:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Ruhusa lazima ziwe `0600`, inayomilikiwa na mtumiaji.

## Tofauti na Usanidi wa FreeBSD / PAM

| Mada | FreeBSD | OpenBSD |
|-------|---------|---------|
| Mfumo wa uthibitishaji | PAM (`pam_google_authenticator.so`) | BSD Auth (hati-andishi ya `login_totp`) |
| Darasa la kuingia | haijalishi | Darasa la `totp` la `/etc/login.conf` |
| Kifurushi | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Daemon ya syslog | `syslogd` / `newsyslog` | `syslogd` (iliyojengwa ndani) |
| Upelekaji wa UDP wa mbali | `@host` katika `syslog.conf` | `@host` katika `syslog.conf` |
| Upelekaji wa TCP wa mbali | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Utatuzi wa Matatizo

**"oathtool not found"**
Sakinisha oath-toolkit: `doas pkg_add oath-toolkit`

**"No secret file for user"**
Endesha `google-authenticator-setup.sh` kwa mtumiaji huyo, au unda kwa mkono
`~/.google_authenticator` na siri ya base-32 kwenye mstari wa kwanza.

**Misimbo ya TOTP daima inakataliwa**
Hakikisha saa ya mfumo imesawazishwa (`ntpd` imewezeshwa kwenye OpenBSD kwa
chaguo-msingi). Tofauti ya saa ya zaidi ya sekunde 30 itasababisha kila msimbo
kushindwa. Ongeza `TOTP_WINDOW` katika `login_totp` ikiwa inahitajika.

**SSH inauliza nenosiri badala ya msimbo wa TOTP**
Thibitisha kwamba `KbdInteractiveAuthentication yes` na
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` zote mbili
zipo katika `/etc/ssh/sshd_config`, na kwamba mtumiaji yuko katika darasa la
kuingia `totp` (`doas usermod -L totp <user>`).

**sshd -t inashindwa baada ya kuhariri sshd_config**
Endesha `doas sshd -t` na urekebisha makosa yoyote yaliyoripotiwa kabla ya
kuanzisha upya sshd. Nakala rudufu iliyoundwa na `setup.sh` ipo kwenye
`/etc/ssh/sshd_config.bak.<timestamp>`.

**Syslog ya mbali haipokei ujumbe**
1. Thibitisha kwamba bandari ya UDP/TCP 514 ya seva ya mbali inafikiwa:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Angalia sheria za ukuta wa moto pande zote mbili (OpenBSD pf na seva ya mbali).
3. Kwa upelekaji wa TCP, thibitisha kwamba `syslogd_flags="-T"` ipo katika
   `/etc/rc.conf.local` na kwamba `syslogd` imeanzishwa upya.

## Leseni

Leseni ya BSD 2-Clause. Angalia [LICENSE](LICENSE) kwa maelezo.
