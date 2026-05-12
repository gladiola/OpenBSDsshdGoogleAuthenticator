# OpenBSD sshd + Google Authenticator (TOTP)

Google Authenticator (TOTP) በመጠቀም ለ OpenBSD SSH ሁለት-ደረጃ ማረጋገጫ፣
ከተሳኩ-ያልሆኑ ግንኙነቶች ምዝገባዎችን ወደ ሩቅ syslog አገልጋይ ማስተላለፍ።

## አጠቃላይ እይታ

ይህ ማከማቻ ይሰጣል፦

| ፋይል | ዓላማ |
|------|---------|
| `setup.sh` | ራሱ-ሰርቶ ማዋቀሪያ ስክሪፕት — እንደ root አንድ ጊዜ ያሂዱ |
| `login_totp` | የ TOTP ኮዱን የሚያረጋግጥ BSD Auth ጀርባ |
| `google-authenticator-setup.sh` | በተጠቃሚ-ደረጃ ምዝገባ ስክሪፕት |
| `sshd_config.snippet` | የ sshd_config ማጣቀሻ ጭማሪዎች |
| `syslog.conf.snippet` | ለሩቅ ማስተላለፍ የ syslog.conf ማጣቀሻ ጭማሪዎች |

### የማረጋገጫ ፍሰት

```
SSH client
  │
  ▼
sshd  ──── 1. ይፋዊ-ቁልፍ ማረጋገጫ (ያለ ቁልፍ ጥንድ)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. ጥያቄ: "Google Authenticator code: "
  ├── 3. ተጠቃሚ ከመተግበሪያው 6-አሃዝ TOTP ኮድ ያስገባል
  ├── 4. oathtool ኮዱን ከ ~/.google_authenticator ጋር ያረጋግጣል
  │
  ├─ ስኬት → ክፍለ-ጊዜ ተከፈተ; auth.info በቦታው ተመዘገበ + ተላከ
  └─ ውድቀት → ክፍለ-ጊዜ ተዘጋ; auth.warning በቦታው ተመዘገበ + ተላከ
```

## መስፈርቶች

- OpenBSD 7.x (በ 7.4 እና 7.5 ተሞክሯል)
- Root ወይም `doas` ፍቃድ
- `oath-toolkit` ጥቅል (`pkg_add oath-toolkit`) — `oathtool` ይሰጣል
- ከአስተናጋጁ ሊደረስ የሚችል ሩቅ syslog አገልጋይ (rsyslog, syslog-ng, ወዘተ)
- ተጠቃሚዎች አስቀድሞ የተጫነ SSH ይፋዊ ቁልፍ ሊኖራቸው ይገባል (`~/.ssh/authorized_keys`)

## ፈጣን ጅምር (ራሱ-ሰርቶ)

```sh
doas sh setup.sh
```

ስክሪፕቱ ይሰራል፦

1. `oath-toolkit` ን `pkg_add` ን በመጠቀም ይጭናል።
2. `login_totp` ን ወደ `/usr/local/libexec/auth/login_totp` ይቀዳል።
3. `totp` ግንኙነት ክፍልን ወደ `/etc/login.conf` ያክላል።
4. `/etc/ssh/sshd_config` ን ያስተካክላል።
5. `/etc/syslog.conf` ን በሩቅ ማስተላለፍ ደንቦች ያስተካክላል።
6. `syslogd` እና `sshd` ን እንደ አዲስ ያስጀምራል።
7. ተጠቃሚ ለመመዝገብ `google-authenticator-setup.sh` ን አማራጭ ሆኖ ያሂዳል።

## ልዩ ጭነት

### 1. oath-toolkit ን ጫን

```sh
doas pkg_add oath-toolkit
```

### 2. BSD Auth ግንኙነት ስክሪፕት ጫን

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. `totp` ግንኙነት ክፍሉን ጨምር

ወደ `/etc/login.conf` ይህን ጨምር፦

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

ከዚያ የ login.conf ዳታቤዝ እንደ አዲስ ገንባ፦

```sh
doas cap_mkdb /etc/login.conf
```

### 4. sshd ን አዋቅር

ከ `sshd_config.snippet` መስመሮችን ወደ `/etc/ssh/sshd_config` ጨምር።
ወሳኝ ዳይሬክቲቮቹ ናቸው፦

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

አረጋግጥ እና sshd ን እንደ አዲስ አስጀምር፦

