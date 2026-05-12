# OpenBSD sshd + Google Authenticator (TOTP)

Verifikasi loro-langkah kanggo SSH OpenBSD nganggo Google Authenticator
(TOTP), kanthi log gagal mlebu sing diterusake menyang server syslog sing adoh.

## Ringkesan

Repositori iki nyedhiyakake:

| Berkas | Tujuan |
|--------|--------|
| `setup.sh` | Skrip pemasangan otomatis — lakokna sepisan minangka root |
| `login_totp` | Backend BSD Auth sing verifikasi kode TOTP |
| `google-authenticator-setup.sh` | Skrip pendaftaran saben pangguna |
| `sshd_config.snippet` | Tambahan sshd_config minangka referensi |
| `syslog.conf.snippet` | Tambahan syslog.conf kanggo penerusan adoh minangka referensi |

### Alur verifikasi

```
Klien SSH
  │
  ▼
sshd  ──── 1. Verifikasi kunci publik (pasangan kunci sing wis ana)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Pitakon: "Google Authenticator code: "
  ├── 3. Pangguna nglebokake 6 angka TOTP saka aplikasi
  ├── 4. oathtool verifikasi kode marang ~/.google_authenticator
  │
  ├─ KASIL → sesi dibuka; auth.info dicathet lokal + diterusake
  └─ GAGAL → sesi ditutup; auth.warning dicathet lokal + diterusake
```

## Syarat-syarat

- OpenBSD 7.x (diuji ing 7.4 lan 7.5)
- Akses root utawa `doas`
- Paket `oath-toolkit` (`pkg_add oath-toolkit`) — nyedhiyakake `oathtool`
- Server syslog adoh sing bisa dijangkau saka host (rsyslog, syslog-ng, lsp.)
- Pangguna kudu wis masang kunci publik SSH (`~/.ssh/authorized_keys`)

## Wiwitan cepet (otomatis)

```sh
doas sh setup.sh
```

Skrip iki bakal:

1. Masang `oath-toolkit` liwat `pkg_add`.
2. Nyalin `login_totp` menyang `/usr/local/libexec/auth/login_totp`.
3. Nambahake kelas mlebu `totp` menyang `/etc/login.conf`.
4. Ngowahi `/etc/ssh/sshd_config`.
5. Ngowahi `/etc/syslog.conf` kanthi aturan penerusan adoh.
6. Miwiti maneh `syslogd` lan `sshd`.
7. Pilihan: nglakokake `google-authenticator-setup.sh` kanggo ndhaftar pangguna.

## Pemasangan manual

### 1. Masang oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Masang skrip mlebu BSD Auth

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Tambahake kelas mlebu `totp`

Tambahake baris iki ing pungkasan `/etc/login.conf`:

```
# Kelas mlebu TOTP (Google Authenticator)
totp:\
    :auth=-totp:\
    :tc=default:
```

Banjur bangun maneh basis data login.conf:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Konfigurasi sshd

Tambahake baris saka `sshd_config.snippet` menyang `/etc/ssh/sshd_config`.
Direktif-direktif sing penting yaiku:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Verifikasi lan wiwiti maneh sshd:

```sh
doas sshd -t          # verifikasi konfigurasi
doas rcctl restart sshd
```

### 5. Konfigurasi syslog adoh

Tambahake baris saka `syslog.conf.snippet` menyang `/etc/syslog.conf`, ganti
`REMOTE_SYSLOG_SERVER` kanthi alamat server sampeyan sing nyata.

**UDP (gawan):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (luwih andal):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

Kanggo TCP, aktifake uga TCP ing `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Muat maneh syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Daftarake pangguna

Lakokna skrip pendaftaran saben pangguna (minangka root utawa minangka pangguna dhewe):

```sh
doas sh google-authenticator-setup.sh
```

Skrip iki bakal:
1. Ngasilake rahasia TOTP 160-bit acak.
2. Nulis menyang `~/.google_authenticator` (mode 0600).
3. Nyithak URI `otpauth://` lan kode QR ing terminal (yen `qrencode` wis dipasang).
4. Nugasake pangguna menyang kelas mlebu `totp`.

Pindai kode QR (utawa tempel URI) menyang Google Authenticator, Aegis,
Authy, utawa aplikasi apa wae sing kompatibel karo TOTP.

### 7. Nugasake pangguna menyang kelas mlebu totp

Yen sampeyan ora nggunakake `google-authenticator-setup.sh`, nugasake kelas kanthi manual:

```sh
doas usermod -L totp alice
```

## Verifikasi pemasangan

### Uji oathtool sacara lokal

