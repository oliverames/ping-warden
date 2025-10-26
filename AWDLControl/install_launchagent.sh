#!/bin/bash

# Installation script for AWDLControl LaunchAgent
# This keeps the app running in the background to maintain monitoring

set -e

AGENT_NAME="com.awdlcontrol.app"
AGENT_PLIST="$AGENT_NAME.plist"
AGENT_DEST="$HOME/Library/LaunchAgents/$AGENT_PLIST"

echo "Installing AWDLControl LaunchAgent..."

# Check if plist exists
if [ ! -f "$AGENT_PLIST" ]; then
    echo "Error: $AGENT_PLIST not found in current directory"
    exit 1
fi

# Create LaunchAgents directory if it doesn't exist
mkdir -p "$HOME/Library/LaunchAgents"

# Copy plist
echo "Copying LaunchAgent to $AGENT_DEST..."
cp "$AGENT_PLIST" "$AGENT_DEST"

# Load the agent
echo "Loading LaunchAgent..."
launchctl load "$AGENT_DEST"

echo "Installation complete!"
echo ""
echo "The AWDLControl app will now:"
echo "  - Start automatically at login"
echo "  - Keep running in the background"
echo "  - Maintain AWDL monitoring even when you're not using the control"
echo ""
echo "To uninstall, run: ./uninstall_launchagent.sh"