```sh
doas sshd -t          # ማዋቀሩን አረጋግጥ
doas rcctl restart sshd
```

### 5. ሩቅ syslog ን አዋቅር

ከ `syslog.conf.snippet` መስመሮችን ወደ `/etc/syslog.conf` ጨምር፣
`REMOTE_SYSLOG_SERVER` ን ትክክለኛ የአገልጋይ አድራሻ በመተካት።

**UDP (ነባሪ):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (የበለጠ አስተማማኝ):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

ለ TCP, ደግሞ TCP ን በ `/etc/rc.conf.local` ውስጥ አንቃ፦

```
syslogd_flags="-T"
```

syslogd ን እንደ አዲስ ጫን፦

```sh
doas rcctl restart syslogd
```

### 6. ተጠቃሚዎችን ምዝገብ

በተጠቃሚ-ደረጃ ምዝገባ ስክሪፕቱን አሂድ (እንደ root ወይም ተጠቃሚው ራሱ)፦

```sh
doas sh google-authenticator-setup.sh
```

ስክሪፕቱ፦
1. ዘፈቀደ 160-ቢት TOTP ሚስጥር ይፈጥራል።
2. ወደ `~/.google_authenticator` ይጽፈዋል (ሁነት 0600)።
3. `otpauth://` URI እና ተርሚናል QR ኮድ ያትማል (ካለ `qrencode` ተጭኖ)።
4. ተጠቃሚውን ወደ `totp` ግንኙነት ክፍል ይመድባል።

QR ኮዱን ቃኝ (ወይም URI ያጣብቅ) ወደ Google Authenticator፣ Aegis፣
Authy፣ ወይም ማናቸውም TOTP-ተኳሃኝ መተግበሪያ።

### 7. ተጠቃሚዎችን ወደ totp ግንኙነት ክፍል ምድብ

`google-authenticator-setup.sh` ካልተጠቀምህ፣ ክፍሉን ልዩ ሁኔታ ምድብ፦

```sh
doas usermod -L totp alice
```

## ማዋቀሩን ማረጋገጥ

### oathtool ን በቦታው ሙክር

