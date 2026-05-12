# OpenBSD sshd + Google Authenticator (TOTP)

Google Authenticator (TOTP) ব্যবহার করে OpenBSD SSH-এর জন্য দ্বি-কারক প্রমাণীকরণ।
ব্যর্থ লগইনের লগ একটি দূরবর্তী syslog সার্ভারে পাঠানো হয়।

## সংক্ষিপ্ত বিবরণ

এই রিপোজিটরি প্রদান করে:

| ফাইল | উদ্দেশ্য |
|------|---------|
| `setup.sh` | স্বয়ংক্রিয় সেটআপ স্ক্রিপ্ট — root হিসেবে একবার চালান |
| `login_totp` | BSD Auth ব্যাকএন্ড যা TOTP কোড যাচাই করে |
| `google-authenticator-setup.sh` | প্রতি-ব্যবহারকারী নথিভুক্তি স্ক্রিপ্ট |
| `sshd_config.snippet` | রেফারেন্স sshd_config সংযোজন |
| `syslog.conf.snippet` | দূরবর্তী ফরওয়ার্ডিংয়ের জন্য রেফারেন্স syslog.conf সংযোজন |

### প্রমাণীকরণ প্রবাহ

```
SSH ক্লায়েন্ট
  │
  ▼
sshd  ──── 1. পাবলিক-কী প্রমাণীকরণ (বিদ্যমান কী জোড়া)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. প্রম্পট: "Google Authenticator code: "
  ├── 3. ব্যবহারকারী অ্যাপ থেকে ৬-সংখ্যার TOTP প্রবেশ করান
  ├── 4. oathtool ~/.google_authenticator-এর বিপরীতে কোড যাচাই করে
  │
  ├─ সাফল্য → সেশন খোলা হয়েছে; auth.info স্থানীয়ভাবে লগ ও ফরওয়ার্ড করা হয়েছে
  └─ ব্যর্থতা → সেশন বন্ধ হয়েছে; auth.warning স্থানীয়ভাবে লগ ও ফরওয়ার্ড করা হয়েছে
```

## প্রয়োজনীয়তাসমূহ

- OpenBSD 7.x (7.4 এবং 7.5-এ পরীক্ষিত)
- root বা `doas` অ্যাক্সেস
- `oath-toolkit` প্যাকেজ (`pkg_add oath-toolkit`) — `oathtool` সরবরাহ করে
- হোস্ট থেকে পৌঁছানো যায় এমন দূরবর্তী syslog সার্ভার (rsyslog, syslog-ng ইত্যাদি)
- ব্যবহারকারীদের SSH পাবলিক কী ইতিমধ্যে ইনস্টল করা থাকতে হবে (`~/.ssh/authorized_keys`)

## দ্রুত শুরু (স্বয়ংক্রিয়)

```sh
doas sh setup.sh
```

স্ক্রিপ্টটি যা করবে:

1. `pkg_add` এর মাধ্যমে `oath-toolkit` ইনস্টল করবে।
2. `login_totp` কে `/usr/local/libexec/auth/login_totp`-এ কপি করবে।
3. `/etc/login.conf`-এ একটি `totp` লগইন ক্লাস যোগ করবে।
4. `/etc/ssh/sshd_config` প্যাচ করবে।
5. `/etc/syslog.conf`-এ দূরবর্তী ফরওয়ার্ডিং নিয়ম যোগ করবে।
6. `syslogd` এবং `sshd` পুনরায় চালু করবে।
7. ঐচ্ছিকভাবে একজন ব্যবহারকারীকে নথিভুক্ত করতে `google-authenticator-setup.sh` চালাবে।

## ম্যানুয়াল ইনস্টলেশন

### ১. oath-toolkit ইনস্টল করুন

```sh
doas pkg_add oath-toolkit
```

### ২. BSD Auth লগইন স্ক্রিপ্ট ইনস্টল করুন

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### ৩. `totp` লগইন ক্লাস যোগ করুন

নিচেরটি `/etc/login.conf`-এ যোগ করুন:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

তারপর login.conf ডেটাবেস পুনর্নির্মাণ করুন:

```sh
doas cap_mkdb /etc/login.conf
```

### ৪. sshd কনফিগার করুন

`sshd_config.snippet`-এর লাইনগুলো `/etc/ssh/sshd_config`-এ যোগ করুন।
গুরুত্বপূর্ণ ডিরেক্টিভগুলো হলো:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

