#!/bin/bash

# Uninstallation script for AWDL Monitor Daemon

set -e

DAEMON_NAME="awdl_monitor_daemon"
DAEMON_LABEL="com.awdlcontrol.daemon"
DAEMON_PLIST="$DAEMON_LABEL.plist"
DAEMON_DEST="/usr/local/bin/$DAEMON_NAME"
PLIST_DEST="/Library/LaunchDaemons/$DAEMON_PLIST"

echo "============================================"
echo "  AWDL Monitor Daemon Uninstallation"
echo "============================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo"
    echo "Usage: sudo ./uninstall_daemon.sh"
    exit 1
fi

echo "Stopping daemon if running..."
echo "---------------------------------------"

# Stop daemon using modern launchctl command
launchctl bootout system/"$DAEMON_LABEL" 2>/dev/null || true

# Verify daemon stopped
if pgrep -x "$DAEMON_NAME" > /dev/null; then
    echo "Warning: Daemon process still running, killing..."
    pkill -x "$DAEMON_NAME" 2>/dev/null || true
fi

echo "Done"

echo ""
echo "Removing files..."
echo "---------------------------------------"

# Remove daemon binary
if [ -f "$DAEMON_DEST" ]; then
    rm -f "$DAEMON_DEST"
    echo "✅ Removed $DAEMON_DEST"
else
    echo "Daemon binary not found at $DAEMON_DEST"
fi

# Remove plist
if [ -f "$PLIST_DEST" ]; then
    rm -f "$PLIST_DEST"
    echo "✅ Removed $PLIST_DEST"
else
    echo "Plist not found at $PLIST_DEST"
fi

# Remove log file if it exists
if [ -f "/var/log/awdl_monitor_daemon.log" ]; then
    rm -f "/var/log/awdl_monitor_daemon.log"
    echo "✅ Removed log file"
fi

echo ""
echo "============================================"
echo "  Uninstallation Complete!"
echo "============================================"
echo ""
echo "The AWDL Monitor Daemon has been removed."
echo ""