```sh
# ለተጠቃሚ ሚስጥር ወቅታዊ TOTP ኮድ ፍጠር፦
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

ይህን ከማረጋገጫ መተግበሪያው ጋር አወዳድር — ሊዛመዱ ይገባቸዋል።

### syslog ማስተላለፍ ሙክር

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

እነዚህ መልዕክቶች ሩቅ syslog አገልጋዩ ላይ መድረሳቸውን አረጋግጥ።

### SSH ግንኙነት ሙክር

**አዲስ** SSH ክፍለ-ጊዜ ክፈት (ነባሩን ክፍለ-ጊዜ ክፍት ይቆይ ሆኖ
ምናልባት ማስተካከል ሊያስፈልግ ይቻላልና)፦

```sh
ssh -v alice@your-server
```

የሚጠበቅ ፍሰት፦
1. sshd ይፋዊ ቁልፍህን ይቀበላል።
2. ጥያቄውን ታያለህ፦ `Google Authenticator code: `
3. ከማረጋገጫ መተግበሪያው 6-አሃዝ ኮድ አስገባ።
4. ግንኙነት ይሳካል ወይም ይሳካሣ; ውጤቱ `/var/log/authlog` እና
   ሩቅ syslog አገልጋዩ ላይ ይታያል።

## ያልተሳካ-ግንኙነት ምዝገባ ቅርጸት

`login_totp` TOTP ኮድ ሲቀነስ፣ `logger(1)` ን በመጠቀም መልዕክት ይልካል፦

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

ይህ መልዕክት ተጽፏል ወደ፦
- የቦታው syslog (`/var/log/authlog` OpenBSD ላይ)።
- ሩቅ syslog አገልጋዩ `syslog.conf` ውስጥ ባለ `auth.info` ደንብ በኩል።

ተጨማሪ ያልተሳካ-ማረጋገጫ ክስተቶች በ sshd ራሱ ተመዝግበዋል፦

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## ፋይል ማጣቀሻ

### `login_totp` (BSD Auth ጀርባ)

- **አቀማመጥ:** `/usr/local/libexec/auth/login_totp`
- **ፍቃዶች:** `root:auth 0550`
- **ሚስጥር ፋይል:** `~/.google_authenticator` (መጀመሪያ መስመር = base-32 TOTP ሚስጥር)
- **ምዝገባ:** ውድቀት ሲኖር `logger -p auth.warning`፣ ስኬት ሲኖር `auth.info`
- **የጊዜ መቻቻል:** ±1 × 30-ሰከንድ እርምጃ (በ `TOTP_WINDOW` ሊዋቀር ይችላል)

### `~/.google_authenticator`

ቀጥተኛ ጽሁፍ ፋይል; **ፊተኛ መስመሩ** base-32 TOTP ሚስጥሩ መሆን አለበት።
ተጨማሪ መስመሮች (አስተያየቶች) `login_totp` ችላ ይላቸዋል።

ምሳሌ፦
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

ፍቃዶቹ `0600` መሆን አለባቸው፣ በተጠቃሚው ተይዘው።

## ከ FreeBSD / PAM-ላይ-የተመሠረተ ማዋቀር ልዩነቶች

| ርዕሰ ጉዳይ | FreeBSD | OpenBSD |
|-------|---------|---------|
| ማረጋገጫ ሥርዓት | PAM (`pam_google_authenticator.so`) | BSD Auth (`login_totp` ስክሪፕት) |
| ግንኙነት ክፍል | አይሠራም | `/etc/login.conf` `totp` ክፍል |
| ጥቅል | `security/google-authenticator-pam` | `security/oath-toolkit` |
| syslog አሂዱ | `syslogd` / `newsyslog` | `syslogd` (ውስጣዊ) |
| ሩቅ UDP ማስተላለፍ | `@host` ב`syslog.conf` | `@host` ב`syslog.conf` |
| ሩቅ TCP ማስተላለፍ | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## ችግር ፍቺ

**"oathtool not found"**
oath-toolkit ን ጫን፦ `doas pkg_add oath-toolkit`

**"No secret file for user"**
ለዚያ ተጠቃሚ `google-authenticator-setup.sh` ን አሂድ፣ ወይም ልዩ ሁኔታ
`~/.google_authenticator` ን ፊተኛ መስመሩ ላይ base-32 ሚስጥሩ ኖሮ ፍጠር።

**TOTP ኮዶቹ ሁሌ ይቀናቃኛሉ**
የስርዓቱ ሰዓት እንደ ተሳሰረ አረጋግጥ (`ntpd` OpenBSD ላይ ነባሪ ሆኖ ነቅቷል)።
ከ 30 ሰከንዶች በላይ የሰዓት ልዩነት ሁሉ ኮድ እንዲወድቅ ያደርጋል።
ካስፈለገ `login_totp` ውስጥ `TOTP_WINDOW` ን ጨምር።

**SSH ከ TOTP ኮድ ፋንታ ሕጋዊ ምሥጢር ቃል ይጠይቃል**
`KbdInteractiveAuthentication yes` እና
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` ሁለቱም
`/etc/ssh/sshd_config` ውስጥ መኖራቸውን፣ እና ተጠቃሚው `totp`
ግንኙነት ክፍል ውስጥ መሆኑን አረጋግጥ (`doas usermod -L totp <user>`)።

**sshd_config ን ካስተካከሉ በኋላ sshd -t ይወድቃል**
`doas sshd -t` ን አሂድ sshd ን እንደ አዲስ ከማስጀምርህ በፊት ሁሉ ሪፖርት
የተደረጉ ስህተቶችን አስተካክል። `setup.sh` ያደረገው ምትኬ ናቁ
`/etc/ssh/sshd_config.bak.<timestamp>` ነው።

**ሩቅ syslog መልዕክቶችን አይቀበልም**
1. ሩቅ አገልጋዩ UDP/TCP ወደብ 514 ሊደረስ እንደሚችል አረጋግጥ፦
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. በሁለቱም ጫፎች ላይ የፋየርዎል ደንቦችን ፈትሽ (OpenBSD pf እና ሩቅ አገልጋዩ)።
3. ለ TCP ማስተላለፍ፣ `syslogd_flags="-T"` `/etc/rc.conf.local` ውስጥ
   መኖሩን እና `syslogd` እንደ አዲስ መጀምረቱን አረጋግጥ።

## ፈቃድ

BSD 2-አንቀጽ ፈቃድ። ዝርዝሮች ለ [LICENSE](LICENSE) ይመልከቱ።
