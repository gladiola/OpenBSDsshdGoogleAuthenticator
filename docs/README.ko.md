# OpenBSD sshd + Google Authenticator (TOTP)

Google Authenticator(TOTP)를 사용한 OpenBSD SSH 이중 인증.
로그인 실패 로그는 원격 syslog 서버로 전달됩니다.

## 개요

이 저장소가 제공하는 내용:

| 파일 | 목적 |
|------|---------|
| `setup.sh` | 자동화된 설정 스크립트 — root로 한 번 실행 |
| `login_totp` | TOTP 코드를 검증하는 BSD Auth 백엔드 |
| `google-authenticator-setup.sh` | 사용자별 등록 스크립트 |
| `sshd_config.snippet` | 참조용 sshd_config 추가 내용 |
| `syslog.conf.snippet` | 원격 전달을 위한 참조 syslog.conf 추가 내용 |

### 인증 흐름

```
SSH 클라이언트
  │
  ▼
sshd  ──── 1. 공개키 인증 (기존 키 쌍)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. 프롬프트: "Google Authenticator code: "
  ├── 3. 사용자가 앱에서 6자리 TOTP 입력
  ├── 4. oathtool이 ~/.google_authenticator에 대해 코드 검증
  │
  ├─ 성공 → 세션 열림; auth.info가 로컬 기록 및 전달됨
  └─ 실패 → 세션 닫힘; auth.warning이 로컬 기록 및 전달됨
```

## 요구 사항

- OpenBSD 7.x (7.4 및 7.5에서 테스트됨)
- root 또는 `doas` 접근 권한
- `oath-toolkit` 패키지 (`pkg_add oath-toolkit`) — `oathtool` 제공
- 호스트에서 접근 가능한 원격 syslog 서버 (rsyslog, syslog-ng 등)
- 사용자는 SSH 공개키가 이미 설치되어 있어야 함 (`~/.ssh/authorized_keys`)

## 빠른 시작 (자동)

```sh
doas sh setup.sh
```

스크립트가 수행하는 작업:

1. `pkg_add`를 통해 `oath-toolkit` 설치.
2. `login_totp`를 `/usr/local/libexec/auth/login_totp`에 복사.
3. `/etc/login.conf`에 `totp` 로그인 클래스 추가.
4. `/etc/ssh/sshd_config` 패치 적용.
5. `/etc/syslog.conf`에 원격 전달 규칙 추가.
6. `syslogd`와 `sshd` 재시작.
7. 선택적으로 `google-authenticator-setup.sh`를 실행하여 사용자 등록.

## 수동 설치

### 1. oath-toolkit 설치

```sh
doas pkg_add oath-toolkit
```

### 2. BSD Auth 로그인 스크립트 설치

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. `totp` 로그인 클래스 추가

다음 내용을 `/etc/login.conf`에 추가합니다:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

그런 다음 login.conf 데이터베이스를 재빌드합니다:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. sshd 설정

`sshd_config.snippet`의 내용을 `/etc/ssh/sshd_config`에 추가합니다.
중요한 디렉티브는 다음과 같습니다:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

sshd를 검증하고 재시작합니다:

```sh
doas sshd -t          # 설정 검증
doas rcctl restart sshd
```

### 5. 원격 syslog 설정

`syslog.conf.snippet`의 내용을 `/etc/syslog.conf`에 추가하고,
`REMOTE_SYSLOG_SERVER`를 실제 서버 주소로 교체합니다.

**UDP (기본값):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (더 안정적):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

TCP의 경우, `/etc/rc.conf.local`에서 TCP도 활성화합니다:

```
syslogd_flags="-T"
```

syslogd를 다시 로드합니다:

```sh
doas rcctl restart syslogd
```

### 6. 사용자 등록

사용자별 등록 스크립트를 실행합니다 (root 또는 사용자 본인으로):

```sh
doas sh google-authenticator-setup.sh
```

스크립트 동작:
1. 무작위 160비트 TOTP 시크릿 생성.
2. `~/.google_authenticator`(모드 0600)에 기록.
3. `otpauth://` URI와 터미널 QR 코드 출력 (`qrencode`가 설치된 경우).
4. 사용자를 `totp` 로그인 클래스에 할당.

QR 코드를 스캔하거나 URI를 붙여넣어 Google Authenticator, Aegis,
Authy 또는 TOTP 호환 앱에 등록합니다.

### 7. 사용자를 totp 로그인 클래스에 할당

`google-authenticator-setup.sh`를 사용하지 않은 경우 수동으로 클래스를 할당합니다:

```sh
doas usermod -L totp alice
```

## 설정 확인

### oathtool 로컬 테스트

