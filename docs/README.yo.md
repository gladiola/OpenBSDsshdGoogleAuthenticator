# OpenBSD sshd + Google Authenticator (TOTP)

Ìjẹ̀rísí-ìdánimọ̀ ìpele-méjì fún OpenBSD SSH nipa lilo Google Authenticator
(TOTP), pẹ̀lú gbigbe àwọn àkọsílẹ̀ ìbẹ̀wọlé tí kùnà lọ sí olupin syslog jíjìnnà.

## Àgbéyẹ̀wò

Apo yii n pese:

| Fáìlì | Ète |
|------|---------|
| `setup.sh` | Ìpilẹ̀ṣẹ̀ ìṣeto aladaṣe — ṣe bí gbòǹgbò ẹẹ́kan |
| `login_totp` | Ẹ̀yìn BSD Auth tó ń ṣe àyẹ̀wò kóòdù TOTP |
| `google-authenticator-setup.sh` | Ìṣetò ìforúkọsílẹ̀ olùmúlò kọ̀ọ̀kan |
| `sshd_config.snippet` | Àwọn àfikún sshd_config ìtọ́kasí |
| `syslog.conf.snippet` | Àwọn àfikún syslog.conf ìtọ́kasí fún gbigbe jíjìnnà |

### Ìṣàn Ìjẹ̀rísí-ìdánimọ̀

```
SSH client
  │
  ▼
sshd  ──── 1. Ìjẹ̀rísí-ìdánimọ̀ bọ́tìnì-gbangba (oríkẹ bọ́tìnì tó wà)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Ìbéèrè: "Google Authenticator code: "
  ├── 3. Olùmúlò tẹ kóòdù TOTP ọ̀nà 6 àkàrà láti ìwé-iṣẹ́
  ├── 4. oathtool ṣe àyẹ̀wò kóòdù náà lòdì sí ~/.google_authenticator
  │
  ├─ ÀṢEYỌRÍ → ìjókòó ṣí; auth.info jẹ́ gbàdúrà ní àdúgbò + tẹ̀dó
  └─ ÀKÓBẸRẸ → ìjókòó tilẹ; auth.warning jẹ́ gbàdúrà ní àdúgbò + tẹ̀dó
```

## Àwọn Ohun Tí a Nílò

- OpenBSD 7.x (ìdánwò lórí 7.4 àti 7.5)
- Ànfààní root tàbí `doas`
- Àkójọ `oath-toolkit` (`pkg_add oath-toolkit`) — n pese `oathtool`
- Olupin syslog jíjìnnà tí a lè dé láti olùgbàlejò (rsyslog, syslog-ng, àti bẹ́ẹ̀ bẹ́ẹ̀ lọ)
- Àwọn olùmúlò gbọdọ̀ ti ni bọ́tìnì gbangba SSH tí a fífilò tẹ́lẹ̀ (`~/.ssh/authorized_keys`)

## Ìbẹ̀rẹ̀ Ìyára (Aladaṣe)

```sh
doas sh setup.sh
```

Ìpilẹ̀ṣẹ̀ náà yóò:

1. Fi `oath-toolkit` sí i nípasẹ̀ `pkg_add`.
2. Dàkọ `login_totp` sí `/usr/local/libexec/auth/login_totp`.
3. Ṣàfikún ẹ̀ka ìbẹ̀wọlé `totp` sí `/etc/login.conf`.
4. Ṣe àtúnṣe `/etc/ssh/sshd_config`.
5. Ṣe àtúnṣe `/etc/syslog.conf` pẹ̀lú àwọn òfin gbigbe jíjìnnà.
6. Tún bẹ̀rẹ̀ `syslogd` àti `sshd`.
7. Ṣe àṣeyọrí jẹ́ ṣiṣe `google-authenticator-setup.sh` láti forúkọ olùmúlò kan.

## Fífilò Ọwọ́

### 1. Fi oath-toolkit Sí Í

```sh
doas pkg_add oath-toolkit
```

### 2. Fi Ìpilẹ̀ṣẹ̀ Ìbẹ̀wọlé BSD Auth Sí Í

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Ṣàfikún Ẹ̀ka Ìbẹ̀wọlé `totp`

Ṣàfikún èyí tó tẹ̀le sí `/etc/login.conf`:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

Lẹ́hìn náà, tún kọ́ àkójọpọ̀ data login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Ṣètò sshd

Ṣàfikún àwọn ìlà láti `sshd_config.snippet` sí `/etc/ssh/sshd_config`.
Àwọn ìtọ́sọ́nà pàtàkì ni:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Ṣe àyẹ̀wò àti tún bẹ̀rẹ̀ sshd:

