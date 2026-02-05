#!/bin/bash
#
#  notarize.sh
#  Notarize Ping Warden for distribution
#
#  Usage: ./notarize.sh [version]
#  Example: ./notarize.sh 2.0.1
#
#  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
#  Licensed under the MIT License.
#

set -e

# Configuration
APP_NAME="Ping Warden"
VERSION="${1:-2.0.1}"
BUNDLE_ID="com.amesvt.pingwarden"
KEYCHAIN_PROFILE="notarytool-profile"  # Must match setup in NOTARIZATION_GUIDE.md
TEAM_ID="PV3W52NDZ3"  # Your Apple Developer Team ID

# Paths
BUILD_DIR="build"
APP_PATH="${BUILD_DIR}/${APP_NAME}.app"
DMG_NAME="PingWarden-${VERSION}.dmg"
ZIP_NAME="PingWarden-${VERSION}.zip"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Ping Warden Notarization Script v${VERSION}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Verify app exists
if [ ! -d "$APP_PATH" ]; then
    echo -e "${RED}Error: ${APP_PATH} not found${NC}"
    echo "Please build the app in Xcode first:"
    echo "  1. Product → Archive"
    echo "  2. Export as Developer ID signed app"
    echo "  3. Move to ${BUILD_DIR}/"
    exit 1
fi

echo -e "${GREEN}✓${NC} App bundle found"

# Step 2: Verify code signing
echo ""
echo "Verifying code signature..."
if ! codesign --verify --deep --strict --verbose=2 "$APP_PATH" 2>&1 | grep -q "satisfies"; then
    echo -e "${RED}Error: App is not properly code signed${NC}"
    echo "Make sure you built with Developer ID Application certificate"
    exit 1
fi

# Check for Developer ID signature (not ad-hoc)
SIGNING_IDENTITY=$(codesign -dvv "$APP_PATH" 2>&1 | grep "Authority=Developer ID Application" || true)
if [ -z "$SIGNING_IDENTITY" ]; then
    echo -e "${RED}Error: App is not signed with Developer ID Application certificate${NC}"
    echo "Current signature:"
    codesign -dvv "$APP_PATH" 2>&1 | grep "Authority"
    echo ""
    echo "Please sign with Developer ID certificate in Xcode"
    exit 1
fi

echo -e "${GREEN}✓${NC} Code signature valid"
echo "  ${SIGNING_IDENTITY}"

# Step 3: Create ZIP for notarization
echo ""
echo "Creating ZIP archive for notarization..."
cd "$BUILD_DIR"
ditto -c -k --keepParent "${APP_NAME}.app" "../${ZIP_NAME}"
cd ..

echo -e "${GREEN}✓${NC} Created ${ZIP_NAME}"

# Step 4: Submit for notarization
echo ""
echo "Submitting to Apple for notarization..."
echo "This may take 1-10 minutes..."
echo ""

SUBMIT_OUTPUT=$(xcrun notarytool submit "$ZIP_NAME" \
    --keychain-profile "$KEYCHAIN_PROFILE" \
    --wait 2>&1)

echo "$SUBMIT_OUTPUT"

# Check if submission succeeded
if echo "$SUBMIT_OUTPUT" | grep -q "status: Accepted"; then
    echo ""
    echo -e "${GREEN}✓ Notarization successful!${NC}"
else
    echo ""
    echo -e "${RED}✗ Notarization failed${NC}"
    exit 1
fi

# Step 5: Staple the ticket
echo ""
echo "Stapling notarization ticket..."
xcrun stapler staple "$APP_PATH"

echo -e "${GREEN}✓${NC} Ticket stapled successfully"

# Step 6: Create notarized DMG
echo ""
echo "Creating notarized DMG..."
if [ -f "create-dmg.sh" ]; then
    ./create-dmg.sh "$VERSION"
    
    if [ -f "$DMG_NAME" ]; then
        echo "Stapling DMG..."
        xcrun stapler staple "$DMG_NAME"
        echo -e "${GREEN}✓${NC} DMG stapled"
    fi
fi

# Summary
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}Notarization Complete!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Notarized files:"
echo "  • ${APP_PATH}"
if [ -f "$DMG_NAME" ]; then
    echo "  • ${DMG_NAME}"
fi
echo ""
echo -e "${GREEN}Done!${NC} 🎉"
echo ""

# Clean up
rm "$ZIP_NAME"

