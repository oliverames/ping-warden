#!/bin/bash

# Embed Helper Script for AWDLControl
# This script automatically embeds the AWDLControlHelper in the app bundle
# Run as a build phase or manually after building

set -e

echo "Embedding AWDLControlHelper in app bundle..."

# Check if we're running in Xcode build phase
if [ -n "$BUILT_PRODUCTS_DIR" ]; then
    # Running as Xcode build phase
    APP_PATH="$BUILT_PRODUCTS_DIR/$PRODUCT_NAME.app"
    HELPER_PATH="$BUILT_PRODUCTS_DIR/AWDLControlHelper"
else
    # Running manually - find the built products
    echo "Error: This script should be run as an Xcode build phase"
    echo "Add it to the AWDLControl target's Build Phases"
    exit 1
fi

# Verify app exists
if [ ! -d "$APP_PATH" ]; then
    echo "Error: App not found at $APP_PATH"
    exit 1
fi

# Verify helper exists
if [ ! -f "$HELPER_PATH" ]; then
    echo "Error: Helper not found at $HELPER_PATH"
    echo "Please build the AWDLControlHelper target first"
    exit 1
fi

# Create LaunchServices directory
LAUNCH_SERVICES_DIR="$APP_PATH/Contents/Library/LaunchServices"
mkdir -p "$LAUNCH_SERVICES_DIR"

# Copy helper with correct name
HELPER_DEST="$LAUNCH_SERVICES_DIR/com.awdlcontrol.helper"
cp -f "$HELPER_PATH" "$HELPER_DEST"

# Set permissions
chmod 755 "$HELPER_DEST"

# Copy Info.plist if needed (SMJobBless requirement)
HELPER_INFO_PLIST="$SRCROOT/AWDLControlHelper/Info.plist"
if [ -f "$HELPER_INFO_PLIST" ]; then
    HELPER_CONTENTS_DIR="$LAUNCH_SERVICES_DIR/com.awdlcontrol.helper.bundle/Contents"
    mkdir -p "$HELPER_CONTENTS_DIR"
    cp -f "$HELPER_INFO_PLIST" "$HELPER_CONTENTS_DIR/Info.plist"
fi

echo "✅ Helper embedded at: $HELPER_DEST"