```sh
doas sshd -t          # ṣe àyẹ̀wò ìṣeto
doas rcctl restart sshd
```

### 5. Ṣètò Syslog Jíjìnnà

Ṣàfikún àwọn ìlà láti `syslog.conf.snippet` sí `/etc/syslog.conf`, rọpo
`REMOTE_SYSLOG_SERVER` pẹ̀lú àdírẹ́ẹ̀sì olupin rẹ gidi.

**UDP (ìpilẹ̀ṣẹ̀):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (ó gbára lé jù):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Fún TCP, tún jẹ́ ki TCP ṣiṣẹ́ nínú `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Tún gbé syslogd ṣíṣẹ́:

```sh
doas rcctl restart syslogd
```

### 6. Forúkọsílẹ̀ Àwọn Olùmúlò

Ṣe ìpilẹ̀ṣẹ̀ ìforúkọsílẹ̀ olùmúlò kọ̀ọ̀kan (gẹ́gẹ́ bí gbòǹgbò tàbí olùmúlò fúnra rẹ̀):

```sh
doas sh google-authenticator-setup.sh
```

Ìpilẹ̀ṣẹ̀ náà:
1. Ṣe ìpilẹ̀ṣẹ̀ àṣírí TOTP 160-bit aládáàbò.
2. Kọ ó sí `~/.google_authenticator` (ìpele 0600).
3. Tẹ̀wé URI `otpauth://` àti kóòdù QR nínú ìgbìmọ̀ (tí `qrencode` bá wà).
4. Fi olùmúlò sọ sí ẹ̀ka ìbẹ̀wọlé `totp`.

Ṣàyẹ̀wò kóòdù QR (tàbí fi URI lẹ̀) sínú Google Authenticator, Aegis,
Authy, tàbí ìwé-iṣẹ́ kan tí ó bá TOTP mu.

### 7. Yan Àwọn Olùmúlò sí Ẹ̀ka Ìbẹ̀wọlé totp

Tí o bá kò lo `google-authenticator-setup.sh`, yan ẹ̀ka náà ní ọwọ́:

```sh
doas usermod -L totp alice
```

## Ìjẹ̀rísí Ìṣeto

### Ṣàdánwò oathtool ní Àdúgbò

```sh
# Ṣe ìpilẹ̀ṣẹ̀ kóòdù TOTP lọ́wọ́lọ́wọ́ fún àṣírí olùmúlò kan:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Ṣe àfiwé èyí pẹ̀lú kóòdù tí ó hàn nínú ìwé-iṣẹ́ ìjẹ̀rísí-ìdánimọ̀ — wọn gbọdọ̀ báramu.

### Ṣàdánwò Gbigbe Syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Ṣe àyẹ̀wò pé àwọn ìfiránsẹ́ wọ̀nyí dé olupin syslog jíjìnnà.

### Ṣàdánwò Ìbẹ̀wọlé SSH

Ṣí ìjókòó SSH **tuntun** (jẹ́ kí ìjókòó rẹ tó wà ṣí bọ̀ ṣọwọ bọ̀ tó jẹ́ pé
nǹkan nílò àtúnṣe):

```sh
ssh -v alice@your-server
```

Ìṣàn tí a retí:
1. sshd gba bọ́tìnì gbangba rẹ.
2. O rí ìbéèrè náà: `Google Authenticator code: `
3. Tẹ kóòdù ọ̀nà 6 àkàrà láti ìwé-iṣẹ́ ìjẹ̀rísí-ìdánimọ̀.
4. Ìbẹ̀wọlé ṣàṣeyọrí tàbí kùnà; àbájáde hàn nínú `/var/log/authlog` àti
   lórí olupin syslog jíjìnnà.

## Ìdàpọ̀ Àkọsílẹ̀ Ìbẹ̀wọlé Tí Kùnà

Nígbàtí `login_totp` bá kọ kóòdù TOTP, ó ń fún ìfiránsẹ́ kan pẹ̀lú `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

A kọ ìfiránsẹ́ yii sí:
- Syslog àdúgbò (`/var/log/authlog` lórí OpenBSD).
- Olupin syslog jíjìnnà nípasẹ̀ òfin `auth.info` nínú `syslog.conf`.

Àwọn ìṣẹ̀lẹ̀ àkóbẹrẹ ìjẹ̀rísí-ìdánimọ̀ àfikún ni sshd fúnra rẹ̀ gbàdúrà:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Ìtọ́kasí Fáìlì

### `login_totp` (Ẹ̀yìn BSD Auth)