sshd যাচাই করুন এবং পুনরায় চালু করুন:

```sh
doas sshd -t          # কনফিগ যাচাই করুন
doas rcctl restart sshd
```

### ৫. দূরবর্তী syslog কনফিগার করুন

`syslog.conf.snippet`-এর লাইনগুলো `/etc/syslog.conf`-এ যোগ করুন,
`REMOTE_SYSLOG_SERVER` আপনার প্রকৃত সার্ভারের ঠিকানা দিয়ে প্রতিস্থাপন করুন।

**UDP (ডিফল্ট):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (আরও নির্ভরযোগ্য):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

TCP-এর জন্য, `/etc/rc.conf.local`-এ TCP সক্ষম করুন:

```
syslogd_flags="-T"
```

syslogd পুনরায় লোড করুন:

```sh
doas rcctl restart syslogd
```

### ৬. ব্যবহারকারী নথিভুক্ত করুন

প্রতি-ব্যবহারকারী নথিভুক্তি স্ক্রিপ্ট চালান (root হিসেবে বা ব্যবহারকারী নিজে):

```sh
doas sh google-authenticator-setup.sh
```

স্ক্রিপ্টটি:
1. একটি এলোমেলো ১৬০-বিট TOTP সিক্রেট তৈরি করে।
2. এটি `~/.google_authenticator`-এ (মোড 0600) লেখে।
3. একটি `otpauth://` URI এবং টার্মিনাল QR কোড প্রিন্ট করে (`qrencode` ইনস্টল থাকলে)।
4. ব্যবহারকারীকে `totp` লগইন ক্লাসে নিযুক্ত করে।

QR কোড স্ক্যান করুন (বা URI পেস্ট করুন) Google Authenticator, Aegis,
Authy, বা যেকোনো TOTP-সামঞ্জস্যপূর্ণ অ্যাপে।

### ৭. ব্যবহারকারীদের totp লগইন ক্লাসে নিযুক্ত করুন

যদি আপনি `google-authenticator-setup.sh` ব্যবহার না করেন, ক্লাস ম্যানুয়ালি নিযুক্ত করুন:

```sh
doas usermod -L totp alice
```

## সেটআপ যাচাই করা

### oathtool স্থানীয়ভাবে পরীক্ষা করুন

