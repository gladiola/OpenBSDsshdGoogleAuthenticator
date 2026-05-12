# OpenBSD sshd + Google Authenticator (TOTP)

Autentikasi dua faktor untuk SSH OpenBSD menggunakan Google Authenticator
(TOTP), dengan log login gagal yang diteruskan ke server syslog jarak jauh.

## Ikhtisar

Repositori ini menyediakan:

| Berkas | Tujuan |
|--------|--------|
| `setup.sh` | Skrip pemasangan otomatis — jalankan sekali sebagai root |
| `login_totp` | Backend BSD Auth yang memverifikasi kode TOTP |
| `google-authenticator-setup.sh` | Skrip pendaftaran per pengguna |
| `sshd_config.snippet` | Tambahan sshd_config sebagai referensi |
| `syslog.conf.snippet` | Tambahan syslog.conf untuk penerusan jarak jauh sebagai referensi |

### Alur autentikasi

```
Klien SSH
  │
  ▼
sshd  ──── 1. Autentikasi kunci publik (pasangan kunci yang sudah ada)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Prompt: "Google Authenticator code: "
  ├── 3. Pengguna memasukkan 6 digit TOTP dari aplikasi
  ├── 4. oathtool memverifikasi kode terhadap ~/.google_authenticator
  │
  ├─ BERHASIL → sesi dibuka; auth.info dicatat lokal + diteruskan
  └─ GAGAL → sesi ditutup; auth.warning dicatat lokal + diteruskan
```

## Persyaratan

- OpenBSD 7.x (diuji pada 7.4 dan 7.5)
- Akses root atau `doas`
- Paket `oath-toolkit` (`pkg_add oath-toolkit`) — menyediakan `oathtool`
- Server syslog jarak jauh yang dapat dijangkau dari host (rsyslog, syslog-ng, dll.)
- Pengguna harus sudah memasang kunci publik SSH (`~/.ssh/authorized_keys`)

## Mulai cepat (otomatis)

```sh
doas sh setup.sh
```

Skrip ini akan:

1. Memasang `oath-toolkit` melalui `pkg_add`.
2. Menyalin `login_totp` ke `/usr/local/libexec/auth/login_totp`.
3. Menambahkan kelas login `totp` ke `/etc/login.conf`.
4. Memodifikasi `/etc/ssh/sshd_config`.
5. Memodifikasi `/etc/syslog.conf` dengan aturan penerusan jarak jauh.
6. Memulai ulang `syslogd` dan `sshd`.
7. Opsional: menjalankan `google-authenticator-setup.sh` untuk mendaftarkan pengguna.

## Pemasangan manual

### 1. Pasang oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Pasang skrip login BSD Auth

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Tambahkan kelas login `totp`

Tambahkan baris berikut ke bagian akhir `/etc/login.conf`:

```
# Kelas login TOTP (Google Authenticator)
totp:\
    :auth=-totp:\
    :tc=default:
```

Kemudian bangun ulang basis data login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Konfigurasi sshd

Tambahkan baris dari `sshd_config.snippet` ke `/etc/ssh/sshd_config`.
Direktif-direktif penting adalah:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Verifikasi dan mulai ulang sshd:

```sh
doas sshd -t          # verifikasi konfigurasi
doas rcctl restart sshd
```

### 5. Konfigurasi syslog jarak jauh

Tambahkan baris dari `syslog.conf.snippet` ke `/etc/syslog.conf`, ganti
`REMOTE_SYSLOG_SERVER` dengan alamat server Anda yang sebenarnya.

**UDP (default):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (lebih andal):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Untuk TCP, aktifkan juga TCP di `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Muat ulang syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Daftarkan pengguna

Jalankan skrip pendaftaran per pengguna (sebagai root atau sebagai pengguna itu sendiri):

```sh
doas sh google-authenticator-setup.sh
```

Skrip ini akan:
1. Menghasilkan rahasia TOTP 160-bit acak.
2. Menulisnya ke `~/.google_authenticator` (mode 0600).
3. Mencetak URI `otpauth://` dan kode QR di terminal (jika `qrencode` terpasang).
4. Menetapkan pengguna ke kelas login `totp`.

Pindai kode QR (atau tempelkan URI) ke Google Authenticator, Aegis,
Authy, atau aplikasi yang kompatibel dengan TOTP apa pun.

### 7. Tetapkan pengguna ke kelas login totp

Jika Anda tidak menggunakan `google-authenticator-setup.sh`, tetapkan kelas secara manual:

```sh
doas usermod -L totp alice
```

## Memverifikasi pemasangan

