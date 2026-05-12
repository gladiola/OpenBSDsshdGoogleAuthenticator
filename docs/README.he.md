# OpenBSD sshd + Google Authenticator (TOTP)

אימות דו-שלבי עבור OpenBSD SSH באמצעות Google Authenticator
(TOTP), עם העברת לוגים של כניסות כושלות לשרת syslog מרוחק.

## סקירה כללית

מאגר זה מספק:

| קובץ | מטרה |
|------|---------|
| `setup.sh` | סקריפט התקנה אוטומטי — מריצים פעם אחת כ-root |
| `login_totp` | ממשק BSD Auth האחורי המאמת את קוד TOTP |
| `google-authenticator-setup.sh` | סקריפט רישום למשתמש בודד |
| `sshd_config.snippet` | תוספות sshd_config לעיון |
| `syslog.conf.snippet` | תוספות syslog.conf לעיון עבור העברה מרוחקת |

### זרימת האימות

```
SSH client
  │
  ▼
sshd  ──── 1. אימות מפתח ציבורי (זוג מפתחות קיים)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. הנחייה: "Google Authenticator code: "
  ├── 3. המשתמש מזין קוד TOTP בן 6 ספרות מהאפליקציה
  ├── 4. oathtool מאמת את הקוד מול ~/.google_authenticator
  │
  ├─ הצלחה → הפעלת סשן; auth.info נרשם מקומית + מועבר
  └─ כישלון → סגירת סשן; auth.warning נרשם מקומית + מועבר
```

## דרישות

