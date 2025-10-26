#!/bin/bash

# This script fixes the helper embedding in the app bundle
# It ensures the helper is copied to the correct location

echo "Fixing helper embedding in AWDLControl.app..."
echo ""

# Get the build output directory
BUILD_DIR="$HOME/Library/Developer/Xcode/DerivedData/AWDLControl-*/Build/Products/Debug"

# Find the actual build directory
ACTUAL_BUILD_DIR=$(find "$HOME/Library/Developer/Xcode/DerivedData" -name "AWDLControl-*" -type d 2>/dev/null | head -1)

if [ -z "$ACTUAL_BUILD_DIR" ]; then
    echo "Error: Could not find AWDLControl DerivedData directory"
    echo "Please build the project first in Xcode"
    exit 1
fi

BUILD_DIR="$ACTUAL_BUILD_DIR/Build/Products/Debug"

if [ ! -d "$BUILD_DIR" ]; then
    echo "Error: Build directory not found: $BUILD_DIR"
    echo "Please build both targets in Xcode first"
    exit 1
fi

APP_PATH="$BUILD_DIR/AWDLControl.app"
HELPER_PATH="$BUILD_DIR/AWDLControlHelper"

if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at: $APP_PATH"
    echo "Please build AWDLControl target first"
    exit 1
fi

if [ ! -f "$HELPER_PATH" ]; then
    echo "Error: Helper not found at: $HELPER_PATH"
    echo "Please build AWDLControlHelper target first"
    exit 1
fi

# Create the LaunchServices directory
LAUNCH_SERVICES_DIR="$APP_PATH/Contents/Library/LaunchServices"
mkdir -p "$LAUNCH_SERVICES_DIR"

# Copy the helper
echo "Copying helper to: $LAUNCH_SERVICES_DIR/"
cp "$HELPER_PATH" "$LAUNCH_SERVICES_DIR/com.awdlcontrol.helper"

# Set proper permissions
chmod 755 "$LAUNCH_SERVICES_DIR/com.awdlcontrol.helper"

# Copy the launchd.plist to the helper bundle location
# (SMJobBless expects it in Contents/ of the helper)
echo "Copying launchd.plist..."
HELPER_CONTENTS="$LAUNCH_SERVICES_DIR/com.awdlcontrol.helper/Contents"
mkdir -p "$HELPER_CONTENTS"
cp "AWDLControl/AWDLControlHelper/launchd.plist" "$HELPER_CONTENTS/"

echo ""
echo "✅ Helper embedded successfully!"
echo ""
echo "Verify:"
ls -la "$LAUNCH_SERVICES_DIR/"
echo ""
echo "Now run the app and try installing the helper"