### Uji oathtool secara lokal

```sh
# Hasilkan kode TOTP saat ini untuk rahasia pengguna:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Bandingkan hasilnya dengan kode yang ditampilkan di aplikasi autentikator — keduanya seharusnya cocok.

### Uji penerusan syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Periksa bahwa pesan-pesan ini tiba di server syslog jarak jauh.

### Uji login SSH

Buka sesi SSH **baru** (biarkan sesi yang ada tetap terbuka kalau ada yang perlu diperbaiki):

```sh
ssh -v alice@your-server
```

Alur yang diharapkan:
1. sshd menerima kunci publik Anda.
2. Anda melihat prompt: `Google Authenticator code: `
3. Masukkan kode 6 digit dari aplikasi autentikator.
4. Login berhasil atau gagal; hasilnya muncul di `/var/log/authlog` dan
   di server syslog jarak jauh.

## Format log login gagal

Ketika `login_totp` menolak kode TOTP, ia mengeluarkan pesan melalui `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Pesan ini ditulis ke:
- Syslog lokal (`/var/log/authlog` di OpenBSD).
- Server syslog jarak jauh melalui aturan `auth.info` di `syslog.conf`.

Peristiwa autentikasi gagal tambahan dicatat oleh sshd itu sendiri:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Referensi berkas

### `login_totp` (backend BSD Auth)

- **Lokasi:** `/usr/local/libexec/auth/login_totp`
- **Izin:** `root:auth 0550`
- **Berkas rahasia:** `~/.google_authenticator` (baris pertama = rahasia TOTP base-32)
- **Pencatatan:** `logger -p auth.warning` saat gagal, `auth.info` saat berhasil
- **Toleransi waktu:** ±1 × langkah 30 detik (dapat dikonfigurasi melalui `TOTP_WINDOW`)

### `~/.google_authenticator`

Berkas teks biasa; **baris pertama** harus berupa rahasia TOTP base-32.
Baris tambahan (komentar) diabaikan oleh `login_totp`.

Contoh:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Izin harus `0600`, dimiliki oleh pengguna yang bersangkutan.

## Perbedaan dari FreeBSD / pengaturan berbasis PAM

| Topik | FreeBSD | OpenBSD |
|-------|---------|---------|
| Kerangka autentikasi | PAM (`pam_google_authenticator.so`) | BSD Auth (skrip `login_totp`) |
| Kelas login | tidak ada | kelas `totp` di `/etc/login.conf` |
| Paket | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Daemon syslog | `syslogd` / `newsyslog` | `syslogd` (bawaan) |
| Penerusan UDP jarak jauh | `@host` di `syslog.conf` | `@host` di `syslog.conf` |
| Penerusan TCP jarak jauh | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Pemecahan masalah

**"oathtool not found"**
Pasang oath-toolkit: `doas pkg_add oath-toolkit`

**"No secret file for user"**
Jalankan `google-authenticator-setup.sh` untuk pengguna tersebut, atau buat
`~/.google_authenticator` secara manual dengan rahasia base-32 pada baris pertama.

**Kode TOTP selalu ditolak**
Pastikan jam sistem tersinkronisasi (`ntpd` diaktifkan secara default di OpenBSD).
Selisih jam lebih dari 30 detik akan menyebabkan setiap kode gagal. Tambah nilai `TOTP_WINDOW`
di `login_totp` jika diperlukan.

**SSH meminta kata sandi alih-alih kode TOTP**
Verifikasi bahwa `KbdInteractiveAuthentication yes` dan
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` keduanya ada
di `/etc/ssh/sshd_config`, dan bahwa pengguna berada di kelas login `totp`
(`doas usermod -L totp <user>`).

**sshd -t gagal setelah mengedit sshd_config**
Jalankan `doas sshd -t` dan perbaiki semua kesalahan yang dilaporkan sebelum memulai ulang sshd.
Cadangan yang dibuat oleh `setup.sh` berada di
`/etc/ssh/sshd_config.bak.<timestamp>`.

**Syslog jarak jauh tidak menerima pesan**
1. Konfirmasi bahwa port UDP/TCP 514 server jarak jauh dapat dijangkau:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Periksa aturan firewall di kedua ujung (OpenBSD pf dan server jarak jauh).
3. Untuk penerusan TCP, konfirmasi bahwa `syslogd_flags="-T"` ada di
   `/etc/rc.conf.local` dan `syslogd` sudah dimulai ulang.

## Lisensi

Lisensi BSD 2-Clause. Lihat [LICENSE](../LICENSE) untuk detailnya.
