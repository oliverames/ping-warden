#!/bin/bash

# Uninstallation script for AWDLControl privileged helper tool
# This script must be run with sudo

set -e

HELPER_NAME="com.awdlcontrol.helper"
HELPER_DEST="/Library/PrivilegedHelperTools/$HELPER_NAME"

echo "Uninstalling AWDLControl privileged helper tool..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo"
    exit 1
fi

# Remove helper tool if it exists
if [ -f "$HELPER_DEST" ]; then
    echo "Removing helper tool from $HELPER_DEST..."
    rm "$HELPER_DEST"
    echo "Helper tool removed successfully!"
else
    echo "Helper tool not found at $HELPER_DEST"
fi

echo "Uninstallation complete!"
