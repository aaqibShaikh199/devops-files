#THIS SCRIPT INSTALL THE MINIKUBE + KUBECTL AFTER THAT IT'S CREATE A ALILAS FOR KUBECTL TO K 
#!/bin/bash

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect OS and architecture
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

# Convert architecture naming
case $ARCH in
    x86_64)
        ARCH="amd64"
        ;;
    arm64|aarch64)
        ARCH="arm64"
        ;;
    *)
        print_error "Unsupported architecture: $ARCH"
        exit 1
        ;;
esac

print_status "Detected OS: $OS, Architecture: $ARCH"

# Installation directory
INSTALL_DIR="$HOME/.local/bin"
mkdir -p "$INSTALL_DIR"

# Add to PATH if not already there
if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
    print_status "Adding $INSTALL_DIR to PATH"
    echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
    export PATH="$INSTALL_DIR:$PATH"
else
    # Ensure PATH is set for current session even if already in config
    export PATH="$INSTALL_DIR:$PATH"
fi

print_status "Installing kubectl..."

# Download kubectl
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
KUBECTL_URL="https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"

print_status "Downloading kubectl ${KUBECTL_VERSION} for ${OS}/${ARCH}..."
curl -LO "$KUBECTL_URL"

# Make executable and move to install directory
chmod +x kubectl
mv kubectl "$INSTALL_DIR/"

print_status "kubectl installed successfully!"

print_status "Installing minikube..."

# Download minikube
MINIKUBE_URL="https://storage.googleapis.com/minikube/releases/latest/minikube-${OS}-${ARCH}"

print_status "Downloading latest minikube for ${OS}/${ARCH}..."
curl -LO "$MINIKUBE_URL"

# Make executable and move to install directory
chmod +x "minikube-${OS}-${ARCH}"
mv "minikube-${OS}-${ARCH}" "$INSTALL_DIR/minikube"

print_status "minikube installed successfully!"

# Create kubectl alias
print_status "Setting up 'k' alias for kubectl..."

# Add alias to shell configuration files
SHELL_CONFIGS=(~/.bashrc ~/.zshrc ~/.profile)

for config in "${SHELL_CONFIGS[@]}"; do
    if [ -f "$config" ]; then
        # Check if alias already exists
        if ! grep -q "alias k=" "$config" 2>/dev/null; then
            echo "" >> "$config"
            echo "# kubectl alias" >> "$config"
            echo "alias k='kubectl'" >> "$config"
            print_status "Added 'k' alias to $config"
        else
            print_warning "Alias 'k' already exists in $config"
        fi
    fi
done

# Set alias for current session
alias k='kubectl'

print_status "Installation completed!"
echo ""
echo "=== Summary ==="
echo "✅ kubectl installed to: $INSTALL_DIR/kubectl"
echo "✅ minikube installed to: $INSTALL_DIR/minikube"
echo "✅ 'k' alias created for kubectl"
echo ""
echo "=== IMPORTANT: Reload your shell environment ==="
echo "Run this command to use kubectl and k alias immediately:"
echo "source ~/.bashrc && export PATH=\"$INSTALL_DIR:\$PATH\""
echo ""
echo "Or simply open a new terminal window."
echo ""
echo "=== Verify Installation ==="
echo "After reloading, test with:"
echo "   kubectl version --client"
echo "   minikube version"
echo "   k version --client  # Test the alias"
echo ""
echo "=== Quick Start ==="
echo "1. Start minikube: minikube start"
echo "2. Test kubectl: k get nodes"

print_status "Happy Kuberneting! 🚀"
exit
