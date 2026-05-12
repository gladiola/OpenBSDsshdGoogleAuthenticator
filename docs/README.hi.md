# OpenBSD sshd + Google Authenticator (TOTP)

Google Authenticator (TOTP) का उपयोग करके OpenBSD SSH के लिए द्वि-कारक प्रमाणीकरण।
विफल लॉगिन लॉग एक दूरस्थ syslog सर्वर पर अग्रेषित किए जाते हैं।

## अवलोकन

यह रिपॉजिटरी प्रदान करती है:

| फ़ाइल | उद्देश्य |
|------|---------|
| `setup.sh` | स्वचालित सेटअप स्क्रिप्ट — root के रूप में एक बार चलाएं |
| `login_totp` | BSD Auth बैकएंड जो TOTP कोड सत्यापित करता है |
| `google-authenticator-setup.sh` | प्रति-उपयोगकर्ता नामांकन स्क्रिप्ट |
| `sshd_config.snippet` | संदर्भ sshd_config परिवर्धन |
| `syslog.conf.snippet` | दूरस्थ अग्रेषण के लिए संदर्भ syslog.conf परिवर्धन |

### प्रमाणीकरण प्रवाह

```
SSH क्लाइंट
  │
  ▼
sshd  ──── 1. सार्वजनिक-कुंजी प्रमाणीकरण (मौजूदा कुंजी जोड़ी)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. संकेत: "Google Authenticator code: "
  ├── 3. उपयोगकर्ता ऐप से 6-अंकीय TOTP दर्ज करता है
  ├── 4. oathtool ~/.google_authenticator के विरुद्ध कोड सत्यापित करता है
  │
  ├─ सफलता → सत्र खुला; auth.info स्थानीय रूप से लॉग और अग्रेषित
  └─ विफलता → सत्र बंद; auth.warning स्थानीय रूप से लॉग और अग्रेषित
```

## आवश्यकताएँ

- OpenBSD 7.x (7.4 और 7.5 पर परीक्षण किया गया)
- root या `doas` पहुँच
- `oath-toolkit` पैकेज (`pkg_add oath-toolkit`) — `oathtool` प्रदान करता है
- होस्ट से पहुँच योग्य दूरस्थ syslog सर्वर (rsyslog, syslog-ng, आदि)
- उपयोगकर्ताओं के पास SSH सार्वजनिक कुंजी पहले से स्थापित होनी चाहिए (`~/.ssh/authorized_keys`)

## त्वरित प्रारंभ (स्वचालित)

```sh
doas sh setup.sh
```

स्क्रिप्ट यह करेगी:

1. `pkg_add` के माध्यम से `oath-toolkit` स्थापित करना।
2. `login_totp` को `/usr/local/libexec/auth/login_totp` पर कॉपी करना।
3. `/etc/login.conf` में `totp` लॉगिन क्लास जोड़ना।
4. `/etc/ssh/sshd_config` को पैच करना।
5. `/etc/syslog.conf` में दूरस्थ अग्रेषण नियम जोड़ना।
6. `syslogd` और `sshd` पुनः प्रारंभ करना।
7. वैकल्पिक रूप से उपयोगकर्ता को नामांकित करने के लिए `google-authenticator-setup.sh` चलाना।

## मैन्युअल स्थापना

### 1. oath-toolkit स्थापित करें

```sh
doas pkg_add oath-toolkit
```

### 2. BSD Auth लॉगिन स्क्रिप्ट स्थापित करें

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. `totp` लॉगिन क्लास जोड़ें

निम्नलिखित को `/etc/login.conf` में जोड़ें:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

फिर login.conf डेटाबेस पुनर्निर्मित करें:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. sshd कॉन्फ़िगर करें

`sshd_config.snippet` की पंक्तियाँ `/etc/ssh/sshd_config` में जोड़ें।
महत्वपूर्ण निर्देश हैं:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

