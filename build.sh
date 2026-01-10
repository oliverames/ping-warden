#!/bin/bash
set -e

echo "🔨 Building Ping Warden v2.0..."
echo ""
echo "⚠️  Note: For proper app icon, build from Xcode IDE instead."
echo ""

# Build targets
# Note: Widget requires Developer ID signing (App Groups entitlement)
# For development/unsigned builds, we build app + helper only
echo "📱 Building app and helper..."
# Temporarily disable set -e to handle xcodebuild failure gracefully
set +e

# Try building all targets first (requires Developer ID for widget)
xcodebuild -project AWDLControl/AWDLControl.xcodeproj \
           -target AWDLControl \
           -target AWDLControlWidget \
           -target AWDLControlHelper \
           -configuration Release \
           clean build \
           > /tmp/xcodebuild.log 2>&1
XCODE_EXIT=$?

# If full build fails (likely due to signing), try without widget and entitlements
if [ $XCODE_EXIT -ne 0 ]; then
    echo "   ⚠️  Full build failed, trying without widget (requires Developer ID)..."
    xcodebuild -project AWDLControl/AWDLControl.xcodeproj \
               -target AWDLControl \
               -target AWDLControlHelper \
               -configuration Release \
               clean build \
               CODE_SIGN_IDENTITY="-" \
               CODE_SIGNING_REQUIRED=NO \
               CODE_SIGNING_ALLOWED=YES \
               CODE_SIGN_ENTITLEMENTS="" \
               > /tmp/xcodebuild.log 2>&1
    XCODE_EXIT=$?
fi
set -e

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

    # Re-sign the app bundle after adding helper (important!)
    echo "🔏 Signing app bundle..."
    codesign --force --deep --sign - "$APP_BUNDLE"
    echo "   ✅ App bundle signed with ad-hoc signature"

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
    codesign -vvv "$APP_BUNDLE" 2>&1 | head -5 || echo "   ⚠️  Signature verification warning (ad-hoc is expected)"

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
    echo "🎉 No more password prompts after initial setup!"
else
    echo "❌ Build failed. Check /tmp/xcodebuild.log for details"
    echo ""
    echo "Last 50 lines of build log:"
    tail -50 /tmp/xcodebuild.log
    exit 1
fi
