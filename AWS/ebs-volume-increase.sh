#!/bin/bash

lsblk_output=$(sudo lsblk)

if [[ $lsblk_output =~ "nvme1n1" || $lsblk_output =~ "nvme0n1" ]]; then
    # Run commands for nvme1n1 or nvme0n1
    echo "Running commands for nvme1n1 or nvme0n1"
    # Add your commands here
    sudo growpart /dev/nvme0n1 1
    df -hT
    sudo xfs_growfs -d /
    sudo resize2fs /dev/nvme0n1p1
    df -h

elif [[ $lsblk_output =~ "xvda" || $lsblk_output =~ "xvdf" ]]; then
    # Run commands for xvda or xvdf
    echo "Running commands for xvda or xvdf"
    # Add your commands here
    sudo growpart /dev/xvda 1
    sudo xfs_growfs -d /
    sudo resize2fs /dev/xvda1
    df -h

else
    # Handle the case where none of the expected strings are found
    echo "No matching devices found"
fi