```sh
# একজন ব্যবহারকারীর সিক্রেটের জন্য বর্তমান TOTP কোড তৈরি করুন:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

প্রমাণক অ্যাপে দেখানো কোডের সাথে তুলনা করুন — এগুলো মিলতে হবে।

### syslog ফরওয়ার্ডিং পরীক্ষা করুন

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

এই বার্তাগুলো দূরবর্তী syslog সার্ভারে পৌঁছায় কিনা যাচাই করুন।

### SSH লগইন পরীক্ষা করুন

একটি **নতুন** SSH সেশন খুলুন (কিছু ঠিক করার প্রয়োজন হলে বিদ্যমান সেশনটি খোলা রাখুন):

```sh
ssh -v alice@your-server
```

প্রত্যাশিত প্রবাহ:
1. sshd আপনার পাবলিক কী গ্রহণ করে।
2. আপনি প্রম্পট দেখেন: `Google Authenticator code: `
3. প্রমাণক অ্যাপ থেকে ৬-সংখ্যার কোড প্রবেশ করান।
4. লগইন সফল হয় বা ব্যর্থ হয়; ফলাফল `/var/log/authlog`-এ এবং
   দূরবর্তী syslog সার্ভারে দেখা যায়।

## ব্যর্থ-লগইন লগ ফরম্যাট

`login_totp` যখন একটি TOTP কোড প্রত্যাখ্যান করে, তখন এটি `logger(1)` এর মাধ্যমে একটি বার্তা পাঠায়:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

এই বার্তাটি লেখা হয়:
- স্থানীয় syslog-এ (OpenBSD-তে `/var/log/authlog`)।
- `syslog.conf`-এ `auth.info` নিয়মের মাধ্যমে দূরবর্তী syslog সার্ভারে।

অতিরিক্ত প্রমাণীকরণ ব্যর্থতার ঘটনাগুলো sshd নিজেই লগ করে:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## ফাইল রেফারেন্স

### `login_totp` (BSD Auth ব্যাকএন্ড)

- **অবস্থান:** `/usr/local/libexec/auth/login_totp`
- **অনুমতি:** `root:auth 0550`
- **সিক্রেট ফাইল:** `~/.google_authenticator` (প্রথম লাইন = base-32 TOTP সিক্রেট)
- **লগিং:** ব্যর্থতায় `logger -p auth.warning`, সাফল্যে `auth.info`
- **সময় সহনশীলতা:** ±1 × ৩০-সেকেন্ড ধাপ (`TOTP_WINDOW` এর মাধ্যমে কনফিগারযোগ্য)

### `~/.google_authenticator`

একটি সাধারণ-পাঠ্য ফাইল; **প্রথম লাইনটি** অবশ্যই base-32 TOTP সিক্রেট হতে হবে।
অতিরিক্ত লাইন (মন্তব্য) `login_totp` দ্বারা উপেক্ষা করা হয়।

উদাহরণ:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

অনুমতি `0600` হতে হবে, ব্যবহারকারীর মালিকানায়।

## FreeBSD / PAM-ভিত্তিক সেটআপের সাথে পার্থক্য

| বিষয় | FreeBSD | OpenBSD |
|-------|---------|---------|
| প্রমাণীকরণ কাঠামো | PAM (`pam_google_authenticator.so`) | BSD Auth (`login_totp` স্ক্রিপ্ট) |
| লগইন ক্লাস | প্রযোজ্য নয় | `/etc/login.conf` `totp` ক্লাস |
| প্যাকেজ | `security/google-authenticator-pam` | `security/oath-toolkit` |
| syslog ডেমন | `syslogd` / `newsyslog` | `syslogd` (অন্তর্নির্মিত) |
| দূরবর্তী UDP ফরওয়ার্ড | `syslog.conf`-এ `@host` | `syslog.conf`-এ `@host` |
| দূরবর্তী TCP ফরওয়ার্ড | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## সমস্যা সমাধান

**"oathtool not found"**
oath-toolkit ইনস্টল করুন: `doas pkg_add oath-toolkit`

**"No secret file for user"**
সেই ব্যবহারকারীর জন্য `google-authenticator-setup.sh` চালান, অথবা ম্যানুয়ালি
প্রথম লাইনে base-32 সিক্রেট সহ `~/.google_authenticator` তৈরি করুন।

**TOTP কোড সবসময় প্রত্যাখ্যাত হচ্ছে**
সিস্টেম ঘড়ি সিঙ্ক্রোনাইজ আছে কিনা নিশ্চিত করুন (OpenBSD-তে `ntpd` ডিফল্টভাবে সক্ষম)।
৩০ সেকেন্ডের বেশি ঘড়ির পার্থক্য প্রতিটি কোড ব্যর্থ করবে।
প্রয়োজনে `login_totp`-এ `TOTP_WINDOW` বাড়ান।

**SSH TOTP কোডের পরিবর্তে পাসওয়ার্ড চাইছে**
যাচাই করুন যে `KbdInteractiveAuthentication yes` এবং
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` উভয়ই
`/etc/ssh/sshd_config`-এ আছে, এবং ব্যবহারকারী `totp` লগইন ক্লাসে আছে
(`doas usermod -L totp <user>`)।

**sshd_config সম্পাদনার পর sshd -t ব্যর্থ হচ্ছে**
`doas sshd -t` চালান এবং sshd পুনরায় চালু করার আগে রিপোর্ট করা ত্রুটিগুলো ঠিক করুন।
`setup.sh` দ্বারা তৈরি ব্যাকআপটি
`/etc/ssh/sshd_config.bak.<timestamp>`-এ আছে।

**দূরবর্তী syslog বার্তা পাচ্ছে না**
1. দূরবর্তী সার্ভারের UDP/TCP পোর্ট 514 পৌঁছানো যাচ্ছে কিনা নিশ্চিত করুন:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. উভয় প্রান্তে ফায়ারওয়াল নিয়ম পরীক্ষা করুন (OpenBSD pf এবং দূরবর্তী সার্ভার)।
3. TCP ফরওয়ার্ডিংয়ের জন্য, নিশ্চিত করুন যে `syslogd_flags="-T"` `/etc/rc.conf.local`-এ আছে
   এবং `syslogd` পুনরায় চালু করা হয়েছে।

## লাইসেন্স

BSD 2-Clause লাইসেন্স। বিস্তারিতের জন্য [LICENSE](../LICENSE) দেখুন।
