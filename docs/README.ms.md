# OpenBSD sshd + Google Authenticator (TOTP)

Pengesahan dua faktor untuk SSH OpenBSD menggunakan Google Authenticator
(TOTP), dengan log log masuk gagal yang dikemukakan ke pelayan syslog jauh.

## Gambaran Keseluruhan

Repositori ini menyediakan:

| Fail | Tujuan |
|------|--------|
| `setup.sh` | Skrip pemasangan automatik — jalankan sekali sebagai root |
| `login_totp` | Backend BSD Auth yang mengesahkan kod TOTP |
| `google-authenticator-setup.sh` | Skrip pendaftaran setiap pengguna |
| `sshd_config.snippet` | Tambahan sshd_config sebagai rujukan |
| `syslog.conf.snippet` | Tambahan syslog.conf untuk pemajuan jauh sebagai rujukan |

### Aliran pengesahan

```
Klien SSH
  │
  ▼
sshd  ──── 1. Pengesahan kunci awam (pasangan kunci sedia ada)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Gesaan: "Google Authenticator code: "
  ├── 3. Pengguna memasukkan 6 digit TOTP daripada aplikasi
  ├── 4. oathtool mengesahkan kod berbanding ~/.google_authenticator
  │
  ├─ BERJAYA → sesi dibuka; auth.info dilog secara tempatan + dimajukan
  └─ GAGAL → sesi ditutup; auth.warning dilog secara tempatan + dimajukan
```

## Keperluan

- OpenBSD 7.x (diuji pada 7.4 dan 7.5)
- Akses root atau `doas`
- Pakej `oath-toolkit` (`pkg_add oath-toolkit`) — menyediakan `oathtool`
- Pelayan syslog jauh yang boleh dicapai daripada hos (rsyslog, syslog-ng, dll.)
- Pengguna mesti sudah memasang kunci awam SSH (`~/.ssh/authorized_keys`)

## Mula cepat (automatik)

```sh
doas sh setup.sh
```

Skrip ini akan:

1. Memasang `oath-toolkit` melalui `pkg_add`.
2. Menyalin `login_totp` ke `/usr/local/libexec/auth/login_totp`.
3. Menambahkan kelas log masuk `totp` ke `/etc/login.conf`.
4. Menampal `/etc/ssh/sshd_config`.
5. Menampal `/etc/syslog.conf` dengan peraturan pemajuan jauh.
6. Memulakan semula `syslogd` dan `sshd`.
7. Pilihan: menjalankan `google-authenticator-setup.sh` untuk mendaftarkan pengguna.

## Pemasangan manual

### 1. Pasang oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Pasang skrip log masuk BSD Auth

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Tambahkan kelas log masuk `totp`

Tambahkan baris berikut ke bahagian akhir `/etc/login.conf`:

```
# Kelas log masuk TOTP (Google Authenticator)
totp:\
    :auth=-totp:\
    :tc=default:
```

Kemudian bina semula pangkalan data login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Konfigurasikan sshd

Tambahkan baris daripada `sshd_config.snippet` ke `/etc/ssh/sshd_config`.
Arahan-arahan kritikal adalah:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Sahkan dan mulakan semula sshd:

```sh
doas sshd -t          # sahkan konfigurasi
doas rcctl restart sshd
```

### 5. Konfigurasikan syslog jauh

Tambahkan baris daripada `syslog.conf.snippet` ke `/etc/syslog.conf`, gantikan
`REMOTE_SYSLOG_SERVER` dengan alamat pelayan anda yang sebenar.

**UDP (lalai):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (lebih boleh dipercayai):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Untuk TCP, aktifkan juga TCP dalam `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Muat semula syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Daftarkan pengguna

Jalankan skrip pendaftaran per pengguna (sebagai root atau sebagai pengguna itu sendiri):

```sh
doas sh google-authenticator-setup.sh
```

Skrip ini akan:
1. Menjana rahsia TOTP 160-bit rawak.
2. Menulisnya ke `~/.google_authenticator` (mod 0600).
3. Mencetak URI `otpauth://` dan kod QR di terminal (jika `qrencode` dipasang).
4. Menetapkan pengguna ke kelas log masuk `totp`.

Imbas kod QR (atau tampal URI) ke dalam Google Authenticator, Aegis,
Authy, atau mana-mana aplikasi yang serasi dengan TOTP.

### 7. Tetapkan pengguna ke kelas log masuk totp

Jika anda tidak menggunakan `google-authenticator-setup.sh`, tetapkan kelas secara manual:

```sh
doas usermod -L totp alice
```

## Mengesahkan pemasangan

### Uji oathtool secara tempatan

