# server-shell-scripts

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A collection of shell scripts for provisioning and configuring Red Hat Enterprise Linux (RHEL) servers. These scripts automate common setup tasks such as installing Docker CE and enabling automatic system updates.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Scripts](#scripts)
  - [setup-docker.sh](#setup-dockersh)
  - [setup-dnf-automatic.sh](#setup-dnf-automaticsh)
  - [setup-new-disk.sh](#setup-new-disksh)
  - [setup-existing-disk.sh](#setup-existing-disksh)
  - [setup-postgresql.sh](#setup-postgresqlsh)
  - [setup-minio.sh](#setup-miniosh)
  - [setup-redis.sh](#setup-redissh)
- [Notes](#notes)
- [License](#license)

## Prerequisites

- RHEL 8/9/10 or a compatible distribution (Rocky Linux, AlmaLinux, etc.)
- `sudo` or root access
- `dnf` package manager

> **Tip:** Review the script contents before piping to a shell — visit the raw URL in a browser or run `curl -fsSL <url>` without `| sudo sh` first.

## Scripts

### setup-docker.sh

**Location:** `scripts/rhel/setup-docker.sh`

Installs Docker CE and related tooling on a RHEL system with a production-ready daemon configuration.

**What it does:**

- Validates that a `<username>` argument is provided and that the user exists on the system
- Updates and upgrades all system packages via `dnf`
- Installs `dnf-plugins-core` and adds Docker's official RHEL repository
- Installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, `docker-compose-plugin`, and `container-selinux`
- Creates the `docker` group if it does not already exist, and adds the specified user to it
- Writes `/etc/docker/daemon.json` — prompts before overwriting if the file already exists — with:
  - `systemd` cgroup driver
  - JSON file logging with 10 MB max size and 3-file rotation
- Enables and starts the `docker` systemd service if it is not already running
- Enables and starts the `containerd` systemd service if it is not already running

**Usage:**

```bash
sudo sh scripts/rhel/setup-docker.sh <username>
# Example:
sudo sh scripts/rhel/setup-docker.sh azureuser
```

> **Note:** This script is fully interactive — it reads from the terminal. Piping it from `curl` will break the prompts. Download it first, then run it:
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/patrickquijano/server-shell-scripts/main/scripts/rhel/setup-docker.sh.sh -o /tmp/setup-docker.sh.sh && sudo sh /tmp/setup-docker.sh.sh $USER
> ```

---

### setup-dnf-automatic.sh

**Location:** `scripts/rhel/setup-dnf-automatic.sh`

Configures unattended daily system updates using `dnf-automatic`.

**What it does:**

- Updates and upgrades all system packages via `dnf`
- Installs the `dnf-automatic` package
- Reads the current `upgrade_type` and `apply_updates` values from `/etc/dnf/automatic.conf` and prompts `[y/N]` to set each to `default` / `yes` respectively
- Enables and starts the `dnf-automatic.timer` systemd unit to run daily

**Usage:**

```bash
sudo sh scripts/rhel/setup-dnf-automatic.sh
```

> **Note:** This script is fully interactive — it reads from the terminal. Piping it from `curl` will break the prompts. Download it first, then run it:
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/patrickquijano/server-shell-scripts/main/scripts/rhel/setup-dnf-automatic.sh -o /tmp/setup-dnf-automatic.sh && sudo sh /tmp/setup-dnf-automatic.sh
> ```

---

### setup-new-disk.sh

**Location:** `scripts/rhel/setup-new-disk.sh`

Identifies unpartitioned disks, prompts to select one, creates a single XFS partition on a GPT partition table, mounts it at a user-specified path, and writes a UUID-based `/etc/fstab` entry so the mount persists across reboots.

**What it does:**

- Detects block devices with no existing partitions and presents them in a numbered list
- Prompts to select a disk and validates the input
- Prompts for an absolute mount point path and validates it is not already in use
- Displays a summary and requires explicit `[y/N]` confirmation before any disk changes
- Creates a GPT partition table and a single data partition (1 MiB aligned, full disk)
- Formats the partition with XFS using `mkfs.xfs`
- Creates the mount point directory, mounts the partition, and appends a UUID-based entry to `/etc/fstab`
- Displays `lsblk`, `df -h`, and the fstab entry to confirm success

**Usage:**

```bash
sudo sh scripts/rhel/setup-new-disk.sh
```

> **Note:** This script is fully interactive — it reads from the terminal. Piping it from `curl` will break the prompts. Download it first, then run it:
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/patrickquijano/server-shell-scripts/main/scripts/rhel/setup-new-disk.sh -o /tmp/setup-new-disk.sh && sudo sh /tmp/setup-new-disk.sh
> ```

---

### setup-existing-disk.sh

**Location:** `scripts/rhel/setup-existing-disk.sh`

Identifies existing partitions that already have filesystems but are not currently mounted, prompts to select one, mounts it at a user-specified path, and writes a UUID-based `/etc/fstab` entry so the mount persists across reboots.

**What it does:**

- Detects unmounted partitions where a filesystem already exists (no partitioning or formatting)
- Prompts to select one partition and validates the input
- Prompts for an absolute mount point path and validates it is not already in use
- Aborts if `/etc/fstab` already contains an entry for the selected partition UUID, device path, or mount point
- Displays a summary and requires explicit `[y/N]` confirmation before mounting
- Creates the mount point directory, mounts the partition, and appends a UUID-based entry to `/etc/fstab`
- Displays `lsblk`, `df -h`, and the fstab entry to confirm success

**Usage:**

```bash
sudo sh scripts/rhel/setup-existing-disk.sh
```

> **Note:** This script is fully interactive — it reads from the terminal. Piping it from `curl` will break the prompts. Download it first, then run it:
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/patrickquijano/server-shell-scripts/main/scripts/rhel/setup-existing-disk.sh -o /tmp/setup-existing-disk.sh && sudo sh /tmp/setup-existing-disk.sh
> ```

---

### setup-postgresql.sh

**Location:** `scripts/rhel/setup-postgresql.sh`

Installs a user-selected PostgreSQL version from the official PGDG repository on a RHEL system, initializes the database cluster at a configurable data directory, sets the `postgres` superuser password, and validates connectivity.

**What it does:**

- Detects the RHEL major version (8, 9, or 10) and CPU architecture at runtime
- Presents a numbered list of available PostgreSQL versions for the detected OS:
  - RHEL 8/9: PostgreSQL 14, 15, 16, 17
  - RHEL 10: PostgreSQL 16, 17
- Prompts for the data directory (PGDATA), defaulting to `/var/lib/pgsql/<version>/data`
- Prompts for the `postgres` superuser password (input is hidden; confirmation required)
- Displays an installation summary and requires explicit `[y/N]` confirmation before any changes
- Updates and upgrades all system packages via `dnf`
- Installs the official PGDG repository RPM for the detected OS and architecture
- Disables the built-in AppStream `postgresql` module to prevent version conflicts
- Installs `postgresql<version>-server` from the PGDG repository
- When a non-default PGDATA is chosen: creates the directory with `postgres:postgres` ownership and `700` permissions, writes a systemd drop-in override at `/etc/systemd/system/postgresql-<version>.service.d/pgdata.conf`, and reloads systemd
- Initializes the cluster using `/usr/pgsql-<version>/bin/postgresql-<version>-setup initdb`
- Enables and starts the `postgresql-<version>` systemd service
- Sets the `postgres` superuser password via `ALTER ROLE postgres WITH PASSWORD '...'`
- Validates cluster connectivity with `SELECT version()` and prints the final service status

**Usage:**

```bash
sudo sh scripts/rhel/setup-postgresql.sh
```

> **Note:** This script is fully interactive — it reads from the terminal. Piping it from `curl` will break the prompts. Download it first, then run it:
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/patrickquijano/server-shell-scripts/main/scripts/rhel/setup-postgresql.sh -o /tmp/setup-postgresql.sh && sudo sh /tmp/setup-postgresql.sh
> ```

---

### setup-minio.sh

**Location:** `scripts/rhel/setup-minio.sh`

Installs MinIO server (self-hosted S3-compatible object storage) on a RHEL system, configures it as a systemd service, and validates the installation.

**What it does:**

- Detects the RHEL major version (8, 9, or 10) and CPU architecture at runtime
- Prompts for the data directory, defaulting to `/var/lib/minio/data`
- Prompts for the admin username (default: `minioadmin`) and password (input is hidden; confirmation required; minimum 8 characters)
- Displays an installation summary and requires explicit `[y/N]` confirmation before any changes
- Updates and upgrades all system packages via `dnf`
- Downloads and installs the latest MinIO community RPM from `dl.min.io/server/minio` for the detected architecture
- Creates the data directory if it does not exist and sets ownership to `minio-user:minio-user`
- Writes `/etc/default/minio` with `MINIO_VOLUMES`, `MINIO_ROOT_USER`, `MINIO_ROOT_PASSWORD`, and `MINIO_CONSOLE_ADDRESS=":9001"` — prompts before overwriting if the file already exists
- Opens ports 9000 (API) and 9001 (Console) via `firewall-cmd` if `firewalld` is active
- Enables and starts the `minio` systemd service
- Downloads the `mc` (MinIO Client) binary from `dl.min.io/client/mc` and installs it to `/usr/local/bin/mc`
- Waits for the MinIO health endpoint to respond, then validates with `mc admin info`
- Prints the API endpoint, Console URL, and service management commands

**Usage:**

```bash
sudo sh scripts/rhel/setup-minio.sh
```

> **Note:** This script is fully interactive — it reads from the terminal. Piping it from `curl` will break the prompts. Download it first, then run it:
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/patrickquijano/server-shell-scripts/main/scripts/rhel/setup-minio.sh -o /tmp/setup-minio.sh && sudo sh /tmp/setup-minio.sh
> ```

### setup-redis.sh

**Location:** `scripts/rhel/setup-redis.sh`

Installs the latest stable Redis server from the official Redis repository on a RHEL system, configures it for network access with password authentication, and validates the installation.

**What it does:**

- Detects the RHEL major version (8, 9, or 10) at runtime; exits with an error on unsupported versions
- Prompts for a Redis password (input is hidden; confirmation required; minimum 8 characters; no spaces or `#` characters)
- Displays an installation summary and requires explicit `[y/N]` confirmation before any changes
- Updates and upgrades all system packages via `dnf`
- On RHEL 8/9: imports the official Redis GPG key from `packages.redis.io`, writes `/etc/yum.repos.d/redis.repo` — prompts before overwriting if the file already exists — and installs the latest stable `redis` package from the official Redis repository
- On RHEL 10: installs `redis` directly from the RHEL AppStream
- Configures `/etc/redis/redis.conf` to bind on all interfaces (`0.0.0.0`) and sets `requirepass` to the provided password
- Opens port 6379 via `firewall-cmd` if `firewalld` is active; prints a manual reminder otherwise
- Enables and starts the `redis` systemd service
- Validates the installation with `redis-cli ping` and prints the server endpoint

**Usage:**

```bash
sudo sh scripts/rhel/setup-redis.sh
```

> **Note:** This script is fully interactive — it reads from the terminal. Piping it from `curl` will break the prompts. Download it first, then run it:
>
> ```bash
> curl -fsSL https://raw.githubusercontent.com/patrickquijano/server-shell-scripts/main/scripts/rhel/setup-redis.sh -o /tmp/setup-redis.sh && sudo sh /tmp/setup-redis.sh
> ```

## Notes

- **Both scripts are independent and complementary.** Run both to get a fully configured Docker host with automatic system updates.
- **Docker group membership** — `setup-docker.sh` accepts a required `<username>` argument and adds that user to the `docker` group so Docker commands can be run without `sudo`. You may need to log out and back in for this to take effect in new terminal sessions.
- **daemon.json prompt** — if `/etc/docker/daemon.json` already exists when `setup-docker.sh` is run, the script will display the current contents and ask whether to overwrite it. Answering `N` skips the update and leaves the existing configuration in place.
- **System update on every run** — both scripts begin with a full `dnf update && dnf upgrade`, so they may take several minutes on a freshly provisioned system.
- **MinIO community edition** — `setup-minio.sh` installs the open-source community MinIO server (`AGPL-3.0`). No license registration is required.
- **Redis repository source** — `setup-redis.sh` uses the official Redis repository (`packages.redis.io`) on RHEL 8 and 9 for the latest stable release, and falls back to the RHEL AppStream on RHEL 10.

## License

[MIT](LICENSE) © Patrick Quijano
