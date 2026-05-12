# OpenBSD sshd + Google Authenticator (TOTP)

Whakamana rua-taumata mō te OpenBSD SSH mā te whakamahi i te Google Authenticator
(TOTP), me te tuku o ngā kōrero takahi tūāhanga ki tētahi tūmau syslog mamao.

## Tirohanga Whānui

Ko tēnei pūnaha e tuku ana:

| Kōnae | Tikanga |
|-------|---------|
| `setup.sh` | Hōtaka tautū aunoa — whakahaeretia kotahi noa iho hei kaiwhakahaere |
| `login_totp` | Tuarā BSD Auth e whakamana ana i te waehere TOTP |
| `google-authenticator-setup.sh` | Hōtaka rēhitatanga mō ia kaiwhakamahi |
| `sshd_config.snippet` | Āpitihanga tauira mō sshd_config |
| `syslog.conf.snippet` | Āpitihanga tauira mō syslog.conf mō te tukuiho mamao |

### Rerenga Whakamana

```
Kiritaki SSH
  │
  ▼
sshd  ──── 1. Whakamana mātāpuoro tūmatiti (ōrite kī o nāianei)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Pātai: "Google Authenticator code: "
  ├── 3. Ka tāuruuru te kaiwhakamahi i te tau TOTP 6-mati mai i te tono
  ├── 4. Ka whakamana oathtool i te waehere ki te ~/.google_authenticator
  │
  ├─ ANGITU → kua tuwhera te wā kōrero; auth.info tuhia ā-rohe + tukuiho
  └─ HAPA → kua katia te wā kōrero; auth.warning tuhia ā-rohe + tukuiho
```

## Ngā Herenga

- OpenBSD 7.x (whakamātauria i runga i 7.4 me 7.5)
- Urunga root, kaore ianei `doas`
- Pakeha `oath-toolkit` (`pkg_add oath-toolkit`) — e tuku ana i `oathtool`
- He tūmau syslog mamao ka taea te tae atu mai i te rangatira (rsyslog, syslog-ng, aha atu)
- Me whai ngā kaiwhakamahi i tētahi mātāpuoro tūmatiti SSH kua tāpiritia (`~/.ssh/authorized_keys`)

## Tīmatanga Tere (aunoa)

```sh
doas sh setup.sh
```

Ka mahi te hōtaka:

1. Tāpiritia `oath-toolkit` mā `pkg_add`.
2. Tāruatia `login_totp` ki `/usr/local/libexec/auth/login_totp`.
3. Tāpiritia he akomanga takiuru `totp` ki `/etc/login.conf`.
4. Waihoa `/etc/ssh/sshd_config`.
5. Waihoa `/etc/syslog.conf` me ngā ture tukuiho mamao.
6. Whakahoutia `syslogd` me `sshd`.
7. Whakahaeretia `google-authenticator-setup.sh` (ā-kōwhiri) ki te rēhita kaiwhakamahi.

## Tāpiritanga ā-Ringa

### 1. Tāpirihia te oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Tāpirihia te hōtaka takiuru BSD Auth

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Tāpirihia te akomanga takiuru `totp`

Tāpirihia ēnei ki `/etc/login.conf`:

```
# Akomanga takiuru TOTP (Google Authenticator)
totp:\
    :auth=-totp:\
    :tc=default:
```

Nā, hanga anō i te pātengi raraunga login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Whakaaetia te sshd

Tāpirihia ngā rārangi mai i `sshd_config.snippet` ki `/etc/ssh/sshd_config`.
Ko ngā tohutohu matua:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Whakamana me te whakahoutia te sshd:

```sh
doas sshd -t          # whakamana tautuhinga
doas rcctl restart sshd
```

### 5. Whakaaetia te syslog mamao

Tāpirihia ngā rārangi mai i `syslog.conf.snippet` ki `/etc/syslog.conf`, me te
whakaanohi i `REMOTE_SYSLOG_SERVER` ki tō wāhitau tūmau ake.

**UDP (taunoa):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (haumaru ake):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Mō TCP, whakahoahoa anō TCP i `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Uta anō i te syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Rēhita Kaiwhakamahi

Whakahaeretia te hōtaka rēhita mō ia kaiwhakamahi (hei kaiwhakahaere, hei kaiwhakamahi rānei):

```sh
doas sh google-authenticator-setup.sh
```

Ko te hōtaka:
1. Ka hanga he mea huna TOTP matapōkere 160-ngota.
2. Ka tuhia ki `~/.google_authenticator` (āhua 0600).
3. Ka tāia he URI `otpauth://` me he waehere QR termianla (mēnā kua tāpiritia `qrencode`).
4. Ka tohua te kaiwhakamahi ki te akomanga takiuru `totp`.

Pānuihia te waehere QR (tāruatia rānei te URI) ki Google Authenticator, Aegis,
Authy, ki tētahi tono TOTP-ōrite rānei.

### 7. Tohua ngā Kaiwhakamahi ki te Akomanga Takiuru totp

Mēnā kāore i whakamahia `google-authenticator-setup.sh`, tohua te akomanga ā-ringa:

```sh
doas usermod -L totp alice
```

## Whakamana i te Tautuhinga

### Whakamātau i te oathtool ā-rohe

