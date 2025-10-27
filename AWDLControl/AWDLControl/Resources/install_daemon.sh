#!/bin/bash

# AWDLControl Daemon Installer
# This script installs the AWDL monitoring daemon from the app bundle
# Run with: sudo /Applications/AWDLControl.app/Contents/Resources/install_daemon.sh

set -e

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║         AWDLControl Daemon Installation                 ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "❌ This script must be run with sudo"
    echo ""
    echo "Usage:"
    echo "  sudo $0"
    echo ""
    exit 1
fi

# Get the directory where this script is located (app Resources)
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
APP_BUNDLE="$(dirname "$(dirname "$(dirname "$SCRIPT_DIR")")")"

echo "📦 Installing from: $APP_BUNDLE"
echo ""

# Paths
DAEMON_SOURCE="$SCRIPT_DIR/awdl_monitor_daemon"
PLIST_SOURCE="$SCRIPT_DIR/com.awdlcontrol.daemon.plist"
DAEMON_DEST="/usr/local/bin/awdl_monitor_daemon"
PLIST_DEST="/Library/LaunchDaemons/com.awdlcontrol.daemon.plist"

# Check if source files exist
if [ ! -f "$DAEMON_SOURCE" ]; then
    echo "❌ Error: Daemon binary not found at:"
    echo "   $DAEMON_SOURCE"
    echo ""
    echo "The app bundle may be corrupted. Please re-download AWDLControl."
    exit 1
fi

if [ ! -f "$PLIST_SOURCE" ]; then
    echo "❌ Error: Daemon plist not found at:"
    echo "   $PLIST_SOURCE"
    echo ""
    echo "The app bundle may be corrupted. Please re-download AWDLControl."
    exit 1
fi

echo "✅ Source files found"
echo ""

# Step 1: Unload existing daemon if running
echo "Step 1/4: Checking for existing daemon..."
if launchctl list | grep -q com.awdlcontrol.daemon; then
    echo "   Unloading existing daemon..."
    launchctl bootout system/com.awdlcontrol.daemon 2>/dev/null || true
    echo "   ✅ Existing daemon unloaded"
else
    echo "   ℹ️  No existing daemon found"
fi
echo ""

# Step 2: Install daemon binary
echo "Step 2/4: Installing daemon binary..."
mkdir -p /usr/local/bin
cp "$DAEMON_SOURCE" "$DAEMON_DEST"
chown root:wheel "$DAEMON_DEST"
chmod 4755 "$DAEMON_DEST"  # setuid root for network control

if [ -f "$DAEMON_DEST" ]; then
    echo "   ✅ Daemon installed to: $DAEMON_DEST"
    ls -lh "$DAEMON_DEST"
else
    echo "   ❌ Failed to install daemon"
    exit 1
fi
echo ""

# Step 3: Install plist
echo "Step 3/4: Installing LaunchDaemon plist..."
cp "$PLIST_SOURCE" "$PLIST_DEST"
chown root:wheel "$PLIST_DEST"
chmod 644 "$PLIST_DEST"

if [ -f "$PLIST_DEST" ]; then
    echo "   ✅ Plist installed to: $PLIST_DEST"
else
    echo "   ❌ Failed to install plist"
    exit 1
fi
echo ""

# Step 4: Load and start daemon
echo "Step 4/4: Loading daemon..."
launchctl bootstrap system "$PLIST_DEST"

# Wait a moment for daemon to start
sleep 2

# Verify daemon is running
if launchctl list | grep -q com.awdlcontrol.daemon; then
    PID=$(launchctl list | grep com.awdlcontrol.daemon | awk '{print $1}')
    if [ "$PID" != "-" ] && [ "$PID" != "0" ]; then
        echo "   ✅ Daemon is running (PID: $PID)"
    else
        echo "   ⚠️  Daemon loaded but not running (PID: $PID)"
        echo ""
        echo "Checking logs..."
        tail -10 /var/log/awdl_monitor_daemon.log 2>/dev/null || echo "No logs yet"
        exit 1
    fi
else
    echo "   ❌ Failed to load daemon"
    exit 1
fi
echo ""

# Verify AWDL is down
AWDL_STATUS=$(ifconfig awdl0 2>/dev/null | grep flags || echo "")
if [ -n "$AWDL_STATUS" ]; then
    if echo "$AWDL_STATUS" | grep -q "UP"; then
        echo "⚠️  Warning: AWDL is still UP"
        echo "   $AWDL_STATUS"
    else
        echo "✅ AWDL is DOWN - daemon is working!"
        echo "   $AWDL_STATUS"
    fi
fi
echo ""

echo "╔══════════════════════════════════════════════════════════╗"
echo "║              Installation Complete! ✅                   ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""
echo "The AWDL monitoring daemon is now installed and running."
echo ""
echo "What was installed:"
echo "  • Daemon: $DAEMON_DEST"
echo "  • Plist:  $PLIST_DEST"
echo ""
echo "Next steps:"
echo "  1. Return to AWDLControl"
echo "  2. Toggle monitoring from the menu bar"
echo "  3. No more password prompts needed!"
echo ""
echo "How it works:"
echo "  • Response time: <1ms when AWDL comes up"
echo "  • CPU usage: 0% when idle (event-driven)"
echo "  • Based on awdlkiller technology"
echo ""
