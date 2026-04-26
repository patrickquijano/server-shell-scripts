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

ARCH_RAW=$(uname -m)
case "$ARCH_RAW" in
  x86_64)  ARCH="amd64" ;;
  aarch64) ARCH="arm64" ;;
  *)
    echo "Error: unsupported architecture '$ARCH_RAW' (supported: x86_64, aarch64)" >&2
    exit 1
    ;;
esac

# --- Data directory ---
DEFAULT_DATA_DIR="/var/lib/minio/data"

echo ""
printf 'MinIO data directory [%s]: ' "$DEFAULT_DATA_DIR"
read -r DATA_INPUT

if [ -z "$DATA_INPUT" ]; then
  DATA_DIR="$DEFAULT_DATA_DIR"
else
  DATA_DIR="$DATA_INPUT"
fi

case "$DATA_DIR" in
  /*) ;;
  *)
    echo "Error: data directory must be an absolute path starting with '/'" >&2
    exit 1
    ;;
esac

if [ -e "$DATA_DIR" ] && [ -n "$(ls -A "$DATA_DIR" 2>/dev/null)" ]; then
  echo "Error: '$DATA_DIR' exists and is not empty — choose an empty or non-existent directory" >&2
  exit 1
fi

# --- Admin username ---
DEFAULT_ROOT_USER="minioadmin"

printf 'MinIO admin username [%s]: ' "$DEFAULT_ROOT_USER"
read -r USER_INPUT

if [ -z "$USER_INPUT" ]; then
  ROOT_USER="$DEFAULT_ROOT_USER"
else
  ROOT_USER="$USER_INPUT"
fi

# --- Admin password ---
if [ -t 0 ]; then
  stty -echo
fi

printf 'MinIO admin password (min 8 chars, no double quotes): '
read -r ROOT_PASSWORD
printf '\n'

printf 'Confirm password: '
read -r ROOT_PASSWORD_CONFIRM
printf '\n'

if [ -t 0 ]; then
  stty echo
fi

if [ -z "$ROOT_PASSWORD" ]; then
  echo "Error: password cannot be empty" >&2
  exit 1
fi

PW_LEN=$(printf '%s' "$ROOT_PASSWORD" | wc -c | tr -d ' \t')
if [ "$PW_LEN" -lt 8 ]; then
  echo "Error: password must be at least 8 characters" >&2
  exit 1
fi

case "$ROOT_PASSWORD" in
  *'"'*)
    echo 'Error: password must not contain a double quote (")' >&2
    exit 1
    ;;
esac

if [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD_CONFIRM" ]; then
  echo "Error: passwords do not match" >&2
  exit 1
fi

# --- Installation summary ---
echo ""
echo "=== MinIO AIStor Installation Summary ==="
printf 'RHEL version:    %s\n' "$RHEL_MAJOR"
printf 'Architecture:    %s\n' "$ARCH_RAW"
printf 'Data directory:  %s\n' "$DATA_DIR"
printf 'Admin user:      %s\n' "$ROOT_USER"
printf 'API port:        9000\n'
printf 'Console port:    9001\n'
echo ""
echo "NOTE: A free AIStor license must be registered after install"
echo "      to enable S3 operations. Run: mc license register minio-local"
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
echo "Updating system packages..."
sudo dnf -y update
sudo dnf -y upgrade

# --- Download and install MinIO AIStor RPM ---
RPM_FILE=$(mktemp /tmp/minio-XXXXXX.rpm)
trap 'rm -f "$RPM_FILE"' EXIT

RPM_URL="https://dl.min.io/aistor/minio/release/linux-${ARCH}/minio.rpm"
echo "Downloading MinIO AIStor (linux-${ARCH})..."
curl --fail --silent --show-error --location --progress-bar \
  "$RPM_URL" --output "$RPM_FILE"

echo "Installing MinIO AIStor RPM..."
sudo dnf -y install "$RPM_FILE"

echo "Installed: $(minio --version)"

# --- Data directory ---
if [ ! -d "$DATA_DIR" ]; then
  echo "Creating data directory: $DATA_DIR"
  sudo mkdir -p "$DATA_DIR"
fi
sudo chown -R minio-user:minio-user "$DATA_DIR"
echo "Set ownership minio-user:minio-user on $DATA_DIR"

# --- Write /etc/default/minio ---
WRITE_ENV=1
if [ -f /etc/default/minio ]; then
  echo ""
  echo "Existing /etc/default/minio:"
  cat /etc/default/minio
  printf 'Overwrite? [y/N] '
  read -r REPLY
  case "$REPLY" in
    [Yy]) ;;
    *)
      echo "Skipping /etc/default/minio update."
      WRITE_ENV=0
      ;;
  esac
fi

if [ "$WRITE_ENV" -eq 1 ]; then
  {
    printf '# MinIO AIStor environment configuration\n'
    printf '# See: https://docs.min.io/enterprise/aistor-object-store/\n'
    printf '\n'
    printf '# Storage backend\n'
    printf 'MINIO_VOLUMES="%s"\n' "$DATA_DIR"
    printf '\n'
    printf '# Admin credentials\n'
    printf 'MINIO_ROOT_USER="%s"\n' "$ROOT_USER"
    printf 'MINIO_ROOT_PASSWORD="%s"\n' "$ROOT_PASSWORD"
    printf '\n'
    printf '# Fix the web console on port 9001\n'
    printf 'MINIO_CONSOLE_ADDRESS=":9001"\n'
    printf '\n'
    printf '# AIStor license (register after install: mc license register minio-local)\n'
    printf '# MINIO_LICENSE="/opt/minio/minio.license"\n'
  } | sudo tee /etc/default/minio >/dev/null
  echo "/etc/default/minio written."
fi

# --- Firewall ---
if systemctl is-active --quiet firewalld; then
  echo "Configuring firewall rules for MinIO..."
  sudo firewall-cmd --permanent --add-port=9000/tcp
  sudo firewall-cmd --permanent --add-port=9001/tcp
  sudo firewall-cmd --reload
  echo "Firewall: opened ports 9000 (API) and 9001 (Console)."
else
  echo "firewalld is not active — skipping firewall configuration."
  echo "NOTE: Manually open ports 9000 and 9001 if a firewall is in use."
fi

# --- Start service ---
echo "Enabling and starting minio service..."
sudo systemctl enable --now minio

if sudo systemctl is-active --quiet minio; then
  echo "minio is enabled and running."
else
  echo "Error: failed to start minio service." >&2
  echo "Check logs with: journalctl -u minio" >&2
  exit 1
fi

# --- Install mc (MinIO Client) ---
MC_FILE=$(mktemp /tmp/mc-XXXXXX)
trap 'rm -f "$RPM_FILE" "$MC_FILE"' EXIT

MC_URL="https://dl.min.io/aistor/mc/release/linux-${ARCH}/mc"
echo "Downloading mc client (linux-${ARCH})..."
curl --fail --silent --show-error --location --progress-bar \
  "$MC_URL" --output "$MC_FILE"

chmod +x "$MC_FILE"
sudo mv "$MC_FILE" /usr/local/bin/mc
echo "Installed: $(mc --version)"

# --- Wait for MinIO API to be ready ---
echo "Waiting for MinIO API to become ready..."
RETRIES=10
while [ "$RETRIES" -gt 0 ]; do
  if curl --fail --silent "http://127.0.0.1:9000/minio/health/live" >/dev/null 2>&1; then
    echo "MinIO health endpoint is responding."
    break
  fi
  RETRIES=$((RETRIES - 1))
  sleep 3
done

if [ "$RETRIES" -eq 0 ]; then
  echo "Error: MinIO health endpoint did not respond after 30 seconds." >&2
  echo "Check logs with: journalctl -u minio" >&2
  exit 1
fi

# --- Configure mc alias and validate ---
mc alias set minio-local "http://127.0.0.1:9000" "$ROOT_USER" "$ROOT_PASSWORD" >/dev/null

if mc admin info minio-local >/dev/null 2>&1; then
  echo "MinIO AIStor is healthy and accepting admin commands."
else
  echo "Warning: mc admin info failed — server may still be initializing." >&2
  echo "Run manually: mc admin info minio-local" >&2
fi

# --- Post-install summary ---
SERVER_IP=$(hostname -I | awk '{print $1}')
echo ""
echo "=== MinIO AIStor Installation Complete ==="
printf 'API endpoint:    http://%s:9000\n' "$SERVER_IP"
printf 'Console URL:     http://%s:9001\n' "$SERVER_IP"
printf 'Admin user:      %s\n' "$ROOT_USER"
printf 'Data directory:  %s\n' "$DATA_DIR"
echo ""
echo "IMPORTANT: S3 operations are blocked until a free license is registered."
echo "  Register now:   mc license register minio-local"
echo "  Service logs:   journalctl -u minio"
echo "  Service status: systemctl status minio"
