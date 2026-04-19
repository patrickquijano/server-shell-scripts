#!/bin/sh

# Update and upgrade the system
sudo dnf -y update
sudo dnf -y upgrade

# Install dnf-automatic for automatic updates and configure it to apply updates automatically
sudo dnf -y install dnf-automatic
sudo sed -i 's/^upgrade_type = .*/upgrade_type = default/' /etc/dnf/automatic.conf
sudo sed -i 's/^apply_updates = .*/apply_updates = yes/' /etc/dnf/automatic.conf

# Enable and start the dnf-automatic timer to run daily
sudo systemctl enable --now dnf-automatic.timer
if sudo systemctl is-active --quiet dnf-automatic.timer; then
  echo "dnf-automatic timer is enabled and running"
else
  echo "Failed to start dnf-automatic timer"
  exit 1
fi