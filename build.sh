#!/bin/bash
#
# build.sh
# Ping Warden (AWDLControl)
#
# Build script for the app, widget, and helper.
#
# Copyright (c) 2025 Oliver Ames. All rights reserved.
# Licensed under the MIT License.
#

set -eo pipefail

echo "🔨 Building Ping Warden v2.0..."
echo ""

# Development Team ID (must match Xcode project settings)
DEVELOPMENT_TEAM="PV3W52NDZ3"

# Expected team ID in project file (for validation)
PROJECT_FILE="AWDLControl/AWDLControl.xcodeproj/project.pbxproj"

# Validate team ID matches project
echo "🔍 Validating build configuration..."
if [ -f "$PROJECT_FILE" ]; then
    PROJECT_TEAM=$(grep -o 'DEVELOPMENT_TEAM = [^;]*' "$PROJECT_FILE" | head -1 | cut -d'"' -f2 | tr -d '=; ')
    if [ -n "$PROJECT_TEAM" ] && [ "$PROJECT_TEAM" != "$DEVELOPMENT_TEAM" ]; then
        echo "   ⚠️  Warning: DEVELOPMENT_TEAM mismatch"
        echo "      Script: $DEVELOPMENT_TEAM"
        echo "      Project: $PROJECT_TEAM"
        echo "      Using project value..."
        DEVELOPMENT_TEAM="$PROJECT_TEAM"
    else
        echo "   ✅ DEVELOPMENT_TEAM validated: $DEVELOPMENT_TEAM"
    fi
fi

# Check if we can find a valid signing identity
# Use exact pattern matching to avoid substring matches
echo "🔍 Checking for Developer ID certificate..."
AVAILABLE_CERTS=$(security find-identity -v -p codesigning 2>/dev/null || true)

# First try to find an exact "Developer ID Application" certificate (not expired)
if echo "$AVAILABLE_CERTS" | grep -E "\"Developer ID Application: [^\"]+\"$" | grep -v "CSSMERR" > /dev/null 2>&1; then
    SIGNING_IDENTITY="Developer ID Application"
    echo "   ✅ Found Developer ID Application certificate"
# Fall back to Apple Development
elif echo "$AVAILABLE_CERTS" | grep -E "\"Apple Development: [^\"]+\"$" | grep -v "CSSMERR" > /dev/null 2>&1; then
    SIGNING_IDENTITY="Apple Development"
    echo "   ✅ Found Apple Development certificate"
