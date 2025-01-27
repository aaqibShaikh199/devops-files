#Using this script you can create a NEW ssh user with pass
#!/bin/bash

# Check if the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root!"
    exit 1
fi

# Prompt for the new username
read -p "Enter the username for the new user: " USERNAME

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

# Create the new user
useradd -m -s /bin/bash "$USERNAME"

# Set the password for the new user
echo "$USERNAME:$PASSWORD" | chpasswd

# Grant the user root privileges by adding them to the 'sudo' group
usermod -aG sudo "$USERNAME"

# Add NOPASSWD option to allow the user to run sudo commands without entering a password
echo "$USERNAME ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/$USERNAME

# Set permissions for the sudoers file
chmod 0440 /etc/sudoers.d/$USERNAME

# Confirm the creation of the user
echo "User '$USERNAME' created with root-like privileges."

