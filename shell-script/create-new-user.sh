#Using this script you can create a NEW ssh user with pass
#!/bin/bash

# Check if script is run with root privileges
if [ "$EUID" -ne 0 ]; then
    echo "Please run this script with sudo or as root"
    exit 1
fi

# Function to validate username
validate_username() {
    if [[ ! $1 =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        return 1
    fi
    return 0
}

# Function to configure SSH files
configure_ssh() {
    local files=(
        "/etc/ssh/ssh_config"
        "/etc/ssh/sshd_config"
        "/etc/ssh/sshd_config.d/60-cloudimg-settings.conf"
    )

    echo "Configuring SSH files..."
    
    # Process each SSH config file
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            echo "Configuring $file..."
            
            # Create backup
            cp "$file" "$file.backup.$(date +%F-%H-%M-%S)"
            
            # Update existing PasswordAuthentication settings
            sed -i 's/^PasswordAuthentication no/PasswordAuthentication yes/' "$file"
            sed -i 's/^#PasswordAuthentication no/PasswordAuthentication yes/' "$file"
            sed -i 's/^#PasswordAuthentication yes/PasswordAuthentication yes/' "$file"
            
            # Add PasswordAuthentication yes if it doesn't exist
            if ! grep -q "^PasswordAuthentication yes" "$file"; then
                echo "PasswordAuthentication yes" >> "$file"
                echo "Added PasswordAuthentication yes to $file"
            fi
            
            echo "Successfully configured $file"
        else
            echo "Warning: $file does not exist"
        fi
    done

    # Restart SSH service
    echo "Restarting SSH service..."
    systemctl restart sshd
    
    if ! systemctl is-active --quiet sshd; then
        echo "Warning: SSH service failed to restart"
        return 1
    fi
    
    echo "SSH configuration completed successfully"
    return 0
}

# Get username
while true; do
    read -p "Enter username: " username
    if validate_username "$username"; then
        if id "$username" &>/dev/null; then
            echo "Error: User already exists"
        else
            break
        fi
    else
        echo "Error: Invalid username. Username must start with a letter or underscore and can only contain lowercase letters, numbers, underscores, and hyphens"
    fi
done

# Get password
while true; do
    read -s -p "Enter password: " password
    echo
    read -s -p "Confirm password: " password2
    echo
    
    if [ "$password" = "$password2" ]; then
        break
    else
        echo "Passwords do not match. Please try again."
    fi
done

# Create user
echo "Creating user $username..."
adduser "$username"
echo "$username:$password" | chpasswd

# Add user to sudo group
usermod -aG sudo "$username"

# Configure sudo access
echo "$username ALL=(ALL:ALL) ALL" >> /etc/sudoers

# Configure SSH
if ! configure_ssh; then
    echo "Warning: SSH configuration encountered some issues"
fi

# Test SSH configuration
echo "Testing SSH configuration..."
sshd -t
if [ $? -eq 0 ]; then
    echo "SSH configuration syntax is valid"
else
    echo "Warning: SSH configuration syntax has errors"
fi

echo "==============================================="
echo "Setup completed successfully!"
echo "User '$username' has been created with sudo privileges"
echo ""
echo "SSH Configuration Status:"
echo "- Modified /etc/ssh/ssh_config"
echo "- Modified /etc/ssh/sshd_config"
echo "- Modified /etc/ssh/sshd_config.d/60-cloudimg-settings.conf"
echo ""
echo "You can now connect using:"
echo "ssh $username@$SERVER_IP"
echo "==============================================="
