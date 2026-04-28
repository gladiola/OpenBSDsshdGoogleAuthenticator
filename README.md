# OpenBSD sshd + Google Authenticator (TOTP)

Two-factor authentication for OpenBSD SSH using Google Authenticator
(TOTP), with failed-login logging forwarded to a remote syslog server.

## Overview

This repository provides:

| File | Purpose |
|------|---------|
| `setup.sh` | Automated setup script — run once as root |
| `login_totp` | BSD Auth backend that verifies the TOTP code |
| `google-authenticator-setup.sh` | Per-user enrolment script |
| `sshd_config.snippet` | Reference sshd_config additions |
| `syslog.conf.snippet` | Reference syslog.conf additions for remote forwarding |

### Authentication flow

```
SSH client
  │
  ▼
sshd  ──── 1. Public-key auth (existing key pair)
  │
  ▼
BSD Auth (login_totp)
  │
  ├── 2. Prompt: "Google Authenticator code: "
  ├── 3. User enters 6-digit TOTP from the app
  ├── 4. oathtool verifies the code against ~/.google_authenticator
  │
  ├─ SUCCESS → session opened; auth.info logged locally + forwarded
  └─ FAILURE → session closed; auth.warning logged locally + forwarded
```

## Requirements

- OpenBSD 7.x (tested on 7.4 and 7.5)
- Root or `doas` access
- `oath-toolkit` package (`pkg_add oath-toolkit`) — provides `oathtool`
- A remote syslog server reachable from the host (rsyslog, syslog-ng, etc.)
- Users must have an SSH public key already installed (`~/.ssh/authorized_keys`)

## Quick start (automated)

```sh
doas sh setup.sh
```

The script will:

1. Install `oath-toolkit` via `pkg_add`.
2. Copy `login_totp` to `/usr/local/libexec/auth/login_totp`.
3. Add a `totp` login class to `/etc/login.conf`.
4. Patch `/etc/ssh/sshd_config`.
5. Patch `/etc/syslog.conf` with remote forwarding rules.
6. Restart `syslogd` and `sshd`.
7. Optionally run `google-authenticator-setup.sh` to enrol a user.

## Manual installation

### 1. Install oath-toolkit

```sh
doas pkg_add oath-toolkit
```

### 2. Install the BSD Auth login script

```sh
doas install -o root -g auth -m 550 \
    login_totp /usr/local/libexec/auth/login_totp
```

### 3. Add the `totp` login class

Append the following to `/etc/login.conf`:

```
# TOTP (Google Authenticator) login class
totp:\
    :auth=-totp:\
    :tc=default:
```

Then rebuild the login.conf database:

```sh
doas cap_mkdb /etc/login.conf
```

### 4. Configure sshd

Add the lines from `sshd_config.snippet` to `/etc/ssh/sshd_config`.
The critical directives are:

```
AuthenticationMethods publickey,keyboard-interactive:bsdauth
KbdInteractiveAuthentication yes
PasswordAuthentication no
UsePAM no
LogLevel VERBOSE
```

Verify and restart sshd:

```sh
doas sshd -t          # verify config
doas rcctl restart sshd
```

### 5. Configure remote syslog

Add the lines from `syslog.conf.snippet` to `/etc/syslog.conf`, replacing
`REMOTE_SYSLOG_SERVER` with your actual server address.

**UDP (default):**

```
auth.info     @192.168.1.50
*.warning     @192.168.1.50
```

**TCP (more reliable):**

```
auth.info     @@192.168.1.50
*.warning     @@192.168.1.50
```

For TCP, also enable TCP in `/etc/rc.conf.local`:

```
syslogd_flags="-T"
```

Reload syslogd:

```sh
doas rcctl restart syslogd
```

### 6. Enrol users

Run the per-user enrolment script (as root or as the user themselves):

```sh
doas sh google-authenticator-setup.sh
```

The script:
1. Generates a random 160-bit TOTP secret.
2. Writes it to `~/.google_authenticator` (mode 0600).
3. Prints a `otpauth://` URI and a terminal QR code (if `qrencode` is installed).
4. Assigns the user to the `totp` login class.

Scan the QR code (or paste the URI) into Google Authenticator, Aegis,
Authy, or any TOTP-compatible app.

### 7. Assign users to the totp login class

If you did not use `google-authenticator-setup.sh`, assign the class manually:

```sh
doas usermod -L totp alice
```

## Verifying the setup

### Test oathtool locally

