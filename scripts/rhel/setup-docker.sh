#!/bin/sh
# This script sets up Docker CE on RHEL-based systems, adds the specified user to the docker group,and configures the Docker daemon to use systemd as the cgroup driver with log rotation options.
# Usage: ./setup-docker.sh <username>

set -e

# Check if a username argument is provided
if [ "$#" -lt 1 ]; then
  echo "Usage: $(basename "$0") <username>"
  echo "  username  The system user to add to the docker group"
  exit 1
fi

# Get the target user from the command line argument
TARGET_USER="$1"

# Check if the specified user exists
if ! id "$TARGET_USER" >/dev/null 2>&1; then
  echo "Error: user '$TARGET_USER' does not exist"
  exit 1
fi

# Update and upgrade the system
sudo dnf -y update
sudo dnf -y upgrade

# Install Docker CE and related packages
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin container-selinux

# Add the docker group if it does not exist
if ! getent group docker; then
  sudo groupadd docker
fi

# Add the specified user to the docker group
sudo usermod -aG docker "$TARGET_USER"

# Configure Docker daemon to use systemd as the cgroup driver and set log rotation options
if [ -f /etc/docker/daemon.json ]; then
  echo "Existing /etc/docker/daemon.json found:"
  cat /etc/docker/daemon.json
  printf 'Replace existing daemon.json? [y/N] '
  read -r reply
  case "$reply" in
  [Yy])
    sudo tee /etc/docker/daemon.json >/dev/null <<EOF
{
  "exec-opts": [
    "native.cgroupdriver=systemd"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
    ;;
  *)
    echo "Skipping daemon.json update"
    ;;
  esac
else
  sudo tee /etc/docker/daemon.json >/dev/null <<EOF
{
  "exec-opts": [
    "native.cgroupdriver=systemd"
  ],
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
EOF
fi

# Enable and start Docker service
sudo systemctl enable --now docker
if sudo systemctl is-active --quiet docker; then
  echo "Docker service is enabled and running"
else
  echo "Failed to start Docker service"
  exit 1
fi

# Enable and start containerd service
sudo systemctl enable --now containerd
if sudo systemctl is-active --quiet containerd; then
  echo "containerd service is enabled and running"
else
  echo "Failed to start containerd service"
  exit 1
fi
