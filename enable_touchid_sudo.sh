#!/bin/bash

# This script enables Touch ID for sudo on macOS by adding the required line to /etc/pam.d/sudo if not already present.

# Check if running as root (should not be, but will need sudo for editing the file)
if [ "$(id -u)" -eq 0 ]; then
  echo "This script should not be run as root. Please run without sudo."
  exit 1
fi

# Check if Touch ID is already enabled in /etc/pam.d/sudo
if grep -q "^auth sufficient pam_tid.so" /etc/pam.d/sudo; then
    echo "Touch ID for sudo is already enabled in /etc/pam.d/sudo."
else
    echo "Enabling Touch ID for sudo by adding 'auth sufficient pam_tid.so' to /etc/pam.d/sudo."
    sudo sed -i '' '1s;^;auth sufficient pam_tid.so\n;' /etc/pam.d/sudo
    if grep -q "^auth sufficient pam_tid.so" /etc/pam.d/sudo; then
        echo "Touch ID for sudo has been enabled."
    else
        echo "Failed to enable Touch ID for sudo. Please check permissions."
    fi
fi 

