#!/bin/bash

# Installation script for AWDL Monitor Daemon
# This installs the C daemon that provides instant AWDL monitoring
# using AF_ROUTE sockets (exactly like awdlkiller)

set -e

DAEMON_NAME="awdl_monitor_daemon"
DAEMON_LABEL="com.awdlcontrol.daemon"
DAEMON_PLIST="$DAEMON_LABEL.plist"
DAEMON_DEST="/usr/local/bin/$DAEMON_NAME"
PLIST_DEST="/Library/LaunchDaemons/$DAEMON_PLIST"

echo "============================================"
echo "  AWDL Monitor Daemon Installation"
echo "============================================"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script must be run with sudo"
    echo "Usage: sudo ./install_daemon.sh"
    exit 1
fi

# Navigate to daemon directory
cd "$(dirname "$0")/AWDLMonitorDaemon" || {
    echo "Error: AWDLMonitorDaemon directory not found"
    exit 1
}

echo "Step 1: Building daemon from source..."
echo "---------------------------------------"

# Build the daemon
if [ -f "Makefile" ]; then
    make clean
    make

    if [ ! -f "$DAEMON_NAME" ]; then
        echo "Error: Build failed - $DAEMON_NAME not found"
        exit 1
    fi
    echo "✅ Build successful"
else
    echo "Error: Makefile not found"
    exit 1
fi

echo ""
echo "Step 2: Installing daemon binary..."
echo "---------------------------------------"

# Create /usr/local/bin if it doesn't exist
mkdir -p /usr/local/bin

# Install daemon with setuid root permissions
install -m 4755 -o root -g wheel "$DAEMON_NAME" "$DAEMON_DEST"

if [ ! -f "$DAEMON_DEST" ]; then
    echo "Error: Failed to install daemon to $DAEMON_DEST"
    exit 1
fi

# Verify setuid bit
if [ ! -u "$DAEMON_DEST" ]; then
    echo "Warning: setuid bit not set, setting it now..."
    chmod u+s "$DAEMON_DEST"
fi

echo "✅ Daemon installed to $DAEMON_DEST"
ls -la "$DAEMON_DEST"

echo ""
echo "Step 3: Installing LaunchDaemon plist..."
echo "---------------------------------------"

# Install plist
if [ ! -f "$DAEMON_PLIST" ]; then
    echo "Error: $DAEMON_PLIST not found"
    exit 1
fi

cp "$DAEMON_PLIST" "$PLIST_DEST"
chown root:wheel "$PLIST_DEST"
chmod 644 "$PLIST_DEST"

echo "✅ Plist installed to $PLIST_DEST"

echo ""
echo "============================================"
echo "  Installation Complete!"
echo "============================================"
echo ""
echo "The AWDL Monitor Daemon has been installed successfully."
echo ""
echo "What was installed:"
echo "  • Daemon binary: $DAEMON_DEST (setuid root)"
echo "  • LaunchDaemon plist: $PLIST_DEST"
echo ""
echo "How it works:"
echo "  • The daemon uses AF_ROUTE sockets for instant notifications"
echo "  • Response time: <1ms when AWDL comes up"
echo "  • CPU usage: 0% when idle (event-driven)"
echo "  • Same technology as awdlkiller"
echo ""
echo "Usage:"
echo "  • Use the AWDLControl app to start/stop monitoring"
echo "  • Toggle the control in Control Center or menu bar"
echo ""
echo "Manual control (if needed):"
echo "  • Start: sudo launchctl load $PLIST_DEST"
echo "  • Stop:  sudo launchctl unload $PLIST_DEST"
echo "  • Check: sudo launchctl list | grep $DAEMON_LABEL"
echo ""
echo "Logs:"
echo "  • Daemon logs to system log (syslog)"
echo "  • View: log show --predicate 'process == \"$DAEMON_NAME\"' --last 1h"
echo "  • Or: sudo tail -f /var/log/awdl_monitor_daemon.log"
echo ""
echo "To uninstall:"
echo "  • Run: sudo ./uninstall_daemon.sh"
echo ""
