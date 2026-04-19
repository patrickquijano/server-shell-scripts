#!/bin/sh

set -e

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
  echo "Error: this script must be run as root (use sudo)" >&2
  exit 1
fi

# Update and upgrade the system
dnf -y update
dnf -y upgrade

# Install dnf-automatic for automatic updates
dnf -y install dnf-automatic

upgrade_type_updated=0
apply_updates_updated=0

# Check the current upgrade_type setting and prompt the user to update it to "default" if it is not already set to "default"
current_upgrade_type=$(grep '^upgrade_type' /etc/dnf/automatic.conf | sed 's/.*= //')
echo "Current upgrade_type: $current_upgrade_type"
printf 'Set upgrade_type to "default"? [y/N] '
read -r reply
case "$reply" in
[Yy])
  sed -i 's/^upgrade_type = .*/upgrade_type = default/' /etc/dnf/automatic.conf
  new_upgrade_type=$(grep '^upgrade_type' /etc/dnf/automatic.conf | sed 's/.*= //')
  if [ "$new_upgrade_type" != "$current_upgrade_type" ]; then
    upgrade_type_updated=1
  fi
  ;;
*)
  echo "Skipping upgrade_type update"
  ;;
esac

# Check the current apply_updates setting and prompt the user to update it to "yes" if it is not already set to "yes"
current_apply_updates=$(grep '^apply_updates' /etc/dnf/automatic.conf | sed 's/.*= //')
echo "Current apply_updates: $current_apply_updates"
printf 'Set apply_updates to "yes"? [y/N] '
read -r reply
case "$reply" in
[Yy])
  sed -i 's/^apply_updates = .*/apply_updates = yes/' /etc/dnf/automatic.conf
  new_apply_updates=$(grep '^apply_updates' /etc/dnf/automatic.conf | sed 's/.*= //')
  if [ "$new_apply_updates" != "$current_apply_updates" ]; then
    apply_updates_updated=1
  fi
  ;;
*)
  echo "Skipping apply_updates update"
  ;;
esac

# Show only settings that were updated
if [ "$upgrade_type_updated" -eq 1 ] || [ "$apply_updates_updated" -eq 1 ]; then
  echo "Updated settings in /etc/dnf/automatic.conf:"
  if [ "$upgrade_type_updated" -eq 1 ]; then
    grep '^upgrade_type' /etc/dnf/automatic.conf
  fi
  if [ "$apply_updates_updated" -eq 1 ]; then
    grep '^apply_updates' /etc/dnf/automatic.conf
  fi
else
  echo "No settings were updated in /etc/dnf/automatic.conf"
fi

# Enable and start the dnf-automatic timer to run daily
systemctl enable --now dnf-automatic.timer
if systemctl is-active --quiet dnf-automatic.timer; then
  echo "dnf-automatic timer is enabled and running"
else
  echo "Failed to start dnf-automatic timer" >&2
  exit 1
fi
