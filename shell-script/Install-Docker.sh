#INSTALL THE DOCKER AND YOU CAN USE DOCKER WITHOUT SUDO 
#!/bin/bash
set -e

# Update system
sudo apt-get update -y
sudo apt-get upgrade -y

# Install dependencies
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

# Add Docker’s official GPG key
sudo install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
sudo chmod a+r /etc/apt/keyrings/docker.gpg

# Set up Docker repository
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
  | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index
sudo apt-get update -y

# Install Docker Engine, CLI, containerd
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Enable & start Docker service
sudo systemctl enable docker
sudo systemctl start docker

# Add current user to docker group
sudo groupadd -f docker
sudo usermod -aG docker $USER
exit

echo "========================================================"
echo " Docker installation completed successfully! 🎉 "
echo " Logout and login again (or run 'newgrp docker') to use"
echo " Docker without sudo."
echo "========================================================"
