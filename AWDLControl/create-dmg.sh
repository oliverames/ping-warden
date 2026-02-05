#!/bin/bash
#
#  create-dmg.sh
#  Creates a distributable DMG with installation instructions
#
#  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
#  Licensed under the MIT License.
#

set -e

# Configuration
APP_NAME="Ping Warden"
VERSION="${1:-2.0.1}"
DMG_NAME="PingWarden-${VERSION}"
BUILD_DIR="build"
DMG_TEMP="dmg_temp"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Creating DMG for ${APP_NAME} v${VERSION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check if app exists
if [ ! -d "${BUILD_DIR}/${APP_NAME}.app" ]; then
    echo "Error: ${BUILD_DIR}/${APP_NAME}.app not found"
    echo "Please build the app first using Xcode"
    exit 1
fi

# Clean up previous temp directory
rm -rf "$DMG_TEMP"
mkdir -p "$DMG_TEMP"

# Copy app
echo "Copying app bundle..."
cp -R "${BUILD_DIR}/${APP_NAME}.app" "$DMG_TEMP/"

# Copy installer script
echo "Copying installer script..."
cp install.sh "$DMG_TEMP/"
chmod +x "$DMG_TEMP/install.sh"

# Create a symlink to Applications
echo "Creating Applications symlink..."
ln -s /Applications "$DMG_TEMP/Applications"

# Create README for DMG
cat > "$DMG_TEMP/README.txt" << 'EOF'
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  PING WARDEN - Installation Instructions
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

⚠️  IMPORTANT: macOS Security Notice
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

macOS may show a warning that "Ping Warden can't be opened" 
or "cannot be verified as free of malware."

This is normal for apps not notarized by Apple. Choose one 
of the installation methods below:


📦 METHOD 1: Automated Installer (Easiest)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Double-click "install.sh"
2. If Terminal opens, click "OK"
3. Follow the prompts

OR open Terminal in this folder and run:
   ./install.sh


🖱️  METHOD 2: Manual Installation
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

1. Drag "Ping Warden.app" to the Applications folder
2. Right-click (or Control-click) on "Ping Warden.app"
3. Select "Open" from the menu
4. Click "Open" in the dialog

This only needs to be done once!


💻 METHOD 3: Terminal Command
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Drag "Ping Warden.app" to Applications, then run:

   xattr -cr "/Applications/Ping Warden.app"
   open "/Applications/Ping Warden.app"


🎮 What does Ping Warden do?
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Eliminates 100-300ms network latency spikes caused by AWDL
(Apple Wireless Direct Link). Perfect for:

  • Gaming (especially competitive online games)
  • Video calls (Zoom, Teams, Discord)
  • Live streaming
  • Remote desktop


✨ Features
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ⚡ <1ms response time
  🎯 0% CPU when idle
  🔒 No password prompts
  🎮 Game Mode auto-detection
  🚀 Launch at login support


📝 First Launch
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

After installation, the first launch will ask you to:

1. Approve the helper in System Settings → Login Items
2. This is a one-time approval (no password needed)
3. The helper only runs while the app is open


💬 Support
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

For issues or questions, visit:
https://github.com/yourusername/ping-warden

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
EOF

# Create DMG
echo "Creating DMG..."
rm -f "${DMG_NAME}.dmg"

# Create DMG with nice settings
hdiutil create -volname "${APP_NAME}" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    -imagekey zlib-level=9 \
    "${DMG_NAME}.dmg"

# Clean up
echo "Cleaning up..."
rm -rf "$DMG_TEMP"

# Calculate DMG size
DMG_SIZE=$(du -h "${DMG_NAME}.dmg" | cut -f1)

echo ""
echo -e "${GREEN}✓ DMG created successfully!${NC}"
echo ""
echo "  File: ${DMG_NAME}.dmg"
echo "  Size: ${DMG_SIZE}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Test the DMG by mounting it"
echo "  2. Verify all installation methods work"
echo "  3. Upload to GitHub releases"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
