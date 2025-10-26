#!/bin/bash

# Installation script for AWDLControl privileged helper tool
# This script must be run with sudo

set -e

HELPER_NAME="com.awdlcontrol.helper"
HELPER_DEST="/Library/PrivilegedHelperTools/$HELPER_NAME"
BUILD_DIR="./build/Release"
HELPER_SOURCE="$BUILD_DIR/AWDLControlHelper"

echo "Installing AWDLControl privileged helper tool..."

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo"
    exit 1
fi

# Check if helper binary exists
if [ ! -f "$HELPER_SOURCE" ]; then
    echo "Error: Helper binary not found at $HELPER_SOURCE"
    echo "Please build the project first using Xcode or xcodebuild"
    exit 1
fi

# Create destination directory if it doesn't exist
mkdir -p /Library/PrivilegedHelperTools

# Copy helper tool
echo "Copying helper tool to $HELPER_DEST..."
cp "$HELPER_SOURCE" "$HELPER_DEST"

# Set ownership and permissions
echo "Setting permissions..."
chown root:wheel "$HELPER_DEST"
chmod 4755 "$HELPER_DEST"  # setuid root

echo "Installation complete!"
echo ""
echo "The helper tool has been installed at: $HELPER_DEST"
echo "It will allow AWDLControl to manage the AWDL interface without repeated admin prompts."
