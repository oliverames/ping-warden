#!/bin/bash

# Manual Helper Embedding Script
# Run this after building both AWDLControlHelper and AWDLControl targets

set -e

echo "🔧 Embedding AWDLControlHelper in app bundle..."
echo ""

# Find the DerivedData directory
DERIVED_DATA_BASE="$HOME/Library/Developer/Xcode/DerivedData"
DERIVED_DATA_DIR=$(find "$DERIVED_DATA_BASE" -name "AWDLControl-*" -type d 2>/dev/null | head -1)

if [ -z "$DERIVED_DATA_DIR" ]; then
    echo "❌ Error: Could not find AWDLControl DerivedData directory"
    echo "Please build the project in Xcode first (⌘B)"
    exit 1
fi

# Try Debug build first, then Release
for CONFIG in Debug Release; do
    BUILD_DIR="$DERIVED_DATA_DIR/Build/Products/$CONFIG"
    APP_PATH="$BUILD_DIR/AWDLControl.app"
    HELPER_PATH="$BUILD_DIR/AWDLControlHelper"

    if [ -d "$APP_PATH" ] && [ -f "$HELPER_PATH" ]; then
        echo "Found $CONFIG build:"
        echo "  App: $APP_PATH"
        echo "  Helper: $HELPER_PATH"
        echo ""

        # Create LaunchServices directory
        LAUNCH_SERVICES_DIR="$APP_PATH/Contents/Library/LaunchServices"
        mkdir -p "$LAUNCH_SERVICES_DIR"

        # Copy helper
        HELPER_DEST="$LAUNCH_SERVICES_DIR/com.awdlcontrol.helper"
        cp -f "$HELPER_PATH" "$HELPER_DEST"
        chmod 755 "$HELPER_DEST"

        echo "✅ Helper embedded successfully!"
        echo ""
        echo "Verification:"
        ls -lh "$LAUNCH_SERVICES_DIR/"
        echo ""
        echo "Next steps:"
        echo "1. Run AWDLControl.app from Xcode (⌘R)"
        echo "2. Click the menu bar icon"
        echo "3. Click 'Enable AWDL Monitoring'"
        echo "4. Enter your password when prompted (ONE TIME ONLY)"
        echo ""
        exit 0
    fi
done

echo "❌ Error: Could not find built app and helper"
echo ""
echo "Please build both targets in Xcode:"
echo "1. Select 'AWDLControlHelper' scheme → Build (⌘B)"
echo "2. Select 'AWDLControl' scheme → Build (⌘B)"
echo "3. Run this script again"
exit 1