```sh
# Jana kod TOTP semasa untuk rahsia pengguna:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Bandingkan ini dengan kod yang ditunjukkan dalam aplikasi pengesah — ia sepatutnya sepadan.

### Uji pemajuan syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Periksa bahawa mesej-mesej ini tiba di pelayan syslog jauh.

### Uji log masuk SSH

Buka sesi SSH **baharu** (pastikan sesi sedia ada kekal terbuka sekiranya ada yang perlu diperbaiki):

```sh
ssh -v alice@your-server
```

Aliran yang dijangka:
1. sshd menerima kunci awam anda.
2. Anda melihat gesaan: `Google Authenticator code: `
3. Masukkan kod 6 digit daripada aplikasi pengesah.
4. Log masuk berjaya atau gagal; hasilnya muncul dalam `/var/log/authlog` dan
   di pelayan syslog jauh.

## Format log log masuk gagal

Apabila `login_totp` menolak kod TOTP, ia mengeluarkan mesej melalui `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Mesej ini ditulis ke:
- Syslog tempatan (`/var/log/authlog` pada OpenBSD).
- Pelayan syslog jauh melalui peraturan `auth.info` dalam `syslog.conf`.

Peristiwa pengesahan gagal tambahan dilog oleh sshd itu sendiri:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Rujukan fail

### `login_totp` (backend BSD Auth)

- **Lokasi:** `/usr/local/libexec/auth/login_totp`
- **Kebenaran:** `root:auth 0550`
- **Fail rahsia:** `~/.google_authenticator` (baris pertama = rahsia TOTP base-32)
- **Pengelogan:** `logger -p auth.warning` semasa gagal, `auth.info` semasa berjaya
- **Toleransi masa:** ±1 × langkah 30 saat (boleh dikonfigurasikan melalui `TOTP_WINDOW`)

### `~/.google_authenticator`

Fail teks biasa; **baris pertama** mesti merupakan rahsia TOTP base-32.
Baris tambahan (ulasan) diabaikan oleh `login_totp`.

Contoh:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Kebenaran mesti `0600`, dimiliki oleh pengguna.

## Perbezaan daripada FreeBSD / persediaan berasaskan PAM

| Topik | FreeBSD | OpenBSD |
|-------|---------|---------|
| Rangka kerja pengesahan | PAM (`pam_google_authenticator.so`) | BSD Auth (skrip `login_totp`) |
| Kelas log masuk | tiada | kelas `totp` dalam `/etc/login.conf` |
| Pakej | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Daemon syslog | `syslogd` / `newsyslog` | `syslogd` (terbina dalam) |
| Pemajuan UDP jauh | `@host` dalam `syslog.conf` | `@host` dalam `syslog.conf` |
| Pemajuan TCP jauh | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Penyelesaian masalah

**"oathtool not found"**
Pasang oath-toolkit: `doas pkg_add oath-toolkit`

**"No secret file for user"**
Jalankan `google-authenticator-setup.sh` untuk pengguna tersebut, atau buat
`~/.google_authenticator` secara manual dengan rahsia base-32 pada baris pertama.

**Kod TOTP sentiasa ditolak**
Pastikan jam sistem disegerakkan (`ntpd` diaktifkan secara lalai pada OpenBSD).
Penyimpangan jam lebih daripada 30 saat akan menyebabkan setiap kod gagal. Tingkatkan `TOTP_WINDOW`
dalam `login_totp` jika perlu.

**SSH meminta kata laluan dan bukannya kod TOTP**
Sahkan bahawa `KbdInteractiveAuthentication yes` dan
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` kedua-duanya
terdapat dalam `/etc/ssh/sshd_config`, dan bahawa pengguna berada dalam kelas
log masuk `totp` (`doas usermod -L totp <user>`).

**sshd -t gagal selepas mengedit sshd_config**
Jalankan `doas sshd -t` dan betulkan sebarang ralat yang dilaporkan sebelum memulakan semula sshd.
Sandaran yang dibuat oleh `setup.sh` berada di
`/etc/ssh/sshd_config.bak.<timestamp>`.

**Syslog jauh tidak menerima mesej**
1. Sahkan bahawa port UDP/TCP 514 pelayan jauh boleh dicapai:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Periksa peraturan firewall pada kedua-dua hujung (OpenBSD pf dan pelayan jauh).
3. Untuk pemajuan TCP, sahkan bahawa `syslogd_flags="-T"` terdapat dalam
   `/etc/rc.conf.local` dan `syslogd` telah dimulakan semula.

## Lesen

Lesen BSD 2-Clause. Lihat [LICENSE](../LICENSE) untuk butiran.
