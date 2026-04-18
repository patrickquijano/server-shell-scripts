#!/bin/bash

# Update and upgrade the system
sudo dnf -y update
sudo dnf -y upgrade

# Install Docker CE and related packages
sudo dnf -y install dnf-plugins-core
sudo dnf config-manager --add-repo https://download.docker.com/linux/rhel/docker-ce.repo
sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin container-selinux

# Add the azureuser to the docker group to run Docker without sudo
if ! getent group docker; then
  sudo groupadd docker
fi

# Add the current user to the docker group
sudo usermod -aG docker $USER

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

# Enable and start Docker and containerd services
sudo systemctl enable --now docker
sudo systemctl enable --now containerd

# Apply the new group membership without logging out
newgrp docker

# Test Docker installation by running the hello-world container
docker run --rm hello-world || echo "Docker hello-world test failed"