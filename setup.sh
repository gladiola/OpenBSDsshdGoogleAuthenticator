#!/bin/sh
#
# setup.sh — Configure OpenBSD sshd with Google Authenticator (TOTP) +
#            remote syslog forwarding of failed-login events.
#
# Usage:
#   Run as root on an OpenBSD 7.x system:
#       doas sh setup.sh
#
# What this script does:
#   1. Installs oath-toolkit (provides oathtool) from binary packages.
#   2. Installs login_totp BSD Auth script to /usr/local/libexec/auth/.
#   3. Adds a "totp" login class to /etc/login.conf.
#   4. Backs up and patches /etc/ssh/sshd_config for TOTP + public-key auth.
#   5. Backs up and patches /etc/syslog.conf to forward auth messages to a
#      remote syslog server (UDP or TCP).
#   6. Restarts syslogd and sshd.
#   7. Optionally runs google-authenticator-setup.sh for a named user.
#
# Requirements:
#   - OpenBSD 7.x (tested on 7.4 / 7.5)
#   - Internet access (or a local package mirror) for pkg_add
#   - A remote syslog server reachable from this host

set -eu

# ---------------------------------------------------------------------------
# Colour helpers
# ---------------------------------------------------------------------------
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RESET='\033[0m'
info()  { printf "${GREEN}[INFO]${RESET}  %s\n" "$*"; }
warn()  { printf "${YELLOW}[WARN]${RESET}  %s\n" "$*"; }
error() { printf "${RED}[ERROR]${RESET} %s\n" "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Must be root
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
    error "This script must be run as root (use doas sh setup.sh)."
fi

# ---------------------------------------------------------------------------
# Confirm OpenBSD
# ---------------------------------------------------------------------------
os=$(uname -s)
if [ "$os" != "OpenBSD" ]; then
    error "This script is for OpenBSD only (detected: $os)."
fi
info "Detected OS: OpenBSD $(uname -r)"

# ---------------------------------------------------------------------------
# Prompt for remote syslog server
# ---------------------------------------------------------------------------
printf "Enter the IP address or hostname of your remote syslog server: "
read -r SYSLOG_SERVER
if [ -z "$SYSLOG_SERVER" ]; then
    error "A remote syslog server address is required."
fi

printf "Use TCP instead of UDP for remote syslog? [y/N]: "
read -r SYSLOG_TCP
SYSLOG_TCP=$(printf '%s' "$SYSLOG_TCP" | tr '[:upper:]' '[:lower:]')

# ---------------------------------------------------------------------------
# 1. Install oath-toolkit
# ---------------------------------------------------------------------------
info "Installing oath-toolkit via pkg_add …"
if pkg_add oath-toolkit; then
    info "oath-toolkit installed."
else
    error "pkg_add oath-toolkit failed.  Check PKG_PATH and retry."
fi

# ---------------------------------------------------------------------------
# 2. Install login_totp BSD Auth script
# ---------------------------------------------------------------------------
AUTH_DIR="/usr/local/libexec/auth"
SCRIPT_SRC="$(dirname "$0")/login_totp"
SCRIPT_DST="$AUTH_DIR/login_totp"

if [ ! -f "$SCRIPT_SRC" ]; then
    error "login_totp not found at $SCRIPT_SRC — run setup.sh from the repository root."
fi

info "Installing $SCRIPT_DST …"
install -d -m 755 "$AUTH_DIR"
install -o root -g auth -m 550 "$SCRIPT_SRC" "$SCRIPT_DST"
info "login_totp installed."

# ---------------------------------------------------------------------------
# 3. Add "totp" login class to /etc/login.conf
# ---------------------------------------------------------------------------
LOGIN_CONF="/etc/login.conf"

if grep -q '^totp:' "$LOGIN_CONF"; then
    warn "'totp' login class already present in $LOGIN_CONF — skipping."
else
    info "Adding 'totp' login class to $LOGIN_CONF …"
    # Insert the totp class before the default class so it inherits from it.
    cat >> "$LOGIN_CONF" << 'EOF'

# TOTP (Google Authenticator) login class — added by setup.sh
totp:\
    :auth=-totp:\
    :tc=default:
EOF
    info "Login class added."
fi

# Rebuild the login.conf database
if [ -x /usr/bin/cap_mkdb ]; then
    cap_mkdb "$LOGIN_CONF"
    info "login.conf database rebuilt."
fi

# ---------------------------------------------------------------------------
# 4. Patch /etc/ssh/sshd_config
# ---------------------------------------------------------------------------
SSHD_CONF="/etc/ssh/sshd_config"
SSHD_BACKUP="${SSHD_CONF}.bak.$(date +%Y%m%d%H%M%S)"

info "Backing up $SSHD_CONF to $SSHD_BACKUP …"
cp "$SSHD_CONF" "$SSHD_BACKUP"

# Remove (comment out) any existing conflicting directives so we can add ours.
for key in \
    KbdInteractiveAuthentication \
    ChallengeResponseAuthentication \
    AuthenticationMethods \
    UsePAM
do
    if grep -qE "^[[:space:]]*${key}[[:space:]]" "$SSHD_CONF"; then
        warn "Commenting out existing '$key' directive in $SSHD_CONF."
        sed -i "s|^[[:space:]]*${key}[[:space:]]|#&|" "$SSHD_CONF"
    fi
done

# Append OpenBSD-specific block at the end of the file.
cat >> "$SSHD_CONF" << 'EOF'

# -----------------------------------------------------------------------
# Google Authenticator (TOTP) — added by setup.sh
# Require both a public key AND a keyboard-interactive TOTP code.
# -----------------------------------------------------------------------
KbdInteractiveAuthentication yes
AuthenticationMethods publickey,keyboard-interactive:bsdauth

# Disable password-based authentication completely (TOTP replaces it).
PasswordAuthentication no

# PAM is not used on OpenBSD; ensure it is disabled.
UsePAM no
EOF

info "sshd_config patched."

# Verify the configuration before restarting.
info "Verifying sshd configuration …"
if ! sshd -t -f "$SSHD_CONF"; then
    warn "sshd -t reported errors.  Restoring backup …"
    cp "$SSHD_BACKUP" "$SSHD_CONF"
    error "sshd_config verification failed.  Backup restored."
fi
info "sshd_config is valid."

# ---------------------------------------------------------------------------
# 5. Configure remote syslog forwarding
# ---------------------------------------------------------------------------
SYSLOG_CONF="/etc/syslog.conf"
SYSLOG_BACKUP="${SYSLOG_CONF}.bak.$(date +%Y%m%d%H%M%S)"

info "Backing up $SYSLOG_CONF to $SYSLOG_BACKUP …"
cp "$SYSLOG_CONF" "$SYSLOG_BACKUP"

# Build the forwarding target string.
# UDP: @host  TCP: @@host (syslogd -T must also be enabled; see below)
if [ "$SYSLOG_TCP" = "y" ] || [ "$SYSLOG_TCP" = "yes" ]; then
    FORWARD_TARGET="@@${SYSLOG_SERVER}"
    info "Using TCP syslog forwarding to $SYSLOG_SERVER"
else
    FORWARD_TARGET="@${SYSLOG_SERVER}"
    info "Using UDP syslog forwarding to $SYSLOG_SERVER"
fi

# Add forwarding rules if not already present.
if grep -q "$FORWARD_TARGET" "$SYSLOG_CONF"; then
    warn "Forwarding to $FORWARD_TARGET already present in $SYSLOG_CONF — skipping."
else
    {
        printf '\n'
        printf '# -----------------------------------------------------------------------\n'
        printf '# Remote syslog forwarding — added by setup.sh\n'
        printf '# Forward auth (login/ssh failures) and all warnings+ to remote server.\n'
        printf '# -----------------------------------------------------------------------\n'
        printf 'auth.info\t\t\t\t%s\n' "$FORWARD_TARGET"
        printf '*.warning\t\t\t\t%s\n' "$FORWARD_TARGET"
    } >> "$SYSLOG_CONF"
    info "Remote syslog forwarding rules added."
fi

# Enable TCP syslog in rc.conf.local when TCP was requested.
if [ "$SYSLOG_TCP" = "y" ] || [ "$SYSLOG_TCP" = "yes" ]; then
    RC_LOCAL="/etc/rc.conf.local"
    if grep -q 'syslogd_flags' "$RC_LOCAL" 2>/dev/null; then
        warn "syslogd_flags already set in $RC_LOCAL; ensure -T is included for TCP."
    else
        info "Enabling TCP reception in syslogd via $RC_LOCAL …"
        printf 'syslogd_flags="-T"\n' >> "$RC_LOCAL"
    fi
fi

# ---------------------------------------------------------------------------
# 6. Restart services
# ---------------------------------------------------------------------------
info "Restarting syslogd …"
rcctl restart syslogd

info "Restarting sshd …"
rcctl restart sshd

info "Services restarted."

# ---------------------------------------------------------------------------
# 7. Offer to enrol a user
# ---------------------------------------------------------------------------
printf "\nWould you like to enrol a user for Google Authenticator now? [y/N]: "
read -r DO_ENROL
DO_ENROL=$(printf '%s' "$DO_ENROL" | tr '[:upper:]' '[:lower:]')

if [ "$DO_ENROL" = "y" ] || [ "$DO_ENROL" = "yes" ]; then
    ENROL_SCRIPT="$(dirname "$0")/google-authenticator-setup.sh"
    if [ -x "$ENROL_SCRIPT" ]; then
        sh "$ENROL_SCRIPT"
    else
        warn "google-authenticator-setup.sh not found or not executable."
        warn "Run it manually: sh google-authenticator-setup.sh"
    fi
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
info "Setup complete."
info "Next steps:"
info "  1. Assign the 'totp' login class to each user that requires TOTP:"
info "       doas usermod -L totp <username>"
info "  2. Each user must run google-authenticator-setup.sh to create their"
info "       ~/.google_authenticator secret file."
info "  3. Verify remote syslog is receiving messages:"
info "       logger -p auth.info 'syslog forwarding test'"
info "  4. Test SSH login in a NEW session before closing this one."
