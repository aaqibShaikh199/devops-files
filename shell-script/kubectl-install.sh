#!/bin/bash

# Download kubectl binary and its SHA-256 checksum
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl.sha256"

# Verify SHA-256 checksum
echo "$(cat kubectl.sha256)  kubectl" | sha256sum --check

# Install kubectl binary to /usr/local/bin/
sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl

# Check kubectl version
kubectl version --client

# Update apt package index
sudo apt-get update

# Install prerequisites
sudo apt-get install -y apt-transport-https ca-certificates curl

# Import Kubernetes apt repository key
curl -fsSL https://pkgs.k8s.io/core:/stable:/v1.30/deb/Release.key | sudo gpg --dearmor -o /etc/apt/trusted.gpg.d/kubernetes-archive-keyring.gpg

# Add Kubernetes apt repository
echo 'deb [signed-by=/etc/apt/trusted.gpg.d/kubernetes-archive-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v1.30/deb/ /' | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update apt package index again
sudo apt-get update

# Install kubectl package
sudo apt-get install -y kubectl