```sh
# Gawe kode TOTP saiki kanggo rahasia pangguna:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Bandhingake iki karo kode sing ditampilake ing aplikasi autentikator — keduane kudu cocok.

### Uji penerusan syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Priksa manawa pesen-pesen iki teka ing server syslog adoh.

### Uji mlebu SSH

Buka sesi SSH **anyar** (tetepake sesi sing wis ana supaya tetep mbuka yen ana sing kudu dibenahi):

```sh
ssh -v alice@your-server
```

Alur sing dikarepake:
1. sshd nampa kunci publik sampeyan.
2. Sampeyan ndeleng pitakon: `Google Authenticator code: `
3. Lebokake kode 6 angka saka aplikasi autentikator.
4. Mlebu kasil utawa gagal; asile muncul ing `/var/log/authlog` lan
   ing server syslog adoh.

## Format log mlebu gagal

Nalika `login_totp` nolak kode TOTP, dheweke ngetokake pesen liwat `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

Pesen iki ditulis menyang:
- Syslog lokal (`/var/log/authlog` ing OpenBSD).
- Server syslog adoh liwat aturan `auth.info` ing `syslog.conf`.

Kedadeyan verifikasi gagal tambahan dicathet dening sshd dhewe:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## Referensi berkas

### `login_totp` (backend BSD Auth)

- **Lokasi:** `/usr/local/libexec/auth/login_totp`
- **Ijin:** `root:auth 0550`
- **Berkas rahasia:** `~/.google_authenticator` (baris pertama = rahasia TOTP base-32)
- **Pencatatan:** `logger -p auth.warning` nalika gagal, `auth.info` nalika kasil
- **Toleransi wektu:** ±1 × langkah 30 detik (bisa dikonfigurasi liwat `TOTP_WINDOW`)

### `~/.google_authenticator`

Berkas teks biasa; **baris pertama** kudu dadi rahasia TOTP base-32.
Baris tambahan (komentar) diabaikan dening `login_totp`.

Conto:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Ijin kudu `0600`, duweke pangguna.

## Beda karo FreeBSD / pengaturan berbasis PAM

| Topik | FreeBSD | OpenBSD |
|-------|---------|---------|
| Kerangka verifikasi | PAM (`pam_google_authenticator.so`) | BSD Auth (skrip `login_totp`) |
| Kelas mlebu | ora ana | kelas `totp` ing `/etc/login.conf` |
| Paket | `security/google-authenticator-pam` | `security/oath-toolkit` |
| Daemon syslog | `syslogd` / `newsyslog` | `syslogd` (bawaan) |
| Penerusan UDP adoh | `@host` ing `syslog.conf` | `@host` ing `syslog.conf` |
| Penerusan TCP adoh | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Ngrampungake masalah

**"oathtool not found"**
Masang oath-toolkit: `doas pkg_add oath-toolkit`

**"No secret file for user"**
Lakokna `google-authenticator-setup.sh` kanggo pangguna kasebut, utawa gawe
`~/.google_authenticator` kanthi manual kanthi rahasia base-32 ing baris pertama.

**Kode TOTP tansah ditolak**
Pastikna jam sistem wis disinkronisasi (`ntpd` diaktifake kanthi gawan ing OpenBSD).
Panyimpangan jam luwih saka 30 detik bakal njalari saben kode gagal. Tambahake `TOTP_WINDOW`
ing `login_totp` yen perlu.

**SSH njaluk tembung sandi tinimbang kode TOTP**
Verifikasi manawa `KbdInteractiveAuthentication yes` lan
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` loro-lorone ana
ing `/etc/ssh/sshd_config`, lan manawa pangguna ana ing kelas mlebu `totp`
(`doas usermod -L totp <user>`).

**sshd -t gagal sawise ngowahi sshd_config**
Lakokna `doas sshd -t` lan benahi kabeh kesalahan sing dilaporake sadurunge miwiti maneh sshd.
Cadangan sing digawe dening `setup.sh` ana ing
`/etc/ssh/sshd_config.bak.<timestamp>`.

**Syslog adoh ora nampa pesen**
1. Konfirmasi manawa port UDP/TCP 514 server adoh bisa dijangkau:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Priksa aturan firewall ing loro-lorone ujung (OpenBSD pf lan server adoh).
3. Kanggo penerusan TCP, konfirmasi manawa `syslogd_flags="-T"` ana ing
   `/etc/rc.conf.local` lan `syslogd` wis diwiwiti maneh.

## Lisensi

Lisensi BSD 2-Clause. Deleng [LICENSE](../LICENSE) kanggo rinciane.