- **Ìpàdé:** `/usr/local/libexec/auth/login_totp`
- **Àwọn Ìgbaniláàyè:** `root:auth 0550`
- **Fáìlì àṣírí:** `~/.google_authenticator` (ìlà àkọ́kọ́ = àṣírí TOTP base-32)
- **Gbàdúrà:** `logger -p auth.warning` nígbà àkóbẹrẹ, `auth.info` nígbà àṣeyọrí
- **Ìfaradà àkókò:** ±1 × ìgbésẹ̀ 30-ììṣẹ́jú (ó ṣeéṣe kí a ṣètò rẹ̀ nípasẹ̀ `TOTP_WINDOW`)

### `~/.google_authenticator`

Fáìlì ọ̀rọ̀-pẹlẹbẹ; **ìlà àkọ́kọ́** gbọdọ̀ jẹ́ àṣírí TOTP base-32.
Àwọn ìlà àfikún (àwọn asọye) ni `login_totp` yọ sílẹ̀.

Àpẹẹrẹ:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Àwọn ìgbaniláàyè gbọdọ̀ jẹ́ `0600`, tí olùmúlò ni.

## Àwọn Ìyàtọ̀ Lọ́wọ́ Ìṣeto FreeBSD / PAM

| Àkọlé | FreeBSD | OpenBSD |
|-------|---------|---------|
| Ẹ̀rọ ìjẹ̀rísí-ìdánimọ̀ | PAM (`pam_google_authenticator.so`) | BSD Auth (ìpilẹ̀ṣẹ̀ `login_totp`) |
| Ẹ̀ka ìbẹ̀wọlé | kò sí | Ẹ̀ka `totp` ní `/etc/login.conf` |
| Àkójọ | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Daemon syslog | `syslogd` / `newsyslog` | `syslogd` (tí a kọ́ sínú) |
| Gbigbe UDP jíjìnnà | `@host` ní `syslog.conf` | `@host` ní `syslog.conf` |
| Gbigbe TCP jíjìnnà | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Ìyèsí Àwọn Ìṣòro

**"oathtool not found"**
Fi oath-toolkit sí i: `doas pkg_add oath-toolkit`

**"No secret file for user"**
Ṣe `google-authenticator-setup.sh` fún olùmúlò yẹn, tàbí ṣẹ̀dá ní ọwọ́
`~/.google_authenticator` pẹ̀lú àṣírí base-32 lórí ìlà àkọ́kọ́.

**Àwọn kóòdù TOTP tí a máa ń kọ̀ nígbàgbogbo**
Rí i dájú pé àgogo ètò náà ti ṣe àwárí (`ntpd` ṣiṣẹ́ lórí OpenBSD ní ìpilẹ̀ṣẹ̀).
Ìyàtọ̀ àgogo tó ju ìṣẹ́jú 30 lọ yóò mú kóòdù kọ̀ọ̀kan kùnà.
Ṣe ìpọ̀sí `TOTP_WINDOW` nínú `login_totp` tí ó bá jẹ́ pé ó pọn dandan.

**SSH ń béèrè ọ̀rọ̀ àṣírí dípò kóòdù TOTP**
Rí i dájú pé `KbdInteractiveAuthentication yes` àti
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` méjèjì
wà nínú `/etc/ssh/sshd_config`, àti pé olùmúlò wà nínú ẹ̀ka ìbẹ̀wọlé `totp`
(`doas usermod -L totp <user>`).

**sshd -t kùnà lẹ́hìn ìṣatunṣe sshd_config**
Ṣe `doas sshd -t` àti ṣe àtúnṣe àwọn àṣìṣe tí a ròyìn ṣáájú àtúnbẹ̀rẹ̀ sshd.
Ẹ̀dà ẹ̀yìn tí `setup.sh` ṣẹ̀dá wà ní
`/etc/ssh/sshd_config.bak.<timestamp>`.

**Syslog jíjìnnà kò gba àwọn ìfiránsẹ́**
1. Jẹ̀rísí pé a lè dé ẹ̀bùtẹ̀ UDP/TCP 514 ti olupin jíjìnnà:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Ṣàyẹ̀wò àwọn òfin ògiri-iná lórí àwọn ẹgbẹ́ méjèjì (OpenBSD pf àti olupin jíjìnnà).
3. Fún gbigbe TCP, jẹ̀rísí pé `syslogd_flags="-T"` wà nínú
   `/etc/rc.conf.local` àti pé a ti tún bẹ̀rẹ̀ `syslogd`.

## Ìwé-àṣẹ

Ìwé-àṣẹ BSD 2-Clause. Wo [LICENSE](LICENSE) fún àwọn alaye.