# Last resort: any development certificate
elif echo "$AVAILABLE_CERTS" | grep -E "\"[^\"]+Development[^\"]+\"$" | grep -v "CSSMERR" > /dev/null 2>&1; then
    SIGNING_IDENTITY=$(echo "$AVAILABLE_CERTS" | grep -E "\"[^\"]+Development[^\"]+\"$" | grep -v "CSSMERR" | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    echo "   ✅ Found certificate: $SIGNING_IDENTITY"
else
    echo "   ❌ No valid signing certificate found!"
    echo ""
    echo "   Available certificates:"
    echo "$AVAILABLE_CERTS" | grep -v "^$" | head -10 || echo "   (none)"
    echo ""
    echo "   To build this app, you need either:"
    echo "   - A Developer ID Application certificate (for distribution)"
    echo "   - An Apple Development certificate (for local testing)"
    echo ""
    echo "   Please ensure you are signed into Xcode with your Apple Developer account."
    exit 1
fi

echo ""

# Build all targets with proper signing
echo "📱 Building app, widget, and helper..."

# Use tee to capture output while showing progress, handle signals properly
BUILD_LOG="/tmp/xcodebuild.log"
trap 'echo ""; echo "Build interrupted. Log saved to $BUILD_LOG"; exit 130' INT TERM

xcodebuild -project AWDLControl/AWDLControl.xcodeproj \
           -target AWDLControl \
           -target AWDLControlWidget \
           -target AWDLControlHelper \
           -configuration Release \
           DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
           CODE_SIGN_STYLE=Automatic \
           clean build 2>&1 | tee "$BUILD_LOG" | grep -E "^(Build|Compile|Sign|error:|warning:|===)" || true

# Check the actual exit status from xcodebuild (not from grep)
XCODE_EXIT=${PIPESTATUS[0]}

if [ $XCODE_EXIT -eq 0 ]; then
    echo ""
    echo "✅ Build succeeded"
    echo ""

    APP_BUNDLE="AWDLControl/build/Release/Ping Warden.app"
    HELPER_BINARY="AWDLControl/build/Release/AWDLControlHelper"
    HELPER_PLIST="AWDLControl/AWDLControlHelper/com.awdlcontrol.helper.plist"

    # Validate required files exist BEFORE copying
    echo "🔍 Validating build artifacts..."
    if [ ! -d "$APP_BUNDLE" ]; then
        echo "   ❌ App bundle not found at $APP_BUNDLE"
        exit 1
    fi
    if [ ! -f "$HELPER_BINARY" ]; then
        echo "   ❌ Helper binary not found at $HELPER_BINARY"
        exit 1
    fi
    if [ ! -f "$HELPER_PLIST" ]; then
        echo "   ❌ Helper plist not found at $HELPER_PLIST"
        exit 1
    fi
    echo "   ✅ All build artifacts present"

    # Bundle helper binary into app
    echo "📦 Bundling helper..."
    cp "$HELPER_BINARY" "$APP_BUNDLE/Contents/MacOS/"
    chmod 755 "$APP_BUNDLE/Contents/MacOS/AWDLControlHelper"
    echo "   ✅ Helper binary copied to Contents/MacOS/"

    # Bundle helper plist for SMAppService
    echo "📦 Bundling helper plist..."
    mkdir -p "$APP_BUNDLE/Contents/Library/LaunchDaemons"
    cp "$HELPER_PLIST" "$APP_BUNDLE/Contents/Library/LaunchDaemons/"
    echo "   ✅ Helper plist copied to Contents/Library/LaunchDaemons/"

    echo ""

    # Re-sign the app bundle after adding helper with proper Developer ID
    echo "🔏 Signing app bundle with $SIGNING_IDENTITY..."
    codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
    echo "   ✅ App bundle signed"

    echo ""

    # Verify bundle structure
    echo "📋 Verifying bundle structure..."
    MACOS_DIR="$APP_BUNDLE/Contents/MacOS"
    DAEMON_DIR="$APP_BUNDLE/Contents/Library/LaunchDaemons"

    echo "   Contents/MacOS:"
    ls -la "$MACOS_DIR" | grep -E "Ping Warden|Helper" || true

    echo "   Contents/Library/LaunchDaemons:"
    ls -la "$DAEMON_DIR" 2>/dev/null || echo "   (directory missing)"

    # Verify required files exist
    if [ ! -f "$MACOS_DIR/Ping Warden" ]; then
        echo "   ❌ Main app binary missing!"
        exit 1
    fi
    if [ ! -f "$MACOS_DIR/AWDLControlHelper" ]; then
        echo "   ❌ Helper binary missing!"
        exit 1
    fi
    if [ ! -f "$DAEMON_DIR/com.awdlcontrol.helper.plist" ]; then
        echo "   ❌ Helper plist missing!"
        exit 1
    fi

    # Verify code signature
    echo ""
    echo "🔏 Verifying code signature..."
    codesign -dvvv "$APP_BUNDLE" 2>&1 | grep -E "Authority|Identifier|TeamIdentifier" || true

    echo ""
    echo "✅ Build complete!"
    echo ""
    echo "📍 App location:"
    echo "   $APP_BUNDLE"
    echo ""
    echo "📋 To install:"
    echo "   cp -r \"$APP_BUNDLE\" /Applications/"
    echo ""
    echo "📋 First launch:"
    echo "   1. Open Ping Warden.app"
    echo "   2. Click 'Set Up Now' when prompted"
    echo "   3. Approve in System Settings → Login Items (one-time)"
    echo ""
else
    echo ""
    echo "❌ Build failed (exit code: $XCODE_EXIT)"
    echo ""
    echo "Build log saved to: $BUILD_LOG"
    echo ""
    echo "Last 50 lines of build log:"
    tail -50 "$BUILD_LOG"
    exit 1
fi
