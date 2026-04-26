#!/bin/sh
set -e

# ── Root check ──────────────────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: this script must be run as root (use sudo)" >&2
  exit 1
fi

# ── OS detection ─────────────────────────────────────────────────────────────
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

ARCH=$(uname -m)
case "$ARCH" in
  x86_64|aarch64|ppc64le) ;;
  *)
    echo "Error: unsupported architecture '$ARCH'" >&2
    exit 1
    ;;
esac

# ── PostgreSQL version selection ──────────────────────────────────────────────
case "$RHEL_MAJOR" in
  8|9) PG_VERSIONS="14 15 16 17" ;;
  10)  PG_VERSIONS="16 17" ;;
esac

echo ""
echo "Available PostgreSQL versions for RHEL ${RHEL_MAJOR}:"
i=1
for ver in $PG_VERSIONS; do
  printf '  %d) PostgreSQL %s\n' "$i" "$ver"
  i=$((i + 1))
done
TOTAL=$((i - 1))

printf 'Select version [1-%d]: ' "$TOTAL"
read -r SEL

case "$SEL" in
  ''|*[!0-9]*)
    echo "Error: '$SEL' is not a valid number" >&2
    exit 1
    ;;
esac

if [ "$SEL" -lt 1 ] || [ "$SEL" -gt "$TOTAL" ]; then
  echo "Error: selection must be between 1 and $TOTAL" >&2
  exit 1
fi

i=1
PG_VER=""
for ver in $PG_VERSIONS; do
  if [ "$i" -eq "$SEL" ]; then
    PG_VER="$ver"
    break
  fi
  i=$((i + 1))
done

# ── Data directory ────────────────────────────────────────────────────────────
DEFAULT_PGDATA="/var/lib/pgsql/${PG_VER}/data"

echo ""
printf 'PostgreSQL data directory [%s]: ' "$DEFAULT_PGDATA"
read -r PGDATA_INPUT

if [ -z "$PGDATA_INPUT" ]; then
  PGDATA="$DEFAULT_PGDATA"
else
  PGDATA="$PGDATA_INPUT"
fi

case "$PGDATA" in
  /*) ;;
  *)
    echo "Error: data directory must be an absolute path starting with '/'" >&2
    exit 1
    ;;
esac

if [ -e "$PGDATA" ] && [ -n "$(ls -A "$PGDATA" 2>/dev/null)" ]; then
  echo "Error: '$PGDATA' exists and is not empty — choose an empty or non-existent directory" >&2
  exit 1
fi

if [ "$PGDATA" = "$DEFAULT_PGDATA" ]; then
  CUSTOM_PGDATA=0
else
  CUSTOM_PGDATA=1
fi

# ── Postgres superuser password ───────────────────────────────────────────────
echo ""

if [ -t 0 ]; then
  stty -echo
fi

printf 'PostgreSQL superuser (postgres) password: '
read -r PG_PASSWORD
printf '\n'

printf 'Confirm password: '
read -r PG_PASSWORD_CONFIRM
printf '\n'

if [ -t 0 ]; then
  stty echo
fi

if [ -z "$PG_PASSWORD" ]; then
  echo "Error: password cannot be empty" >&2
  exit 1
fi

if [ "$PG_PASSWORD" != "$PG_PASSWORD_CONFIRM" ]; then
  echo "Error: passwords do not match" >&2
  exit 1
fi

# ── Installation summary and confirmation ─────────────────────────────────────
echo ""
echo "=== Installation Summary ==="
printf 'RHEL version:       %s\n' "$RHEL_MAJOR"
printf 'Architecture:       %s\n' "$ARCH"
printf 'PostgreSQL version: %s\n' "$PG_VER"
printf 'Data directory:     %s\n' "$PGDATA"
printf 'Service name:       postgresql-%s\n' "$PG_VER"
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

# ── System update and PGDG repository ────────────────────────────────────────
echo "==> Updating system packages..."
dnf -y update
dnf -y upgrade

echo ""
echo "==> Installing PostgreSQL PGDG repository..."
REPO_URL="https://download.postgresql.org/pub/repos/yum/reporpms/EL-${RHEL_MAJOR}-${ARCH}/pgdg-redhat-repo-latest.noarch.rpm"
dnf -y install "$REPO_URL"

echo ""
echo "==> Disabling built-in postgresql AppStream module..."
case "$RHEL_MAJOR" in
  8|9)
    dnf -y module disable postgresql
    ;;
  10)
    dnf -y module disable postgresql 2>/dev/null || true
    ;;
esac

# ── Install postgresql-server ─────────────────────────────────────────────────
echo ""
echo "==> Installing PostgreSQL ${PG_VER} server..."
dnf -y install "postgresql${PG_VER}-server"

# ── Custom PGDATA systemd override ────────────────────────────────────────────
if [ "$CUSTOM_PGDATA" -eq 1 ]; then
  echo ""
  echo "==> Configuring custom data directory: ${PGDATA}"

  mkdir -p "$PGDATA"
  chown postgres:postgres "$PGDATA"
  chmod 700 "$PGDATA"

  OVERRIDE_DIR="/etc/systemd/system/postgresql-${PG_VER}.service.d"
  mkdir -p "$OVERRIDE_DIR"

  sudo tee "${OVERRIDE_DIR}/pgdata.conf" >/dev/null <<EOF
[Service]
Environment=PGDATA=${PGDATA}
EOF

  systemctl daemon-reload
  echo "Systemd override written to ${OVERRIDE_DIR}/pgdata.conf"
fi

# ── Initialize database cluster ───────────────────────────────────────────────
echo ""
echo "==> Initializing PostgreSQL ${PG_VER} database cluster..."
"/usr/pgsql-${PG_VER}/bin/postgresql-${PG_VER}-setup" initdb

# ── Enable and start service ──────────────────────────────────────────────────
echo ""
echo "==> Enabling and starting postgresql-${PG_VER}..."
systemctl enable --now "postgresql-${PG_VER}"

if systemctl is-active --quiet "postgresql-${PG_VER}"; then
  echo "postgresql-${PG_VER} is enabled and running"
else
  echo "Error: failed to start postgresql-${PG_VER}" >&2
  exit 1
fi

# ── Set postgres superuser password ──────────────────────────────────────────
echo ""
echo "==> Setting postgres superuser password..."
ESCAPED_PW=$(printf '%s' "$PG_PASSWORD" | sed "s/'/''/g")
printf "ALTER ROLE postgres WITH PASSWORD '%s';\n" "$ESCAPED_PW" \
  | su -c "psql" - postgres

# ── Validate and print final summary ─────────────────────────────────────────
echo ""
echo "==> Validating installation..."
PG_VERSION_STRING=$(su -c "psql -tAc 'SELECT version();'" - postgres)
echo "Connection successful."
echo ""
echo "=== PostgreSQL Installation Complete ==="
printf 'Version:        %s\n' "$PG_VERSION_STRING"
printf 'Data directory: %s\n' "$PGDATA"
printf 'Service:        postgresql-%s\n' "$PG_VER"
echo ""
echo "Service status:"
systemctl status "postgresql-${PG_VER}" --no-pager