sshd सत्यापित करें और पुनः प्रारंभ करें:

```sh
doas sshd -t          # कॉन्फ़िग सत्यापित करें
doas rcctl restart sshd
```

### 5. दूरस्थ syslog कॉन्फ़िगर करें

`syslog.conf.snippet` की पंक्तियाँ `/etc/syslog.conf` में जोड़ें,
`REMOTE_SYSLOG_SERVER` को अपने वास्तविक सर्वर पते से बदलें।

**UDP (डिफ़ॉल्ट):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (अधिक विश्वसनीय):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

TCP के लिए, `/etc/rc.conf.local` में TCP भी सक्षम करें:

```
syslogd_flags="-T"
```

syslogd पुनः लोड करें:

```sh
doas rcctl restart syslogd
```

### 6. उपयोगकर्ताओं को नामांकित करें

प्रति-उपयोगकर्ता नामांकन स्क्रिप्ट चलाएं (root के रूप में या उपयोगकर्ता स्वयं):

```sh
doas sh google-authenticator-setup.sh
```

स्क्रिप्ट:
1. एक यादृच्छिक 160-बिट TOTP रहस्य उत्पन्न करती है।
2. इसे `~/.google_authenticator` (मोड 0600) में लिखती है।
3. एक `otpauth://` URI और टर्मिनल QR कोड प्रिंट करती है (यदि `qrencode` स्थापित है)।
4. उपयोगकर्ता को `totp` लॉगिन क्लास में असाइन करती है।

QR कोड स्कैन करें (या URI पेस्ट करें) Google Authenticator, Aegis,
Authy, या किसी भी TOTP-संगत ऐप में।

### 7. उपयोगकर्ताओं को totp लॉगिन क्लास में असाइन करें

यदि आपने `google-authenticator-setup.sh` का उपयोग नहीं किया, तो क्लास मैन्युअल रूप से असाइन करें:

```sh
doas usermod -L totp alice
```

## सेटअप सत्यापित करना

### oathtool को स्थानीय रूप से परीक्षण करें

