#!/bin/sh
#
# google-authenticator-setup.sh
#
# Enrol a single OpenBSD user for Google Authenticator (TOTP).
# Must be run as root (or by the user themselves with doas).
#
# What this script does:
#   1. Prompts for the target username (defaults to the current user).
#   2. Generates a TOTP secret using oathtool and stores it in
#      ~/.google_authenticator (the format expected by login_totp).
#   3. Prints a QR-code URI that can be scanned with the Google
#      Authenticator (or any TOTP-compatible) app.
#   4. Assigns the user to the "totp" login class via usermod.
#
# Requires:
#   oath-toolkit  (pkg_add oath-toolkit)
#   qrencode      (optional — pkg_add qrencode — for terminal QR codes)

set -eu

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RESET='\033[0m'
info()  { printf "${GREEN}[INFO]${RESET}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${RESET}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Validate dependencies
# ---------------------------------------------------------------------------
for cmd in oathtool head cut install; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        error "Required command '$cmd' not found."
    fi
done

# ---------------------------------------------------------------------------
# Determine target user
# ---------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
    printf "Username to enrol [$(logname 2>/dev/null || echo root)]: "
    read -r TARGET_USER
    TARGET_USER="${TARGET_USER:-$(logname 2>/dev/null || echo root)}"
else
    TARGET_USER="$(id -un)"
    info "Running as non-root; enrolling current user: $TARGET_USER"
fi

# Verify the user exists.
if ! getent passwd "$TARGET_USER" >/dev/null 2>&1; then
    error "User '$TARGET_USER' does not exist."
fi

HOME_DIR=$(getent passwd "$TARGET_USER" | cut -d: -f6)
SECRET_FILE="$HOME_DIR/.google_authenticator"

# ---------------------------------------------------------------------------
# Warn if a secret file already exists
# ---------------------------------------------------------------------------
if [ -f "$SECRET_FILE" ]; then
    warn "A secret file already exists at $SECRET_FILE."
    printf "Overwrite it? This will invalidate the current Google Authenticator key. [y/N]: "
    read -r CONFIRM
    CONFIRM=$(printf '%s' "$CONFIRM" | tr '[:upper:]' '[:lower:]')
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "yes" ]; then
        info "Aborting — existing secret kept."
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# Generate a new TOTP secret (20 random bytes → base-32, 32 characters)
# ---------------------------------------------------------------------------
info "Generating TOTP secret …"

# Use OpenBSD's /dev/random for entropy.
SECRET_HEX=$(dd if=/dev/random bs=20 count=1 2>/dev/null | od -A n -t x1 | tr -d ' \n')
SECRET_B32=$(printf '%s' "$SECRET_HEX" | \
    python3 -c "
import sys, base64, binascii
data = binascii.unhexlify(sys.stdin.read().strip())
print(base64.b32encode(data).decode().rstrip('='))
")

if [ -z "$SECRET_B32" ]; then
    error "Failed to generate a base-32 secret (is python3 available?)."
fi

# ---------------------------------------------------------------------------
# Write the secret file (format compatible with login_totp / oathtool)
# ---------------------------------------------------------------------------
HOSTNAME=$(hostname -s)
ISSUER="SSH-${HOSTNAME}"
OTP_URI="otpauth://totp/${ISSUER}:${TARGET_USER}?secret=${SECRET_B32}&issuer=${ISSUER}&algorithm=SHA1&digits=6&period=30"

# Write the file with tight permissions.
# Format: first line = base-32 secret, followed by optional metadata lines.
(
    umask 177
    printf '%s\n' "$SECRET_B32" > "$SECRET_FILE"
    printf '# Created by google-authenticator-setup.sh on %s\n' "$(date)" >> "$SECRET_FILE"
)
chown "$TARGET_USER" "$SECRET_FILE"

info "Secret file written to $SECRET_FILE (mode 0600, owned by $TARGET_USER)."

# ---------------------------------------------------------------------------
# Print QR-code URI
# ---------------------------------------------------------------------------
printf '\n'
info "Scan the following URI with Google Authenticator (or compatible app):"
printf '\n  %s\n\n' "$OTP_URI"

# Optionally render a QR code in the terminal.
if command -v qrencode >/dev/null 2>&1; then
    info "QR code (scan with your authenticator app):"
    qrencode -t UTF8 "$OTP_URI"
else
    warn "qrencode not found.  Install it with 'pkg_add qrencode' for terminal QR codes."
    warn "You can also paste the URI above into https://www.qr-code-generator.com"
fi

# ---------------------------------------------------------------------------
# Assign user to the "totp" login class
# ---------------------------------------------------------------------------
if [ "$(id -u)" -eq 0 ]; then
    # /etc/master.passwd (field 5) holds the login class on OpenBSD.
    CURRENT_CLASS=$(awk -F: -v u="$TARGET_USER" '$1==u{print $5; exit}' \
        /etc/master.passwd 2>/dev/null)
    if [ "$CURRENT_CLASS" = "totp" ]; then
        info "User '$TARGET_USER' is already in the 'totp' login class."
    else
        info "Assigning user '$TARGET_USER' to the 'totp' login class …"
        usermod -L totp "$TARGET_USER"
        info "Done."
    fi
else
    warn "Not running as root — cannot set login class automatically."
    warn "Ask root to run:  doas usermod -L totp $TARGET_USER"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n'
info "Enrolment complete for user '$TARGET_USER'."
info "Test that oathtool can produce codes for this secret:"
info "  oathtool --totp -b '$SECRET_B32'"
info "The code printed should match what appears in the authenticator app."
printf '\n'
warn "Keep the QR code URI above private — it is your TOTP secret."
