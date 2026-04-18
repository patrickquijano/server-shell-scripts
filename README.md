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
curl -fsSL https://raw.githubusercontent.com/patrickquijano/server-shell-scripts/main/scripts/rhel/setup-docker.sh | sudo bash -s -- <username>
```

```bash
curl -fsSL https://raw.githubusercontent.com/patrickquijano/server-shell-scripts/main/scripts/rhel/setup-dnf-automatic.sh | sudo bash
```

> **Tip:** Review the script contents before piping to a shell — visit the raw URL in a browser or run `curl -fsSL <url>` without `| sudo bash` first.

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
sudo bash scripts/rhel/setup-docker.sh <username>
# Example:
sudo bash scripts/rhel/setup-docker.sh azureuser
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
- **Docker group membership** — `setup-docker.sh` accepts a required `<username>` argument and adds that user to the `docker` group so Docker commands can be run without `sudo`. You may need to log out and back in for this to take effect in new terminal sessions.
- **daemon.json prompt** — if `/etc/docker/daemon.json` already exists when `setup-docker.sh` is run, the script will display the current contents and ask whether to overwrite it. Answering `N` skips the update and leaves the existing configuration in place.
- **System update on every run** — both scripts begin with a full `dnf update && dnf upgrade`, so they may take several minutes on a freshly provisioned system.

## License

[MIT](LICENSE) © Patrick Quijano
