#!/bin/bash

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root!"
    exit 1
fi

# Prompt for the new username
read -p "Enter the username for the new user: " USERNAME

# Validate the username: ensure it's not empty and doesn't contain invalid characters
if [[ -z "$USERNAME" || "$USERNAME" =~ [^a-zA-Z0-9_-] ]]; then
    echo "Invalid username. Use only letters, numbers, underscores, or hyphens."
    exit 1
fi

# Check if the username already exists
if id "$USERNAME" &>/dev/null; then
    echo "The user '$USERNAME' already exists!"
    exit 1
fi

# Prompt for the password
read -s -p "Enter the password for the new user: " PASSWORD
echo
read -s -p "Confirm the password: " PASSWORD_CONFIRM
echo

# Check if passwords match
if [ "$PASSWORD" != "$PASSWORD_CONFIRM" ]; then
    echo "Passwords do not match!"
    exit 1
fi

# Create the new user with a home directory
useradd -m -s /bin/bash "$USERNAME" 2>/dev/null
if [ $? -ne 0 ]; then
    echo "Failed to create the user '$USERNAME'. Please check the system logs for details."
    exit 1
fi

# Set the password for the new user
echo "$USERNAME:$PASSWORD" | chpasswd
if [ $? -ne 0 ]; then
    echo "Failed to set the password for '$USERNAME'."
    userdel -r "$USERNAME"
    exit 1
fi

# Grant the user root privileges by adding them to the 'sudo' group
usermod -aG sudo "$USERNAME"
if [ $? -ne 0 ]; then
    echo "Failed to add '$USERNAME' to the sudo group."
    userdel -r "$USERNAME"
    exit 1
fi

# Add NOPASSWD option to allow the user to run sudo commands without entering a password
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/$USERNAME"
chmod 0440 "/etc/sudoers.d/$USERNAME"
if [ $? -ne 0 ]; then
    echo "Failed to configure sudoers for '$USERNAME'."
    userdel -r "$USERNAME"
    exit 1
fi

# Confirm the creation of the user
echo "User '$USERNAME' created with root-like privileges."
