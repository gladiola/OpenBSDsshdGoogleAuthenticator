# OpenBSD sshd + Google Authenticator (TOTP)

مصادقة ثنائية العامل لـ SSH على OpenBSD باستخدام Google Authenticator
(TOTP)، مع توجيه سجلات تسجيل الدخول الفاشلة إلى خادم syslog بعيد.

## نظرة عامة

يوفر هذا المستودع:

| الملف | الغرض |
|------|---------|
| `setup.sh` | سكريبت الإعداد التلقائي — يُشغَّل مرة واحدة كمستخدم root |
| `login_totp` | واجهة BSD Auth الخلفية التي تتحقق من رمز TOTP |
| `google-authenticator-setup.sh` | سكريبت تسجيل المستخدمين الفردي |
| `sshd_config.snippet` | إضافات sshd_config المرجعية |
| `syslog.conf.snippet` | إضافات syslog.conf المرجعية للتوجيه البعيد |

### تدفق المصادقة

```
SSH client
  │
  ▼
sshd  ──── 1. مصادقة المفتاح العام (زوج مفاتيح موجود)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. المطالبة: "Google Authenticator code: "
  ├── 3. يُدخل المستخدم رمز TOTP المؤلف من 6 أرقام من التطبيق
  ├── 4. oathtool يتحقق من الرمز مقابل ~/.google_authenticator
  │
  ├─ نجاح → فتح الجلسة؛ تسجيل auth.info محليًا + توجيهه
  └─ فشل → إغلاق الجلسة؛ تسجيل auth.warning محليًا + توجيهه
```

## المتطلبات

- OpenBSD 7.x (تم الاختبار على 7.4 و 7.5)
- وصول root أو `doas`
- حزمة `oath-toolkit` (`pkg_add oath-toolkit`) — توفر `oathtool`
- خادم syslog بعيد يمكن الوصول إليه من المضيف (rsyslog، syslog-ng، إلخ)
- يجب أن يكون للمستخدمين مفتاح SSH العام مثبتًا مسبقًا (`~/.ssh/authorized_keys`)

## البداية السريعة (تلقائي)

```sh
doas sh setup.sh
```

سيقوم السكريبت بما يلي:

1. تثبيت `oath-toolkit` عبر `pkg_add`.
2. نسخ `login_totp` إلى `/usr/local/libexec/auth/login_totp`.
3. إضافة فئة تسجيل دخول `totp` إلى `/etc/login.conf`.
4. تعديل `/etc/ssh/sshd_config`.
5. تعديل `/etc/syslog.conf` بقواعد التوجيه البعيد.
6. إعادة تشغيل `syslogd` و `sshd`.
7. تشغيل `google-authenticator-setup.sh` اختياريًا لتسجيل مستخدم.

## التثبيت اليدوي

### 1. تثبيت oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. تثبيت سكريبت تسجيل الدخول BSD Auth

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. إضافة فئة تسجيل الدخول `totp`

أضف ما يلي إلى `/etc/login.conf`:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

ثم أعد بناء قاعدة بيانات login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. إعداد sshd

أضف الأسطر من `sshd_config.snippet` إلى `/etc/ssh/sshd_config`.
التوجيهات الحرجة هي:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

تحقق من الإعداد وأعد تشغيل sshd:

```sh
doas sshd -t          # التحقق من الإعداد
doas rcctl restart sshd
```

### 5. إعداد syslog البعيد

أضف الأسطر من `syslog.conf.snippet` إلى `/etc/syslog.conf`، مع استبدال
`REMOTE_SYSLOG_SERVER` بعنوان الخادم الفعلي.

**UDP (الافتراضي):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (أكثر موثوقية):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

لـ TCP، قم أيضًا بتمكين TCP في `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

أعد تشغيل syslogd:

```sh
doas rcctl restart syslogd
```

### 6. تسجيل المستخدمين

شغّل سكريبت التسجيل الفردي (كمستخدم root أو المستخدم نفسه):

```sh
doas sh google-authenticator-setup.sh
```

يقوم السكريبت بما يلي:
1. توليد سر TOTP عشوائي بحجم 160 بت.
2. كتابته في `~/.google_authenticator` (الوضع 0600).
3. طباعة URI بصيغة `otpauth://` ورمز QR في الطرفية (إذا كان `qrencode` مثبتًا).
4. تعيين المستخدم في فئة تسجيل الدخول `totp`.

امسح رمز QR (أو الصق الـ URI) في Google Authenticator أو Aegis أو
Authy أو أي تطبيق متوافق مع TOTP.

### 7. تعيين المستخدمين لفئة تسجيل الدخول totp

إذا لم تستخدم `google-authenticator-setup.sh`، عيّن الفئة يدويًا:

```sh
doas usermod -L totp alice
```

## التحقق من الإعداد

### اختبار oathtool محليًا

