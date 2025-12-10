#!/bin/bash

# Installation script for AWDL Monitor Daemon (App Bundle Version)
# Installs the pre-built C daemon that provides instant AWDL monitoring
# using AF_ROUTE sockets (exactly like awdlkiller)

set -e

DAEMON_NAME="awdl_monitor_daemon"
DAEMON_LABEL="com.awdlcontrol.daemon"
DAEMON_PLIST="$DAEMON_LABEL.plist"
DAEMON_DEST="/usr/local/bin/$DAEMON_NAME"
PLIST_DEST="/Library/LaunchDaemons/$DAEMON_PLIST"

# Get the directory where this script is located (app bundle Resources)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo "  AWDL Monitor Daemon Installation"
echo "============================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo"
    echo "Usage: sudo '$0'"
    exit 1
fi

# Verify pre-built daemon exists in bundle
if [ ! -f "$SCRIPT_DIR/$DAEMON_NAME" ]; then
    echo "Error: Pre-built daemon not found at $SCRIPT_DIR/$DAEMON_NAME"
    echo "The app bundle may be corrupted. Please reinstall AWDLControl."
    exit 1
fi

# Verify plist exists in bundle
if [ ! -f "$SCRIPT_DIR/$DAEMON_PLIST" ]; then
    echo "Error: Daemon plist not found at $SCRIPT_DIR/$DAEMON_PLIST"
    echo "The app bundle may be corrupted. Please reinstall AWDLControl."
    exit 1
fi

echo "Step 1: Stopping existing daemon if running..."
echo "---------------------------------------"
launchctl bootout system/"$DAEMON_LABEL" 2>/dev/null || true
echo "Done"

echo ""
echo "Step 2: Installing daemon binary..."
echo "---------------------------------------"

# Create /usr/local/bin if it doesn't exist
mkdir -p /usr/local/bin

# Install daemon with setuid root permissions
install -m 4755 -o root -g wheel "$SCRIPT_DIR/$DAEMON_NAME" "$DAEMON_DEST"

if [ ! -f "$DAEMON_DEST" ]; then
    echo "Error: Failed to install daemon to $DAEMON_DEST"
    exit 1
fi

# Verify setuid bit
if [ ! -u "$DAEMON_DEST" ]; then
    chmod u+s "$DAEMON_DEST"
fi

echo "Installed to $DAEMON_DEST"
ls -la "$DAEMON_DEST"

echo ""
echo "Step 3: Installing LaunchDaemon plist..."
echo "---------------------------------------"

cp "$SCRIPT_DIR/$DAEMON_PLIST" "$PLIST_DEST"
chown root:wheel "$PLIST_DEST"
chmod 644 "$PLIST_DEST"

echo "Installed to $PLIST_DEST"

echo ""
echo "============================================"
echo "  Installation Complete!"
echo "============================================"
echo ""
echo "The AWDL Monitor Daemon has been installed."
echo ""
echo "What was installed:"
echo "  - Daemon binary: $DAEMON_DEST (setuid root)"
echo "  - LaunchDaemon plist: $PLIST_DEST"
echo ""
echo "How it works:"
echo "  - AF_ROUTE sockets for instant kernel notifications"
echo "  - Response time: <1ms"
echo "  - CPU usage: 0% when idle"
echo ""
echo "Return to AWDLControl.app to enable monitoring."
echo ""
