#!/bin/sh
set -e

if [ "$(id -u)" -ne 0 ]; then
  echo "Error: this script must be run as root (use sudo)" >&2
  exit 1
fi

if [ ! -f /etc/os-release ]; then
  echo "Error: /etc/os-release not found — this script requires a RHEL-compatible system" >&2
  exit 1
fi

# shellcheck disable=SC1091
RHEL_MAJOR=$(. /etc/os-release && printf '%s' "$VERSION_ID" | cut -d. -f1)

case "$RHEL_MAJOR" in
  8|9|10) ;;
  *)
    echo "Error: unsupported RHEL major version '$RHEL_MAJOR' (supported: 8, 9, 10)" >&2
    exit 1
    ;;
esac

# --- Redis password ---
if [ -t 0 ]; then
  stty -echo
fi

printf 'Redis password (min 8 chars, no spaces, no #): '
read -r REDIS_PASSWORD
printf '\n'

printf 'Confirm password: '
read -r REDIS_PASSWORD_CONFIRM
printf '\n'

if [ -t 0 ]; then
  stty echo
fi

if [ -z "$REDIS_PASSWORD" ]; then
  echo "Error: password cannot be empty" >&2
  exit 1
fi

PW_LEN=$(printf '%s' "$REDIS_PASSWORD" | wc -c | tr -d ' \t')
if [ "$PW_LEN" -lt 8 ]; then
  echo "Error: password must be at least 8 characters" >&2
  exit 1
fi

case "$REDIS_PASSWORD" in
  *' '*)
    echo "Error: password must not contain spaces" >&2
    exit 1
    ;;
esac

case "$REDIS_PASSWORD" in
  *'#'*)
    echo "Error: password must not contain '#'" >&2
    exit 1
    ;;
esac

if [ "$REDIS_PASSWORD" != "$REDIS_PASSWORD_CONFIRM" ]; then
  echo "Error: passwords do not match" >&2
  exit 1
fi

# --- Installation summary ---
case "$RHEL_MAJOR" in
  8|9) REPO_SOURCE="packages.redis.io/rpm/rockylinux${RHEL_MAJOR}" ;;
  10)  REPO_SOURCE="RHEL AppStream" ;;
esac

echo ""
echo "=== Redis Installation Summary ==="
printf 'RHEL version:   %s\n' "$RHEL_MAJOR"
printf 'Repository:     %s\n' "$REPO_SOURCE"
printf 'Bind address:   0.0.0.0\n'
printf 'Port:           6379\n'
echo ""

printf 'Proceed with installation? [y/N] '
read -r CONFIRM
case "$CONFIRM" in
  [Yy]) ;;
  *)
    echo "Aborted."
    exit 0
    ;;
esac
echo ""

# --- System update ---
echo "==> Updating system packages..."
dnf -y update
dnf -y upgrade

case "$RHEL_MAJOR" in
  8|9)
    # --- Import Redis GPG key ---
    echo ""
    echo "==> Importing Redis GPG key..."
    KEY_FILE=$(mktemp /tmp/redis-key-XXXXXX.gpg)
    trap 'rm -f "$KEY_FILE"' EXIT

    curl --fail --silent --show-error --location \
      "https://packages.redis.io/gpg" --output "$KEY_FILE"
    rpm --import "$KEY_FILE"
    echo "Redis GPG key imported."

    # --- Write /etc/yum.repos.d/redis.repo ---
    echo ""
    echo "==> Configuring Redis repository..."
    WRITE_REPO=1
    if [ -f /etc/yum.repos.d/redis.repo ]; then
      echo "Existing /etc/yum.repos.d/redis.repo:"
      cat /etc/yum.repos.d/redis.repo
      printf 'Overwrite? [y/N] '
      read -r REPLY
      case "$REPLY" in
        [Yy]) ;;
        *)
          echo "Skipping /etc/yum.repos.d/redis.repo update."
          WRITE_REPO=0
          ;;
      esac
    fi

    if [ "$WRITE_REPO" -eq 1 ]; then
      tee /etc/yum.repos.d/redis.repo >/dev/null <<EOF
[Redis]
name=Redis
baseurl=http://packages.redis.io/rpm/rockylinux${RHEL_MAJOR}
enabled=1
gpgcheck=1
EOF
      echo "/etc/yum.repos.d/redis.repo written."
    fi

    # --- Install redis ---
    echo ""
    echo "==> Installing Redis..."
    dnf -y install redis
    ;;

  10)
    # --- Install redis from AppStream ---
    echo ""
    echo "==> Installing Redis from AppStream..."
    dnf -y install redis
    ;;
esac

echo "Installed: $(redis-server --version)"

# --- Configure /etc/redis/redis.conf ---
echo ""
echo "==> Configuring /etc/redis/redis.conf..."

CONF="/etc/redis/redis.conf"

if [ ! -f "$CONF" ]; then
  echo "Error: $CONF not found after installation" >&2
  exit 1
fi

# Set bind to 0.0.0.0 (all interfaces)
if grep -q '^bind ' "$CONF"; then
  sed -i 's/^bind .*/bind 0.0.0.0/' "$CONF"
else
  printf 'bind 0.0.0.0\n' | tee -a "$CONF" >/dev/null
fi
echo "bind set to 0.0.0.0"

# Set requirepass (comment out any existing, then append)
sed -i 's/^requirepass/# requirepass/' "$CONF"
printf 'requirepass %s\n' "$REDIS_PASSWORD" | tee -a "$CONF" >/dev/null
echo "requirepass configured."

# --- Firewall ---
echo ""
if systemctl is-active --quiet firewalld; then
  echo "==> Configuring firewall for Redis..."
  firewall-cmd --permanent --add-port=6379/tcp
  firewall-cmd --reload
  echo "Firewall: opened port 6379/tcp."
else
  echo "firewalld is not active — skipping firewall configuration."
  echo "NOTE: Manually open port 6379/tcp if a firewall is in use."
fi

# --- Enable and start service ---
echo ""
echo "==> Enabling and starting redis service..."
systemctl enable --now redis

if systemctl is-active --quiet redis; then
  echo "redis is enabled and running."
else
  echo "Error: failed to start redis service." >&2
  echo "Check logs with: journalctl -u redis" >&2
  exit 1
fi

# --- Validate ---
echo ""
echo "==> Validating installation..."
if redis-cli --no-auth-warning -a "$REDIS_PASSWORD" ping | grep -q PONG; then
  echo "Redis responded to PING with PONG — installation validated."
else
  echo "Error: redis-cli ping failed." >&2
  echo "Check logs with: journalctl -u redis" >&2
  exit 1
fi

# --- Post-install summary ---
REDIS_VERSION=$(redis-server --version | awk '{print $3}' | sed 's/v=//')
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "=== Redis Installation Complete ==="
printf 'Version:        %s\n' "$REDIS_VERSION"
printf 'Endpoint:       %s:6379\n' "$SERVER_IP"
printf 'Config:         %s\n' "$CONF"
echo ""
echo "  Service logs:   journalctl -u redis"
echo "  Service status: systemctl status redis"