```sh
# Generate the current TOTP code for a user's secret:
head -1 ~/.google_authenticator | xargs oathtool --totp -b
```

Compare this with the code shown in the authenticator app — they should match.

### Test syslog forwarding

```sh
logger -p auth.info   "syslog-test: auth.info forwarding"
logger -p auth.warning "syslog-test: auth.warning forwarding"
```

Check that these messages arrive on the remote syslog server.

### Test SSH login

Open a **new** SSH session (keep your existing session open in case
something needs fixing):

```sh
ssh -v alice@your-server
```

Expected flow:
1. sshd accepts your public key.
2. You see the prompt: `Google Authenticator code: `
3. Enter the 6-digit code from the authenticator app.
4. Login succeeds or fails; the result appears in `/var/log/authlog` and
   on the remote syslog server.

## Failed-login log format

When `login_totp` rejects a TOTP code, it emits a message via `logger(1)`:

```
Apr 27 16:00:01 myhost login_totp[12345]: TOTP reject: failed one-time-password for user 'alice' (service=ssh class=totp)
```

This message is written to:
- The local syslog (`/var/log/authlog` on OpenBSD).
- The remote syslog server via the `auth.info` rule in `syslog.conf`.

Additional failed-authentication events are logged by sshd itself:

```
Apr 27 16:00:01 myhost sshd[12346]: Failed keyboard-interactive for alice from 203.0.113.5 port 54321 ssh2
```

## File reference

### `login_totp` (BSD Auth backend)

- **Location:** `/usr/local/libexec/auth/login_totp`
- **Permissions:** `root:auth 0550`
- **Secret file:** `~/.google_authenticator` (first line = base-32 TOTP secret)
- **Logging:** `logger -p auth.warning` on failure, `auth.info` on success
- **Time tolerance:** ±1 × 30-second step (configurable via `TOTP_WINDOW`)

### `~/.google_authenticator`

A plain-text file; the **first line** must be the base-32 TOTP secret.
Additional lines (comments) are ignored by `login_totp`.

Example:
```
JBSWY3DPEHPK3PXP
# Created by google-authenticator-setup.sh on Mon Apr 27 16:00:00 UTC 2026
```

Permissions must be `0600`, owned by the user.

## Differences from FreeBSD / PAM-based setups

| Topic | FreeBSD | OpenBSD |
|-------|---------|---------|
| Auth framework | PAM (`pam_google_authenticator.so`) | BSD Auth (`login_totp` script) |
| Login class | n/a | `/etc/login.conf` `totp` class |
| Package | `security/google-authenticator-pam` | `security/oath-toolkit` |
| syslog daemon | `syslogd` / `newsyslog` | `syslogd` (built-in) |
| Remote UDP forward | `@host` in `syslog.conf` | `@host` in `syslog.conf` |
| Remote TCP forward | `@@host` | `@@host` (+ `syslogd_flags="-T"`) |

## Troubleshooting

**"oathtool not found"**
Install oath-toolkit: `doas pkg_add oath-toolkit`

**"No secret file for user"**
Run `google-authenticator-setup.sh` for that user, or manually create
`~/.google_authenticator` with the base-32 secret on the first line.

**TOTP codes always rejected**
Ensure the system clock is synchronised (`ntpd` is enabled on OpenBSD by
default). A clock skew of more than 30 seconds will cause every code to
fail. Increase `TOTP_WINDOW` in `login_totp` if needed.

**SSH asks for a password instead of a TOTP code**
Verify that `KbdInteractiveAuthentication yes` and
`AuthenticationMethods publickey,keyboard-interactive:bsdauth` are both
present in `/etc/ssh/sshd_config`, and that the user is in the `totp`
login class (`doas usermod -L totp <user>`).

**sshd -t fails after editing sshd_config**
Run `doas sshd -t` and fix any reported errors before restarting sshd.
The backup created by `setup.sh` is at
`/etc/ssh/sshd_config.bak.<timestamp>`.

**Remote syslog not receiving messages**
1. Confirm the remote server's UDP/TCP port 514 is reachable:
   `nc -u -z REMOTE_SYSLOG_SERVER 514`
2. Check firewall rules on both ends (OpenBSD pf and remote server).
3. For TCP forwarding, confirm `syslogd_flags="-T"` is in
   `/etc/rc.conf.local` and `syslogd` has been restarted.

## License

BSD 2-Clause License. See [LICENSE](LICENSE) for details.