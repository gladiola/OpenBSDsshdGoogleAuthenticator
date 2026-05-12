# OpenBSD sshd + Google Authenticator (TOTP)

การยืนยันตัวตนสองปัจจัยสำหรับ OpenBSD SSH โดยใช้ Google Authenticator (TOTP)
พร้อมการส่งต่อบันทึกการเข้าสู่ระบบที่ล้มเหลวไปยังเซิร์ฟเวอร์ syslog ระยะไกล

## ภาพรวม

ที่เก็บโค้ดนี้มีให้:

| ไฟล์ | วัตถุประสงค์ |
|------|---------|
| `setup.sh` | สคริปต์ตั้งค่าอัตโนมัติ — รันครั้งเดียวในฐานะ root |
| `login_totp` | แบ็กเอนด์ BSD Auth ที่ตรวจสอบรหัส TOTP |
| `google-authenticator-setup.sh` | สคริปต์ลงทะเบียนต่อผู้ใช้ |
| `sshd_config.snippet` | ส่วนเพิ่มเติม sshd_config สำหรับอ้างอิง |
| `syslog.conf.snippet` | ส่วนเพิ่มเติม syslog.conf สำหรับอ้างอิงในการส่งต่อระยะไกล |

### ขั้นตอนการยืนยันตัวตน

```
SSH ไคลเอนต์
  │
  ▼
sshd  ──── 1. การยืนยันตัวตนด้วยคีย์สาธารณะ (คู่คีย์ที่มีอยู่)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. พรอมต์: "Google Authenticator code: "
  ├── 3. ผู้ใช้ป้อน TOTP 6 หลักจากแอป
  ├── 4. oathtool ตรวจสอบรหัสกับ ~/.google_authenticator
  │
  ├─ สำเร็จ → เซสชันเปิด; บันทึก auth.info ในเครื่องและส่งต่อ
  └─ ล้มเหลว → เซสชันปิด; บันทึก auth.warning ในเครื่องและส่งต่อ
```

## ความต้องการของระบบ

- OpenBSD 7.x (ทดสอบบน 7.4 และ 7.5)
- สิทธิ์เข้าถึง root หรือ `doas`
- แพ็กเกจ `oath-toolkit` (`pkg_add oath-toolkit`) — ให้ `oathtool`
- เซิร์ฟเวอร์ syslog ระยะไกลที่เข้าถึงได้จากโฮสต์ (rsyslog, syslog-ng ฯลฯ)
- ผู้ใช้ต้องมี SSH คีย์สาธารณะติดตั้งไว้แล้ว (`~/.ssh/authorized_keys`)

## เริ่มต้นอย่างรวดเร็ว (อัตโนมัติ)

```sh
doas sh setup.sh
```

สคริปต์จะดำเนินการ:

1. ติดตั้ง `oath-toolkit` ผ่าน `pkg_add`
2. คัดลอก `login_totp` ไปยัง `/usr/local/libexec/auth/login_totp`
3. เพิ่มคลาสการเข้าสู่ระบบ `totp` ใน `/etc/login.conf`
4. แพตช์ `/etc/ssh/sshd_config`
5. แพตช์ `/etc/syslog.conf` ด้วยกฎการส่งต่อระยะไกล
6. รีสตาร์ท `syslogd` และ `sshd`
7. รัน `google-authenticator-setup.sh` เพื่อลงทะเบียนผู้ใช้ (ตัวเลือก)

## การติดตั้งด้วยตนเอง

### 1. ติดตั้ง oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. ติดตั้งสคริปต์เข้าสู่ระบบ BSD Auth

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. เพิ่มคลาสการเข้าสู่ระบบ `totp`

เพิ่มข้อความต่อไปนี้ลงใน `/etc/login.conf`:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

จากนั้นสร้างฐานข้อมูล login.conf ใหม่:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. กำหนดค่า sshd

เพิ่มบรรทัดจาก `sshd_config.snippet` ลงใน `/etc/ssh/sshd_config`
ไดเรกทีฟที่สำคัญได้แก่:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

ตรวจสอบและรีสตาร์ท sshd:

```sh
doas sshd -t          # ตรวจสอบการกำหนดค่า
doas rcctl restart sshd
```

### 5. กำหนดค่า syslog ระยะไกล

เพิ่มบรรทัดจาก `syslog.conf.snippet` ลงใน `/etc/syslog.conf`
โดยแทนที่ `REMOTE_SYSLOG_SERVER` ด้วยที่อยู่เซิร์ฟเวอร์จริงของคุณ

**UDP (ค่าเริ่มต้น):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (เชื่อถือได้มากกว่า):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

สำหรับ TCP ให้เปิดใช้งาน TCP ใน `/etc/rc.conf.local` ด้วย:

```
syslogd_flags="-T"
```

โหลด syslogd ใหม่:

```sh
doas rcctl restart syslogd
```

### 6. ลงทะเบียนผู้ใช้

รันสคริปต์ลงทะเบียนต่อผู้ใช้ (ในฐานะ root หรือผู้ใช้เอง):

```sh
doas sh google-authenticator-setup.sh
```

สคริปต์จะ:
1. สร้างรหัสลับ TOTP แบบสุ่ม 160 บิต
2. เขียนลงใน `~/.google_authenticator` (โหมด 0600)
3. พิมพ์ URI `otpauth://` และ QR โค้ดในเทอร์มินัล (หากติดตั้ง `qrencode`)
4. กำหนดผู้ใช้ให้อยู่ในคลาสการเข้าสู่ระบบ `totp`

สแกน QR โค้ด (หรือวาง URI) ลงใน Google Authenticator, Aegis,
Authy หรือแอปที่รองรับ TOTP

### 7. กำหนดผู้ใช้ให้อยู่ในคลาสการเข้าสู่ระบบ totp

หากไม่ได้ใช้ `google-authenticator-setup.sh` ให้กำหนดคลาสด้วยตนเอง:

```sh
doas usermod -L totp alice
```

## การตรวจสอบการตั้งค่า

### ทดสอบ oathtool ในเครื่อง

```sh
# สร้างรหัส TOTP ปัจจุบันสำหรับรหัสลับของผู้ใช้:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

เปรียบเทียบกับรหัสที่แสดงในแอปยืนยันตัวตน — ควรตรงกัน

### ทดสอบการส่งต่อ syslog

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

ตรวจสอบว่าข้อความเหล่านี้มาถึงเซิร์ฟเวอร์ syslog ระยะไกล

### ทดสอบการเข้าสู่ระบบ SSH

เปิด SSH เซสชัน **ใหม่** (เปิดเซสชันที่มีอยู่ไว้ในกรณีที่ต้องแก้ไขอะไร):

```sh
ssh -v alice@your-server
```

ขั้นตอนที่คาดหวัง:
1. sshd ยอมรับคีย์สาธารณะของคุณ
2. คุณเห็นพรอมต์: `Google Authenticator code: `
3. ป้อนรหัส 6 หลักจากแอปยืนยันตัวตน
4. การเข้าสู่ระบบสำเร็จหรือล้มเหลว; ผลลัพธ์ปรากฏใน `/var/log/authlog`
   และบนเซิร์ฟเวอร์ syslog ระยะไกล

## รูปแบบบันทึกการเข้าสู่ระบบที่ล้มเหลว

เมื่อ `login_totp` ปฏิเสธรหัส TOTP จะส่งข้อความผ่าน `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

ข้อความนี้จะถูกเขียนไปยัง:
- syslog ในเครื่อง (`/var/log/authlog` บน OpenBSD)
- เซิร์ฟเวอร์ syslog ระยะไกลผ่านกฎ `auth.info` ใน `syslog.conf`

เหตุการณ์การยืนยันตัวตนที่ล้มเหลวเพิ่มเติมจะถูกบันทึกโดย sshd เอง:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## ข้อมูลอ้างอิงไฟล์

### `login_totp` (แบ็กเอนด์ BSD Auth)