```sh
# توليد رمز TOTP الحالي لسر المستخدم:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

قارن هذا مع الرمز الظاهر في تطبيق المصادقة — يجب أن يتطابقا.

### اختبار توجيه syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

تحقق من وصول هذه الرسائل إلى خادم syslog البعيد.

### اختبار تسجيل الدخول عبر SSH

افتح جلسة SSH **جديدة** (ابقِ جلستك الحالية مفتوحة في حال احتجت إلى إصلاح شيء):

```sh
ssh -v alice@your-server
```

التدفق المتوقع:
1. يقبل sshd مفتاحك العام.
2. ترى المطالبة: `Google Authenticator code: `
3. أدخل الرمز المؤلف من 6 أرقام من تطبيق المصادقة.
4. ينجح تسجيل الدخول أو يفشل؛ تظهر النتيجة في `/var/log/authlog` وعلى خادم syslog البعيد.

## صيغة سجل تسجيل الدخول الفاشل

عندما يرفض `login_totp` رمز TOTP، يصدر رسالة عبر `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

تُكتب هذه الرسالة في:
- سجل syslog المحلي (`/var/log/authlog` على OpenBSD).
- خادم syslog البعيد عبر قاعدة `auth.info` في `syslog.conf`.

يسجّل sshd نفسه أحداث فشل مصادقة إضافية:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## مرجع الملفات

### `login_totp` (واجهة BSD Auth الخلفية)

- **الموقع:** `/usr/local/libexec/auth/login_totp`
- **الصلاحيات:** `root:auth 0550`
- **ملف السر:** `~/.google_authenticator` (السطر الأول = سر TOTP بترميز base-32)
- **التسجيل:** `logger -p auth.warning` عند الفشل، `auth.info` عند النجاح
- **التسامح الزمني:** ±1 × 30 ثانية (قابل للتعديل عبر `TOTP_WINDOW`)

### `~/.google_authenticator`

ملف نصي عادي؛ يجب أن يكون **السطر الأول** هو سر TOTP بترميز base-32.
يتم تجاهل الأسطر الإضافية (التعليقات) من قِبَل `login_totp`.

مثال:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

يجب أن تكون الصلاحيات `0600` ومملوكة من قِبَل المستخدم.

## الاختلافات عن إعدادات FreeBSD / PAM

| الموضوع | FreeBSD | OpenBSD |
|-------|---------|---------|
| إطار المصادقة | PAM (`pam_google_authenticator.so`) | BSD Auth (سكريبت `login_totp`) |
| فئة تسجيل الدخول | غير متاح | فئة `totp` في `/etc/login.conf` |
| الحزمة | `security/google-authenticator-pam` | `security/oath-toolkit` |
| خدمة syslog | `syslogd` / `newsyslog` | `syslogd` (مدمج) |
| التوجيه البعيد UDP | `@host` في `syslog.conf` | `@host` في `syslog.conf` |
| التوجيه البعيد TCP | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## استكشاف الأخطاء وإصلاحها

**"oathtool not found"**
ثبّت oath-toolkit: `doas pkg_add oath-toolkit`

**"No secret file for user"**
شغّل `google-authenticator-setup.sh` لذلك المستخدم، أو أنشئ يدويًا
`~/.google_authenticator` مع السر بترميز base-32 في السطر الأول.

**رموز TOTP مرفوضة دائمًا**
تأكد من مزامنة ساعة النظام (`ntpd` ممكّن على OpenBSD افتراضيًا).
سيتسبب انحراف الساعة بأكثر من 30 ثانية في فشل كل رمز.
قم بزيادة `TOTP_WINDOW` في `login_totp` إذا لزم الأمر.

**SSH يطلب كلمة مرور بدلاً من رمز TOTP**
تحقق من وجود `KbdInteractiveAuthentication yes` و
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` كليهما
في `/etc/ssh/sshd_config`، وأن المستخدم في فئة تسجيل الدخول `totp`
(`doas usermod -L totp <user>`).

**فشل sshd -t بعد تعديل sshd_config**
شغّل `doas sshd -t` وأصلح أي أخطاء مُبلَّغ عنها قبل إعادة تشغيل sshd.
النسخة الاحتياطية التي أنشأها `setup.sh` موجودة في
`/etc/ssh/sshd_config.bak.<timestamp>`.

**خادم syslog البعيد لا يستقبل الرسائل**
1. تأكد من إمكانية الوصول إلى منفذ UDP/TCP 514 للخادم البعيد:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. تحقق من قواعد جدار الحماية على كلا الطرفين (OpenBSD pf والخادم البعيد).
3. لتوجيه TCP، تأكد من وجود `syslogd_flags="-T"` في
   `/etc/rc.conf.local` وإعادة تشغيل `syslogd`.

## الرخصة

رخصة BSD ثنائية البند. انظر [LICENSE](LICENSE) للتفاصيل.