```sh
# उपयोगकर्ता के रहस्य के लिए वर्तमान TOTP कोड उत्पन्न करें:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

प्रमाणक ऐप में दिखाए गए कोड से तुलना करें — वे मेल खाने चाहिए।

### syslog अग्रेषण परीक्षण करें

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

जाँचें कि ये संदेश दूरस्थ syslog सर्वर पर पहुँचते हैं।

### SSH लॉगिन परीक्षण करें

एक **नया** SSH सत्र खोलें (यदि कुछ ठीक करने की आवश्यकता हो तो मौजूदा सत्र खुला रखें):

```sh
ssh -v alice@your-server
```

अपेक्षित प्रवाह:
1. sshd आपकी सार्वजनिक कुंजी स्वीकार करता है।
2. आपको संकेत दिखता है: `Google Authenticator code: `
3. प्रमाणक ऐप से 6-अंकीय कोड दर्ज करें।
4. लॉगिन सफल या विफल; परिणाम `/var/log/authlog` और
   दूरस्थ syslog सर्वर पर दिखाई देता है।

## विफल-लॉगिन लॉग प्रारूप

जब `login_totp` TOTP कोड अस्वीकार करता है, तो यह `logger(1)` के माध्यम से एक संदेश भेजता है:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

यह संदेश लिखा जाता है:
- स्थानीय syslog (OpenBSD पर `/var/log/authlog`)।
- `syslog.conf` में `auth.info` नियम के माध्यम से दूरस्थ syslog सर्वर।

अतिरिक्त प्रमाणीकरण विफलता घटनाएँ sshd द्वारा स्वयं लॉग की जाती हैं:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## फ़ाइल संदर्भ

### `login_totp` (BSD Auth बैकएंड)

- **स्थान:** `/usr/local/libexec/auth/login_totp`
- **अनुमतियाँ:** `root:auth 0550`
- **रहस्य फ़ाइल:** `~/.google_authenticator` (पहली पंक्ति = base-32 TOTP रहस्य)
- **लॉगिंग:** विफलता पर `logger -p auth.warning`, सफलता पर `auth.info`
- **समय सहनशीलता:** ±1 × 30-सेकंड चरण (`TOTP_WINDOW` के माध्यम से कॉन्फ़िगर करने योग्य)

### `~/.google_authenticator`

एक सादा-पाठ फ़ाइल; **पहली पंक्ति** base-32 TOTP रहस्य होनी चाहिए।
अतिरिक्त पंक्तियाँ (टिप्पणियाँ) `login_totp` द्वारा अनदेखी की जाती हैं।

उदाहरण:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

अनुमतियाँ `0600` होनी चाहिए, उपयोगकर्ता के स्वामित्व में।

## FreeBSD / PAM-आधारित सेटअप से अंतर

| विषय | FreeBSD | OpenBSD |
|-------|---------|---------|
| प्रमाणीकरण ढाँचा | PAM (`pam_google_authenticator.so`) | BSD Auth (`login_totp` स्क्रिप्ट) |
| लॉगिन क्लास | लागू नहीं | `/etc/login.conf` `totp` क्लास |
| पैकेज | `security/google-authenticator-pam` | `security/oath-toolkit` |
| syslog डेमन | `syslogd` / `newsyslog` | `syslogd` (अंतर्निहित) |
| दूरस्थ UDP अग्रेषण | `syslog.conf` में `@host` | `syslog.conf` में `@host` |
| दूरस्थ TCP अग्रेषण | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## समस्या निवारण

**"oathtool not found"**
oath-toolkit स्थापित करें: `doas pkg_add oath-toolkit`

**"No secret file for user"**
उस उपयोगकर्ता के लिए `google-authenticator-setup.sh` चलाएं, या पहली पंक्ति में
base-32 रहस्य के साथ `~/.google_authenticator` मैन्युअल रूप से बनाएं।

**TOTP कोड हमेशा अस्वीकृत होते हैं**
सुनिश्चित करें कि सिस्टम घड़ी सिंक्रनाइज़ है (`ntpd` OpenBSD पर डिफ़ॉल्ट रूप से
सक्षम है)। 30 सेकंड से अधिक का घड़ी झुकाव हर कोड को विफल करेगा।
यदि आवश्यक हो तो `login_totp` में `TOTP_WINDOW` बढ़ाएं।

**SSH TOTP कोड के बजाय पासवर्ड माँगता है**
सत्यापित करें कि `KbdInteractiveAuthentication yes` और
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` दोनों
`/etc/ssh/sshd_config` में मौजूद हैं, और उपयोगकर्ता `totp`
लॉगिन क्लास में है (`doas usermod -L totp <user>`)।

**sshd_config संपादित करने के बाद sshd -t विफल होता है**
`doas sshd -t` चलाएं और sshd पुनः प्रारंभ करने से पहले रिपोर्ट की गई त्रुटियाँ ठीक करें।
`setup.sh` द्वारा बनाया गया बैकअप
`/etc/ssh/sshd_config.bak.<timestamp>` पर है।

**दूरस्थ syslog संदेश प्राप्त नहीं कर रहा**
1. दूरस्थ सर्वर का UDP/TCP पोर्ट 514 पहुँच योग्य है, पुष्टि करें:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. दोनों तरफ के फ़ायरवॉल नियम जाँचें (OpenBSD pf और दूरस्थ सर्वर)।
3. TCP अग्रेषण के लिए, पुष्टि करें कि `syslogd_flags="-T"` `/etc/rc.conf.local` में है
   और `syslogd` पुनः प्रारंभ किया गया है।

## लाइसेंस

BSD 2-Clause लाइसेंस। विवरण के लिए [LICENSE](../LICENSE) देखें।
