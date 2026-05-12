# OpenBSD sshd + Google Authenticator (TOTP)

Έλεγχος ταυτότητας δύο παραγόντων για SSH σε OpenBSD με χρήση Google Authenticator
(TOTP), με προώθηση καταγραφών αποτυχημένων συνδέσεων σε απομακρυσμένο διακομιστή syslog.

## Επισκόπηση

Αυτό το αποθετήριο παρέχει:

| Αρχείο | Σκοπός |
|--------|--------|
| `setup.sh` | Αυτοματοποιημένο σενάριο εγκατάστασης — εκτελείται μία φορά ως root |
| `login_totp` | Σύστημα υποστήριξης BSD Auth που επαληθεύει τον κωδικό TOTP |
| `google-authenticator-setup.sh` | Σενάριο εγγραφής ανά χρήστη |
| `sshd_config.snippet` | Προτεινόμενες προσθήκες στο sshd_config |
| `syslog.conf.snippet` | Προτεινόμενες προσθήκες στο syslog.conf για απομακρυσμένη προώθηση |

### Ροή ελέγχου ταυτότητας

```
SSH client
  │
  ▼
sshd  ──── 1. Έλεγχος ταυτότητας με δημόσιο κλειδί (υπάρχον ζεύγος κλειδιών)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Προτροπή: "Google Authenticator code: "
  ├── 3. Ο χρήστης εισάγει τον 6ψήφιο κωδικό TOTP από την εφαρμογή
  ├── 4. Το oathtool επαληθεύει τον κωδικό έναντι του ~/.google_authenticator
  │
  ├─ SUCCESS → η συνεδρία ανοίγει· auth.info καταγράφεται τοπικά + προωθείται
  └─ FAILURE → η συνεδρία κλείνει· auth.warning καταγράφεται τοπικά + προωθείται
```

## Απαιτήσεις

- OpenBSD 7.x (δοκιμασμένο σε 7.4 και 7.5)
- Πρόσβαση root ή `doas`
- Πακέτο `oath-toolkit` (`pkg_add oath-toolkit`) — παρέχει το `oathtool`
- Απομακρυσμένος διακομιστής syslog προσβάσιμος από τον κεντρικό υπολογιστή (rsyslog, syslog-ng κ.λπ.)
- Οι χρήστες πρέπει να έχουν ήδη εγκατεστημένο δημόσιο κλειδί SSH (`~/.ssh/authorized_keys`)

## Γρήγορη εκκίνηση (αυτόματη)

```sh
doas sh setup.sh
```

Το σενάριο θα:

1. Εγκαταστήσει το `oath-toolkit` μέσω `pkg_add`.
2. Αντιγράψει το `login_totp` στο `/usr/local/libexec/auth/login_totp`.
3. Προσθέσει κλάση σύνδεσης `totp` στο `/etc/login.conf`.
4. Τροποποιήσει το `/etc/ssh/sshd_config`.
5. Τροποποιήσει το `/etc/syslog.conf` με κανόνες απομακρυσμένης προώθησης.
6. Επανεκκινήσει το `syslogd` και το `sshd`.
7. Προαιρετικά εκτελέσει το `google-authenticator-setup.sh` για εγγραφή χρήστη.

## Χειροκίνητη εγκατάσταση

### 1. Εγκατάσταση oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Εγκατάσταση του σεναρίου BSD Auth login

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Προσθήκη κλάσης σύνδεσης `totp`

Προσθέστε τα παρακάτω στο τέλος του αρχείου `/etc/login.conf`:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

Στη συνέχεια ανακατασκευάστε τη βάση δεδομένων login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Ρύθμιση παραμέτρων sshd

Προσθέστε τις γραμμές από το `sshd_config.snippet` στο `/etc/ssh/sshd_config`.
Οι κρίσιμες οδηγίες είναι:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Επαληθεύστε και επανεκκινήστε το sshd:

```sh
doas sshd -t          # επαλήθευση ρύθμισης παραμέτρων
doas rcctl restart sshd
```