```sh
# 사용자의 시크릿으로 현재 TOTP 코드 생성:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

인증 앱에 표시된 코드와 비교하세요 — 일치해야 합니다.

### syslog 전달 테스트

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

이 메시지들이 원격 syslog 서버에 도달하는지 확인합니다.

### SSH 로그인 테스트

**새** SSH 세션을 엽니다 (문제가 발생할 경우를 대비해 기존 세션은 열어 둡니다):

```sh
ssh -v alice@your-server
```

예상 흐름:
1. sshd가 공개키를 수락.
2. 프롬프트 표시: `Google Authenticator code: `
3. 인증 앱에서 6자리 코드 입력.
4. 로그인 성공 또는 실패; 결과가 `/var/log/authlog`와
   원격 syslog 서버에 나타납니다.

## 로그인 실패 로그 형식

`login_totp`가 TOTP 코드를 거부하면 `logger(1)`를 통해 메시지를 출력합니다:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

이 메시지는 다음에 기록됩니다:
- 로컬 syslog (OpenBSD의 `/var/log/authlog`).
- `syslog.conf`의 `auth.info` 규칙을 통한 원격 syslog 서버.

추가 인증 실패 이벤트는 sshd 자체에 의해 기록됩니다:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## 파일 참조

### `login_totp` (BSD Auth 백엔드)

- **위치:** `/usr/local/libexec/auth/login_totp`
- **권한:** `root:auth 0550`
- **시크릿 파일:** `~/.google_authenticator` (첫 번째 줄 = base-32 TOTP 시크릿)
- **로깅:** 실패 시 `logger -p auth.warning`, 성공 시 `auth.info`
- **시간 허용 범위:** ±1 × 30초 단계 (`TOTP_WINDOW`로 설정 가능)

### `~/.google_authenticator`

일반 텍스트 파일; **첫 번째 줄**은 반드시 base-32 TOTP 시크릿이어야 합니다.
추가 줄(주석)은 `login_totp`에 의해 무시됩니다.

예시:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

권한은 `0600`이어야 하며 사용자가 소유자여야 합니다.

## FreeBSD / PAM 기반 설정과의 차이점

| 항목 | FreeBSD | OpenBSD |
|-------|---------|---------|
| 인증 프레임워크 | PAM (`pam_google_authenticator.so`) | BSD Auth (`login_totp` 스크립트) |
| 로그인 클래스 | 해당 없음 | `/etc/login.conf` `totp` 클래스 |
| 패키지 | `security/google-authenticator-pam` | `security/oath-toolkit` |
| syslog 데몬 | `syslogd` / `newsyslog` | `syslogd` (내장) |
| 원격 UDP 전달 | `syslog.conf`의 `@host` | `syslog.conf`의 `@host` |
| 원격 TCP 전달 | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## 문제 해결

**"oathtool not found"**
oath-toolkit을 설치하세요: `doas pkg_add oath-toolkit`

**"No secret file for user"**
해당 사용자에 대해 `google-authenticator-setup.sh`를 실행하거나,
첫 번째 줄에 base-32 시크릿이 있는 `~/.google_authenticator`를 수동으로 생성하세요.

**TOTP 코드가 항상 거부됨**
시스템 시계가 동기화되어 있는지 확인하세요 (OpenBSD에서는 `ntpd`가 기본으로 활성화됨).
30초를 초과하는 시계 편차가 있으면 모든 코드가 실패합니다.
필요한 경우 `login_totp`의 `TOTP_WINDOW`를 늘리세요.

**SSH가 TOTP 코드 대신 비밀번호를 요청함**
`KbdInteractiveAuthentication yes`와
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` 모두
`/etc/ssh/sshd_config`에 있는지, 그리고 사용자가 `totp` 로그인 클래스에
있는지 확인하세요 (`doas usermod -L totp <user>`).

**sshd_config 편집 후 sshd -t 실패**
`doas sshd -t`를 실행하고 sshd를 재시작하기 전에 보고된 오류를 수정하세요.
`setup.sh`가 생성한 백업은
`/etc/ssh/sshd_config.bak.<timestamp>`에 있습니다.

**원격 syslog가 메시지를 수신하지 않음**
1. 원격 서버의 UDP/TCP 포트 514에 접근 가능한지 확인:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. 양쪽 방화벽 규칙 확인 (OpenBSD pf 및 원격 서버).
3. TCP 전달의 경우, `syslogd_flags="-T"`가 `/etc/rc.conf.local`에 있고
   `syslogd`가 재시작되었는지 확인하세요.

## 라이선스

BSD 2-Clause 라이선스. 자세한 내용은 [LICENSE](../LICENSE)를 참조하세요.
