# server-shell-scripts

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

A collection of shell scripts for provisioning and configuring Red Hat Enterprise Linux (RHEL) servers. These scripts automate common setup tasks such as installing Docker CE and enabling automatic system updates.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Scripts](#scripts)
  - [setup-docker.sh](#setup-dockersh)
  - [setup-dnf-automatic.sh](#setup-dnf-automaticsh)
- [Notes](#notes)
- [License](#license)

## Prerequisites

- RHEL 8/9 or a compatible distribution (Rocky Linux, AlmaLinux, etc.)
- `sudo` or root access
- `dnf` package manager

## Quick Start

Run a script directly from the repository without cloning it first:

```bash
# Install Docker CE
curl -fsSL https://raw.githubusercontent.com/patrickquijano/server-shell-scripts/main/scripts/rhel/setup-docker.sh | sudo bash

# Configure automatic system updates
curl -fsSL https://raw.githubusercontent.com/patrickquijano/server-shell-scripts/main/scripts/rhel/setup-dnf-automatic.sh | sudo bash
```

> **Tip:** Review the script contents before piping to a shell — visit the raw URL in a browser or run `curl -fsSL <url>` without `| sudo bash` first.

## Scripts

### setup-docker.sh

**Location:** `scripts/rhel/setup-docker.sh`

Installs Docker CE and related tooling on a RHEL system with a production-ready daemon configuration.

**What it does:**

- Updates and upgrades all system packages via `dnf`
- Adds Docker's official RHEL repository
- Installs `docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, and `docker-compose-plugin`
- Enables and starts the Docker systemd service
- Creates the `docker` group and adds the current user to it
- Installs `container-selinux` for SELinux compatibility
- Writes `/etc/docker/daemon.json` with:
  - `systemd` cgroup driver
  - JSON file logging with 10 MB max size and 3-file rotation
- Reloads systemd and restarts Docker
- Validates the installation by running the `hello-world` container

**Usage:**

```bash
sudo bash scripts/rhel/setup-docker.sh
```

---

### setup-dnf-automatic.sh

**Location:** `scripts/rhel/setup-dnf-automatic.sh`

Configures unattended daily system updates using `dnf-automatic`.

**What it does:**

- Updates and upgrades all system packages via `dnf`
- Installs the `dnf-automatic` package
- Configures `/etc/dnf/automatic.conf`:
  - `upgrade_type = default` — applies all available updates
  - `apply_updates = yes` — updates are applied automatically without manual intervention
- Enables and starts the `dnf-automatic.timer` systemd unit to run daily

**Usage:**

```bash
sudo bash scripts/rhel/setup-dnf-automatic.sh
```

## Notes

- **Both scripts are independent and complementary.** Run both to get a fully configured Docker host with automatic system updates.
- **Docker group membership** — `setup-docker.sh` adds the current user to the `docker` group so Docker commands can be run without `sudo`. You may need to log out and back in for this to take effect in new terminal sessions.
- **System update on every run** — both scripts begin with a full `dnf update && dnf upgrade`, so they may take several minutes on a freshly provisioned system.

## License

[MIT](LICENSE) © Patrick Quijano