### 5. Ρύθμιση απομακρυσμένου syslog

Προσθέστε τις γραμμές από το `syslog.conf.snippet` στο `/etc/syslog.conf`, αντικαθιστώντας
το `REMOTE_SYSLOG_SERVER` με την πραγματική διεύθυνση του διακομιστή σας.

**UDP (προεπιλογή):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (πιο αξιόπιστο):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Για TCP, ενεργοποιήστε επίσης το TCP στο `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Επαναφορτώστε το syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Εγγραφή χρηστών

Εκτελέστε το σενάριο εγγραφής ανά χρήστη (ως root ή ως ο ίδιος ο χρήστης):

```sh
doas sh google-authenticator-setup.sh
```

Το σενάριο:
1. Δημιουργεί ένα τυχαίο μυστικό TOTP 160 bit.
2. Το γράφει στο `~/.google_authenticator` (mode 0600).
3. Εκτυπώνει ένα URI `otpauth://` και έναν κωδικό QR στο τερματικό (εάν είναι εγκατεστημένο το `qrencode`).
4. Αναθέτει στον χρήστη την κλάση σύνδεσης `totp`.

Σαρώστε τον κωδικό QR (ή επικολλήστε το URI) στο Google Authenticator, Aegis,
Authy ή οποιαδήποτε εφαρμογή συμβατή με TOTP.

### 7. Ανάθεση χρηστών στην κλάση σύνδεσης totp

Εάν δεν χρησιμοποιήσατε το `google-authenticator-setup.sh`, αναθέστε την κλάση χειροκίνητα:

```sh
doas usermod -L totp alice
```

## Επαλήθευση της εγκατάστασης

### Τοπική δοκιμή oathtool

```sh
# Δημιουργία του τρέχοντος κωδικού TOTP για το μυστικό ενός χρήστη:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Συγκρίνετε αυτόν τον κωδικό με τον κωδικό που εμφανίζεται στην εφαρμογή επαλήθευσης — πρέπει να ταιριάζουν.

### Δοκιμή προώθησης syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Επαληθεύστε ότι αυτά τα μηνύματα φτάνουν στον απομακρυσμένο διακομιστή syslog.

### Δοκιμή σύνδεσης SSH

Ανοίξτε μια **νέα** συνεδρία SSH (κρατήστε ανοιχτή την υπάρχουσα συνεδρία σε περίπτωση
που χρειαστεί να διορθωθεί κάτι):

```sh
ssh -v alice@your-server
```

Αναμενόμενη ροή:
1. Το sshd αποδέχεται το δημόσιο κλειδί σας.
2. Εμφανίζεται η προτροπή: `Google Authenticator code: `
3. Εισαγάγετε τον 6ψήφιο κωδικό από την εφαρμογή επαλήθευσης.
4. Η σύνδεση επιτυγχάνει ή αποτυγχάνει· το αποτέλεσμα εμφανίζεται στο `/var/log/authlog` και
   στον απομακρυσμένο διακομιστή syslog.

## Μορφή καταγραφής αποτυχημένης σύνδεσης

Όταν το `login_totp` απορρίπτει έναν κωδικό TOTP, εκπέμπει ένα μήνυμα μέσω `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Αυτό το μήνυμα γράφεται στο:
- Τοπικό syslog (`/var/log/authlog` στο OpenBSD).
- Απομακρυσμένο διακομιστή syslog μέσω του κανόνα `auth.info` στο `syslog.conf`.

Επιπλέον συμβάντα αποτυχημένης επαλήθευσης καταγράφονται από το ίδιο το sshd:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Αναφορά αρχείων

### `login_totp` (σύστημα υποστήριξης BSD Auth)