```sh
# Hangaia te waehere TOTP o nāianei mō te mea huna a tētahi kaiwhakamahi:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Whakaritea tēnei ki te waehere e whakaaturia ana i roto i te tono whakamana — me ōrite.

### Whakamātau i te tukuiho syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Tirohia kia tae atu ēnei karere ki te tūmau syslog mamao.

### Whakamātau i te Takiuru SSH

Tuwhera i tētahi wā kōrero SSH **hou** (pupuri tō wā kōrero o nāianei tuwhera i
te wā ka hiahiatia he whakatika):

```sh
ssh -v alice@your-server
```

Ko te rerenga e tūmanakohia ana:
1. Ka whakaaetia e sshd tō mātāpuoro tūmatiti.
2. Ka kite koe i te pātai: `Google Authenticator code: `
3. Tāuruuru i te waehere 6-mati mai i te tono whakamana.
4. Ka angitu, ka hapa rānei te takiuru; ka puta te hua ki `/var/log/authlog` me
   ki te tūmau syslog mamao.

## Hanga Kōrero Takiuru Hapa

Ka whakakahore `login_totp` i tētahi waehere TOTP, ka tukuna he karere mā `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Ka tuhia tēnei karere ki:
- Te syslog ā-rohe (`/var/log/authlog` i runga i OpenBSD).
- Te tūmau syslog mamao mā te ture `auth.info` i `syslog.conf`.

Ka tuhia anō e sshd ake ōna āhuatanga hapa whakamana:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Tohutoro Kōnae

### `login_totp` (tuarā BSD Auth)

- **Wāhi:** `/usr/local/libexec/auth/login_totp`
- **Ngā Whakaaetanga:** `root:auth 0550`
- **Kōnae mea huna:** `~/.google_authenticator` (rārangi tuatahi = mea huna TOTP base-32)
- **Tuhituhi:** `logger -p auth.warning` i te hapa, `auth.info` i te angitu
- **Manawanui wā:** ±1 × takahanga 30-hēkona (ka taea te tautuhia mā `TOTP_WINDOW`)

### `~/.google_authenticator`

He kōnae kuputuhi māmā; ko te **rārangi tuatahi** me mau ki te mea huna TOTP base-32.
Ka warewaretia ngā rārangi kē atu (tākupu) e `login_totp`.

Tauira:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Me `0600` ngā whakaaetanga, nō te kaiwhakamahi.

## Ngā Rereketanga mai i FreeBSD / Ngā Tautuhinga PAM

| Kaupeka | FreeBSD | OpenBSD |
|---------|---------|---------|
| Anga whakamana | PAM (`pam_google_authenticator.so`) | BSD Auth (hōtaka `login_totp`) |
| Akomanga takiuru | kāore | `/etc/login.conf` akomanga `totp` |
| Pakeha | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Tāngata ngārahu syslog | `syslogd` / `newsyslog` | `syslogd` (hāngai) |
| Tukuiho UDP mamao | `@host` i `syslog.conf` | `@host` i `syslog.conf` |
| Tukuiho TCP mamao | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Whakatika Raru

**«oathtool not found»**
Tāpirihia te oath-toolkit: `doas pkg_add oath-toolkit`

**«No secret file for user»**
Whakahaeretia `google-authenticator-setup.sh` mō taua kaiwhakamahi, me hanga rānei
`~/.google_authenticator` ā-ringa me te mea huna base-32 i runga i te rārangi tuatahi.

**Ka whakakāhoretia ngā waehere TOTP i ngā wā katoa**
Whakaūngia kia māhiti ana te karaka pūnaha (`ntpd` ka whakahōhonukia i runga i OpenBSD
i runga i te taunoa). Ka hapa ngā waehere katoa mēnā he rereketanga neke ake i te 30 hēkona.
Whakanuia `TOTP_WINDOW` i `login_totp` mēnā e hiahiatia ana.

**Ka pātai SSH i tētahi kupuhipa umanga waehere TOTP**
Whakamana e tū ana `KbdInteractiveAuthentication yes` me
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` i roto
i `/etc/ssh/sshd_config`, ā, kei roto te kaiwhakamahi i te akomanga takiuru `totp`
(`doas usermod -L totp <kaiwhakamahi>`).

**Ka hapa te sshd -t i muri i te whakatika i sshd_config**
Whakahaeretia `doas sshd -t` me te whakatika i ngā hapa e pūrongotia ana i mua i te
whakahoutia anō i te sshd. Ko te tāruatanga i hangaia e `setup.sh` kei
`/etc/ssh/sshd_config.bak.<waahi-wā>`.

**Kāore te syslog mamao e whiwhi ana i ngā karere**
1. Whakaūngia ka taea te tae atu ki te tūānga UDP/TCP 514 o te tūmau mamao:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Tirohia ngā ture tauanga ahi i ngā taha e rua (OpenBSD pf me te tūmau mamao).
3. Mō te tukuiho TCP, whakaūngia e roto ana `syslogd_flags="-T"` i
   `/etc/rc.conf.local` ā, kua whakahoutia `syslogd`.

## Raihana

Raihana BSD 2-Kūwaha. Tirohia [LICENSE](LICENSE) mō ngā taipitopito.
