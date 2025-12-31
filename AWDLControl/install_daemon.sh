#!/bin/bash

# Installation script for AWDL Monitor Daemon
# Works in two modes:
# 1. From app bundle: Uses pre-built daemon binary
# 2. From source: Builds daemon from source

set -e

DAEMON_NAME="awdl_monitor_daemon"
DAEMON_LABEL="com.awdlcontrol.daemon"
DAEMON_PLIST="$DAEMON_LABEL.plist"
DAEMON_DEST="/usr/local/bin/$DAEMON_NAME"
PLIST_DEST="/Library/LaunchDaemons/$DAEMON_PLIST"

# Get the directory where this script is located
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "============================================"
echo "  AWDL Monitor Daemon Installation"
echo "============================================"
echo ""
echo "Script location: $SCRIPT_DIR"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo/admin privileges"
    exit 1
fi

echo "Step 1: Stopping existing daemon if running..."
echo "---------------------------------------"
launchctl bootout system/"$DAEMON_LABEL" 2>/dev/null || true
echo "Done"
echo ""

# Determine installation mode
if [ -f "$SCRIPT_DIR/$DAEMON_NAME" ]; then
    # App bundle mode - pre-built binary exists
    echo "Step 2: Using pre-built daemon binary..."
    echo "---------------------------------------"
    DAEMON_SOURCE="$SCRIPT_DIR/$DAEMON_NAME"
    PLIST_SOURCE="$SCRIPT_DIR/$DAEMON_PLIST"
    echo "Found pre-built binary at $DAEMON_SOURCE"

elif [ -d "$SCRIPT_DIR/AWDLMonitorDaemon" ]; then
    # Source mode - build from source
    echo "Step 2: Building daemon from source..."
    echo "---------------------------------------"
    cd "$SCRIPT_DIR/AWDLMonitorDaemon"

    if [ -f "Makefile" ]; then
        make clean 2>/dev/null || true
        make

        if [ ! -f "$DAEMON_NAME" ]; then
            echo "Error: Build failed - $DAEMON_NAME not found"
            exit 1
        fi
        echo "Build successful"
        DAEMON_SOURCE="$SCRIPT_DIR/AWDLMonitorDaemon/$DAEMON_NAME"
        PLIST_SOURCE="$SCRIPT_DIR/AWDLMonitorDaemon/$DAEMON_PLIST"
    else
        echo "Error: Makefile not found"
        exit 1
    fi
else
    echo "Error: Could not find daemon binary or source"
    echo "Expected either:"
    echo "  - Pre-built binary at: $SCRIPT_DIR/$DAEMON_NAME"
    echo "  - Source directory at: $SCRIPT_DIR/AWDLMonitorDaemon"
    exit 1
fi

echo ""
echo "Step 3: Installing daemon binary..."
echo "---------------------------------------"

# Create /usr/local/bin if it doesn't exist
mkdir -p /usr/local/bin

# Install daemon with setuid root permissions
install -m 4755 -o root -g wheel "$DAEMON_SOURCE" "$DAEMON_DEST"

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
echo "Step 4: Installing LaunchDaemon plist..."
echo "---------------------------------------"

# Install plist
if [ ! -f "$PLIST_SOURCE" ]; then
    echo "Error: $DAEMON_PLIST not found at $PLIST_SOURCE"
    exit 1
fi

cp "$PLIST_SOURCE" "$PLIST_DEST"
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