- **Τοποθεσία:** `/usr/local/libexec/auth/login_totp`
- **Άδειες:** `root:auth 0550`
- **Αρχείο μυστικού:** `~/.google_authenticator` (πρώτη γραμμή = μυστικό TOTP σε base-32)
- **Καταγραφή:** `logger -p auth.warning` σε αποτυχία, `auth.info` σε επιτυχία
- **Ανοχή χρόνου:** ±1 × 30-δευτερόλεπτο βήμα (ρυθμιζόμενο μέσω `TOTP_WINDOW`)

### `~/.google_authenticator`

Αρχείο απλού κειμένου· η **πρώτη γραμμή** πρέπει να είναι το μυστικό TOTP σε base-32.
Πρόσθετες γραμμές (σχόλια) αγνοούνται από το `login_totp`.

Παράδειγμα:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Οι άδειες πρέπει να είναι `0600`, με ιδιοκτήτη τον χρήστη.

## Διαφορές από FreeBSD / εγκαταστάσεις βασισμένες σε PAM

| Θέμα | FreeBSD | OpenBSD |
|------|---------|---------|
| Πλαίσιο ελέγχου ταυτότητας | PAM (`pam_google_authenticator.so`) | BSD Auth (σενάριο `login_totp`) |
| Κλάση σύνδεσης | δ/α | Κλάση `totp` στο `/etc/login.conf` |
| Πακέτο | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Δαίμονας syslog | `syslogd` / `newsyslog` | `syslogd` (ενσωματωμένο) |
| Απομακρυσμένη προώθηση UDP | `@host` στο `syslog.conf` | `@host` στο `syslog.conf` |
| Απομακρυσμένη προώθηση TCP | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Αντιμετώπιση προβλημάτων

**«oathtool not found»**
Εγκαταστήστε το oath-toolkit: `doas pkg_add oath-toolkit`

**«No secret file for user»**
Εκτελέστε το `google-authenticator-setup.sh` για αυτόν τον χρήστη, ή δημιουργήστε χειροκίνητα
το `~/.google_authenticator` με το μυστικό base-32 στην πρώτη γραμμή.

**Οι κωδικοί TOTP απορρίπτονται πάντα**
Βεβαιωθείτε ότι το ρολόι του συστήματος είναι συγχρονισμένο (`ntpd` είναι ενεργοποιημένο στο OpenBSD από
προεπιλογή). Απόκλιση ρολογιού μεγαλύτερη από 30 δευτερόλεπτα θα προκαλέσει αποτυχία κάθε κωδικού.
Αυξήστε το `TOTP_WINDOW` στο `login_totp` εάν χρειάζεται.

**Το SSH ζητά κωδικό πρόσβασης αντί για κωδικό TOTP**
Βεβαιωθείτε ότι τόσο το `KbdInteractiveAuthentication yes` όσο και το
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` υπάρχουν
στο `/etc/ssh/sshd_config`, και ότι ο χρήστης ανήκει στην κλάση `totp`
(`doas usermod -L totp <user>`).

**Το sshd -t αποτυγχάνει μετά την επεξεργασία του sshd_config**
Εκτελέστε `doas sshd -t` και διορθώστε τυχόν αναφερόμενα σφάλματα πριν επανεκκινήσετε το sshd.
Το αντίγραφο ασφαλείας που δημιουργήθηκε από το `setup.sh` βρίσκεται στο
`/etc/ssh/sshd_config.bak.<timestamp>`.

**Ο απομακρυσμένος syslog δεν λαμβάνει μηνύματα**
1. Επιβεβαιώστε ότι η θύρα UDP/TCP 514 του απομακρυσμένου διακομιστή είναι προσβάσιμη:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Ελέγξτε τους κανόνες τείχους προστασίας και στις δύο πλευρές (OpenBSD pf και απομακρυσμένος διακομιστής).
3. Για προώθηση TCP, επιβεβαιώστε ότι το `syslogd_flags="-T"` βρίσκεται στο
   `/etc/rc.conf.local` και ότι το `syslogd` έχει επανεκκινηθεί.

## Άδεια χρήσης

BSD 2-Clause License. Δείτε το αρχείο [LICENSE](../LICENSE) για λεπτομέρειες.