- OpenBSD 7.x (נבדק על 7.4 ו-7.5)
- גישת root או `doas`
- חבילת `oath-toolkit` (`pkg_add oath-toolkit`) — מספקת את `oathtool`
- שרת syslog מרוחק הנגיש מהמארח (rsyslog, syslog-ng, וכו')
- למשתמשים חייב להיות מפתח SSH ציבורי מותקן (`~/.ssh/authorized_keys`)

## התחלה מהירה (אוטומטי)

```sh
doas sh setup.sh
```

הסקריפט יבצע:

1. התקנת `oath-toolkit` דרך `pkg_add`.
2. העתקת `login_totp` ל-`/usr/local/libexec/auth/login_totp`.
3. הוספת מחלקת התחברות `totp` ל-`/etc/login.conf`.
4. עדכון `/etc/ssh/sshd_config`.
5. עדכון `/etc/syslog.conf` עם כללי העברה מרוחקת.
6. הפעלה מחדש של `syslogd` ו-`sshd`.
7. הרצת `google-authenticator-setup.sh` אופציונלית לרישום משתמש.

## התקנה ידנית

### 1. התקן את oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. התקן את סקריפט התחברות BSD Auth

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. הוסף את מחלקת ההתחברות `totp`

הוסף את הבא ל-`/etc/login.conf`:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

לאחר מכן בנה מחדש את מסד הנתונים של login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. הגדר את sshd

הוסף את השורות מ-`sshd_config.snippet` ל-`/etc/ssh/sshd_config`.
ההנחיות הקריטיות הן:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

אמת והפעל מחדש את sshd:

```sh
doas sshd -t          # אימות ההגדרות
doas rcctl restart sshd
```

### 5. הגדר syslog מרוחק

הוסף את השורות מ-`syslog.conf.snippet` ל-`/etc/syslog.conf`, תוך החלפת
`REMOTE_SYSLOG_SERVER` בכתובת השרת בפועל.

**UDP (ברירת מחדל):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (אמין יותר):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

עבור TCP, הפעל גם TCP ב-`/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

טען מחדש את syslogd:

```sh
doas rcctl restart syslogd
```

### 6. רשום משתמשים

הרץ את סקריפט הרישום הפרטני (כ-root או כהמשתמש עצמו):

```sh
doas sh google-authenticator-setup.sh
```

הסקריפט:
1. מייצר סוד TOTP אקראי בגודל 160 ביט.
2. כותב אותו ל-`~/.google_authenticator` (הרשאה 0600).
3. מדפיס URI מסוג `otpauth://` וקוד QR בטרמינל (אם `qrencode` מותקן).
4. מקצה את המשתמש למחלקת ההתחברות `totp`.

סרוק את קוד ה-QR (או הדבק את ה-URI) לתוך Google Authenticator, Aegis,
Authy, או כל אפליקציה תואמת TOTP.

### 7. הקצה משתמשים למחלקת ההתחברות totp

אם לא השתמשת ב-`google-authenticator-setup.sh`, הקצה את המחלקה ידנית:

```sh
doas usermod -L totp alice
```

## אימות ההגדרה

### בדוק את oathtool מקומית

```sh
# ייצר את קוד TOTP הנוכחי עבור הסוד של משתמש:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

השווה זאת עם הקוד המוצג באפליקציית האימות — הם צריכים להיות זהים.

### בדוק העברת syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

ודא שהודעות אלה מגיעות לשרת syslog המרוחק.

### בדוק כניסת SSH

פתח סשן SSH **חדש** (השאר את הסשן הנוכחי שלך פתוח למקרה שמשהו צריך תיקון):

```sh
ssh -v alice@your-server
```

זרימה צפויה:
1. sshd מקבל את המפתח הציבורי שלך.
2. אתה רואה את ההנחייה: `Google Authenticator code: `
3. הזן את הקוד בן 6 הספרות מאפליקציית האימות.
4. ההתחברות מצליחה או נכשלת; התוצאה מופיעה ב-`/var/log/authlog` ובשרת syslog המרוחק.

## פורמט לוג כניסה כושלת

כאשר `login_totp` דוחה קוד TOTP, הוא פולט הודעה דרך `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

הודעה זו נכתבת ל:
- syslog המקומי (`/var/log/authlog` ב-OpenBSD).
- שרת syslog המרוחק דרך כלל `auth.info` ב-`syslog.conf`.

אירועי כישלון אימות נוספים נרשמים על ידי sshd עצמו:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## עיון בקבצים

### `login_totp` (ממשק BSD Auth האחורי)

- **מיקום:** `/usr/local/libexec/auth/login_totp`
- **הרשאות:** `root:auth 0550`
- **קובץ סוד:** `~/.google_authenticator` (שורה ראשונה = סוד TOTP בקידוד base-32)
- **רישום:** `logger -p auth.warning` בכישלון, `auth.info` בהצלחה
- **סבלנות זמן:** ±1 × צעד 30 שניות (ניתן להגדרה דרך `TOTP_WINDOW`)

### `~/.google_authenticator`

קובץ טקסט רגיל; **השורה הראשונה** חייבת להיות סוד TOTP בקידוד base-32.
שורות נוספות (הערות) מתעלמות מהן על ידי `login_totp`.

דוגמה:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

ההרשאות חייבות להיות `0600`, בבעלות המשתמש.

## הבדלים מהגדרות FreeBSD / PAM

| נושא | FreeBSD | OpenBSD |
|-------|---------|---------|
| מסגרת אימות | PAM (`pam_google_authenticator.so`) | BSD Auth (סקריפט `login_totp`) |
| מחלקת התחברות | לא רלוונטי | מחלקת `totp` ב-`/etc/login.conf` |
| חבילה | `security/google-authenticator-pam` | `security/oath-toolkit` |
| שד syslog | `syslogd` / `newsyslog` | `syslogd` (מובנה) |
| העברת UDP מרוחקת | `@host` ב-`syslog.conf` | `@host` ב-`syslog.conf` |
| העברת TCP מרוחקת | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## פתרון בעיות

**"oathtool not found"**
התקן את oath-toolkit: `doas pkg_add oath-toolkit`

**"No secret file for user"**
הרץ את `google-authenticator-setup.sh` עבור אותו משתמש, או צור ידנית
`~/.google_authenticator` עם הסוד בקידוד base-32 בשורה הראשונה.

**קודי TOTP נדחים תמיד**
ודא ששעון המערכת מסונכרן (`ntpd` מופעל ב-OpenBSD כברירת מחדל).
חריגה של יותר מ-30 שניות בשעון תגרום לכישלון כל קוד.
הגדל את `TOTP_WINDOW` ב-`login_totp` אם נדרש.

**SSH מבקש סיסמה במקום קוד TOTP**
ודא ש-`KbdInteractiveAuthentication yes` ו-
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` נמצאים שניהם
ב-`/etc/ssh/sshd_config`, ושהמשתמש נמצא במחלקת ההתחברות `totp`
(`doas usermod -L totp <user>`).

**sshd -t נכשל לאחר עריכת sshd_config**
הרץ `doas sshd -t` ותקן כל שגיאה מדווחת לפני הפעלה מחדש של sshd.
הגיבוי שנוצר על ידי `setup.sh` נמצא ב-
`/etc/ssh/sshd_config.bak.<timestamp>`.

**syslog מרוחק אינו מקבל הודעות**
1. ודא שניתן להגיע ליציאת UDP/TCP 514 של השרת המרוחק:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. בדוק כללי חומת אש משני הצדדים (OpenBSD pf והשרת המרוחק).
3. להעברת TCP, ודא ש-`syslogd_flags="-T"` נמצא ב-
   `/etc/rc.conf.local` וש-`syslogd` הופעל מחדש.

## רישיון

רישיון BSD דו-סעיפי. ראה [LICENSE](LICENSE) לפרטים.
