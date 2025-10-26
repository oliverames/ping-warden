#!/bin/bash

# Uninstallation script for AWDLControl LaunchAgent

set -e

AGENT_NAME="com.awdlcontrol.app"
AGENT_DEST="$HOME/Library/LaunchAgents/$AGENT_NAME.plist"

echo "Uninstalling AWDLControl LaunchAgent..."

# Unload the agent if it's loaded
if launchctl list | grep -q "$AGENT_NAME"; then
    echo "Unloading LaunchAgent..."
    launchctl unload "$AGENT_DEST" 2>/dev/null || true
fi

# Remove plist
if [ -f "$AGENT_DEST" ]; then
    echo "Removing LaunchAgent from $AGENT_DEST..."
    rm "$AGENT_DEST"
    echo "LaunchAgent removed successfully!"
else
    echo "LaunchAgent not found at $AGENT_DEST"
fi

echo "Uninstallation complete!"
