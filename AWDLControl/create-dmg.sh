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

# Create a symlink to Applications
echo "Creating Applications symlink..."
ln -s /Applications "$DMG_TEMP/Applications"

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