- **ตำแหน่ง:** `/usr/local/libexec/auth/login_totp`
- **สิทธิ์:** `root:auth 0550`
- **ไฟล์รหัสลับ:** `~/.google_authenticator` (บรรทัดแรก = รหัสลับ TOTP แบบ base-32)
- **การบันทึก:** `logger -p auth.warning` เมื่อล้มเหลว, `auth.info` เมื่อสำเร็จ
- **ความคลาดเคลื่อนเวลา:** ±1 × ขั้น 30 วินาที (กำหนดค่าได้ผ่าน `TOTP_WINDOW`)

### `~/.google_authenticator`

ไฟล์ข้อความธรรมดา; **บรรทัดแรก** ต้องเป็นรหัสลับ TOTP แบบ base-32
บรรทัดเพิ่มเติม (ความคิดเห็น) จะถูกละเว้นโดย `login_totp`

ตัวอย่าง:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

สิทธิ์ต้องเป็น `0600` และเป็นของผู้ใช้

## ความแตกต่างจากการตั้งค่าแบบ FreeBSD / PAM

| หัวข้อ | FreeBSD | OpenBSD |
|-------|---------|---------|
| กรอบการยืนยันตัวตน | PAM (`pam_google_authenticator.so`) | BSD Auth (สคริปต์ `login_totp`) |
| คลาสการเข้าสู่ระบบ | ไม่มี | คลาส `totp` ใน `/etc/login.conf` |
| แพ็กเกจ | `security/google-authenticator-pam` | `security/oath-toolkit` |
| syslog daemon | `syslogd` / `newsyslog` | `syslogd` (ในตัว) |
| ส่งต่อ UDP ระยะไกล | `@host` ใน `syslog.conf` | `@host` ใน `syslog.conf` |
| ส่งต่อ TCP ระยะไกล | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## การแก้ไขปัญหา

**"oathtool not found"**
ติดตั้ง oath-toolkit: `doas pkg_add oath-toolkit`

**"No secret file for user"**
รัน `google-authenticator-setup.sh` สำหรับผู้ใช้นั้น หรือสร้าง
`~/.google_authenticator` ด้วยตนเองโดยมีรหัสลับ base-32 ในบรรทัดแรก

**รหัส TOTP ถูกปฏิเสธเสมอ**
ตรวจสอบให้แน่ใจว่านาฬิกาของระบบซิงโครไนซ์แล้ว (`ntpd` เปิดใช้งานโดยค่าเริ่มต้นบน OpenBSD)
ความเบี่ยงเบนของนาฬิกาเกิน 30 วินาทีจะทำให้รหัสทุกรหัสล้มเหลว
เพิ่ม `TOTP_WINDOW` ใน `login_totp` หากจำเป็น

**SSH ถามรหัสผ่านแทนรหัส TOTP**
ตรวจสอบว่า `KbdInteractiveAuthentication yes` และ
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` ทั้งคู่
มีอยู่ใน `/etc/ssh/sshd_config` และผู้ใช้อยู่ในคลาสการเข้าสู่ระบบ `totp`
(`doas usermod -L totp <user>`)

**sshd -t ล้มเหลวหลังจากแก้ไข sshd_config**
รัน `doas sshd -t` และแก้ไขข้อผิดพลาดที่รายงานก่อนรีสตาร์ท sshd
ไฟล์สำรองที่สร้างโดย `setup.sh` อยู่ที่
`/etc/ssh/sshd_config.bak.<timestamp>`

**เซิร์ฟเวอร์ syslog ระยะไกลไม่ได้รับข้อความ**
1. ยืนยันว่า UDP/TCP พอร์ต 514 ของเซิร์ฟเวอร์ระยะไกลเข้าถึงได้:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. ตรวจสอบกฎไฟร์วอลล์ทั้งสองฝั่ง (OpenBSD pf และเซิร์ฟเวอร์ระยะไกล)
3. สำหรับการส่งต่อ TCP ยืนยันว่า `syslogd_flags="-T"` อยู่ใน
   `/etc/rc.conf.local` และ `syslogd` ได้รีสตาร์ทแล้ว

## สัญญาอนุญาต

สัญญาอนุญาต BSD 2-Clause ดูรายละเอียดที่ [LICENSE](../LICENSE)
