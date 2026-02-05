#!/bin/bash
#
#  install.sh
#  Ping Warden Installer
#
#  Removes quarantine attributes and installs to Applications folder.
#
#  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
#  Licensed under the MIT License.
#

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

APP_NAME="Ping Warden.app"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${SCRIPT_DIR}/${APP_NAME}"
INSTALL_PATH="/Applications/${APP_NAME}"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Ping Warden Installer"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if app exists in current directory
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: ${APP_NAME} not found in current directory${NC}"
    echo "Please run this script from the folder containing ${APP_NAME}"
    exit 1
fi

# Check if already installed
if [ -d "$INSTALL_PATH" ]; then
    echo -e "${YELLOW}Ping Warden is already installed.${NC}"
    read -p "Do you want to replace it? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled."
        exit 0
    fi
    
    # Kill running app if exists
    echo "Stopping Ping Warden if running..."
    killall "Ping Warden" 2>/dev/null || true
    
    # Remove old version
    echo "Removing old version..."
    rm -rf "$INSTALL_PATH"
fi

# Remove quarantine attribute (this is what fixes the Gatekeeper issue)
echo "Removing quarantine attributes..."
xattr -cr "$APP_PATH"

# Copy to Applications
echo "Installing to /Applications..."
cp -R "$APP_PATH" "$INSTALL_PATH"

# Remove quarantine from installed copy too (just to be safe)
xattr -cr "$INSTALL_PATH"

echo ""
echo -e "${GREEN}✓ Installation complete!${NC}"
echo ""
echo "You can now launch Ping Warden from:"
echo "  • Applications folder"
echo "  • Spotlight (⌘ + Space, then type 'Ping Warden')"
echo ""
echo "First-time setup will ask for approval in System Settings → Login Items"
echo ""

# Ask if user wants to launch now
read -p "Launch Ping Warden now? (y/n) " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Launching..."
    open "$INSTALL_PATH"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
