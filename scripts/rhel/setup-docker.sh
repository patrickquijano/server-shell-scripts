#!/bin/bash

# Update and upgrade the system
sudo dnf -y update
sudo dnf -y upgrade

# Install Docker CE and dependencies
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable and start the Docker service
sudo systemctl enable --now docker

# Add the azureuser to the docker group to run Docker without sudo
if ! getent group docker; then
  sudo groupadd docker
fi

# Add the current user to the docker group
sudo usermod -aG docker $USER

# Apply the new group membership without logging out
newgrp docker

# Install SELinux policy for Docker
sudo dnf -y install container-selinux

# Configure Docker daemon to use systemd as the cgroup driver and set log options
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
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

# Reload systemd and restart Docker to apply the new configuration
sudo systemctl daemon-reload
sudo systemctl restart docker

# Test Docker installation by running the hello-world container
docker run --rm hello-world || echo "Docker hello-world test failed"