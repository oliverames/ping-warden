#!/bin/bash
set -e

echo "🔨 Building Ping Warden v2.0..."
echo ""

# Development Team ID (must match Xcode project settings)
DEVELOPMENT_TEAM="PV3W52NDZ3"

# Check if we can find a valid signing identity
echo "🔍 Checking for Developer ID certificate..."
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
    SIGNING_IDENTITY="Developer ID Application"
    echo "   ✅ Found Developer ID Application certificate"
elif security find-identity -v -p codesigning | grep -q "Apple Development"; then
    SIGNING_IDENTITY="Apple Development"
    echo "   ✅ Found Apple Development certificate"
else
    echo "   ❌ No valid signing certificate found!"
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
xcodebuild -project AWDLControl/AWDLControl.xcodeproj \
           -target AWDLControl \
           -target AWDLControlWidget \
           -target AWDLControlHelper \
           -configuration Release \
           DEVELOPMENT_TEAM="$DEVELOPMENT_TEAM" \
           CODE_SIGN_STYLE=Automatic \
           clean build \
           > /tmp/xcodebuild.log 2>&1

XCODE_EXIT=$?

if [ $XCODE_EXIT -eq 0 ]; then
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
    echo "   ✅ App bundle signed with Developer ID"

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
    echo "❌ Build failed. Check /tmp/xcodebuild.log for details"
    echo ""
    echo "Last 50 lines of build log:"
    tail -50 /tmp/xcodebuild.log
    exit 1
fi
