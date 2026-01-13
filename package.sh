#!/bin/bash
#
# package.sh
# Ping Warden (AWDLControl)
#
# Notarizes the app and creates a distributable DMG.
# Run this after build.sh completes successfully.
#
# Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
# Licensed under the MIT License.
#
# Prerequisites:
#   1. App must be signed with "Developer ID Application" certificate
#   2. Set up credentials (choose one method):
#      a) Keychain (recommended):
#         xcrun notarytool store-credentials "notarytool-profile" \
#             --apple-id "your@email.com" \
#             --team-id "PV3W52NDZ3" \
#             --password "app-specific-password"
#      b) Environment variables:
#         export NOTARIZE_APPLE_ID="your@email.com"
#         export NOTARIZE_PASSWORD="app-specific-password"
#         export NOTARIZE_TEAM_ID="PV3W52NDZ3"
#
# Usage:
#   ./package.sh                    # Uses keychain profile "notarytool-profile"
#   ./package.sh --skip-notarize    # Create DMG without notarization (testing only)
#

set -eo pipefail

echo "📦 Packaging Ping Warden for distribution..."
echo ""

# Configuration
APP_NAME="Ping Warden"
APP_BUNDLE="AWDLControl/build/Release/${APP_NAME}.app"
OUTPUT_DIR="AWDLControl/build/Release"
DMG_NAME="Ping.Warden.dmg"
DMG_PATH="${OUTPUT_DIR}/${DMG_NAME}"
ZIP_PATH="${OUTPUT_DIR}/${APP_NAME}.zip"
KEYCHAIN_PROFILE="notarytool-profile"
TEAM_ID="PV3W52NDZ3"

# Parse arguments
SKIP_NOTARIZE=false
for arg in "$@"; do
    case $arg in
        --skip-notarize)
            SKIP_NOTARIZE=true
            echo "⚠️  Skipping notarization (testing mode)"
            echo ""
            ;;
    esac
done

# Verify app bundle exists
echo "🔍 Checking for built app..."
if [ ! -d "$APP_BUNDLE" ]; then
    echo "   ❌ App bundle not found at: $APP_BUNDLE"
    echo ""
    echo "   Please run ./build.sh first to build the app."
    exit 1
fi
echo "   ✅ Found app bundle"

# Verify app is signed with Developer ID (required for notarization)
echo "🔍 Verifying code signature..."
SIGNING_AUTH=$(codesign -dvvv "$APP_BUNDLE" 2>&1 | grep "Authority=Developer ID Application" || true)
if [ -z "$SIGNING_AUTH" ] && [ "$SKIP_NOTARIZE" = false ]; then
    echo "   ❌ App is not signed with Developer ID Application certificate"
    echo ""
    echo "   Notarization requires a Developer ID Application certificate."
    echo "   Current signature:"
    codesign -dvvv "$APP_BUNDLE" 2>&1 | grep "Authority" || echo "   (no signature found)"
    echo ""
    echo "   Options:"
    echo "   1. Sign with Developer ID certificate and rebuild"
    echo "   2. Use --skip-notarize for local testing (not for distribution)"
    exit 1
fi
echo "   ✅ App is properly signed"
echo ""

# Determine notarization credentials
get_credentials() {
    # Method 1: Check for stored keychain profile
    if xcrun notarytool history --keychain-profile "$KEYCHAIN_PROFILE" >/dev/null 2>&1; then
        echo "keychain"
        return
    fi

    # Method 2: Check for environment variables
    if [ -n "$NOTARIZE_APPLE_ID" ] && [ -n "$NOTARIZE_PASSWORD" ]; then
        echo "env"
        return
    fi

    echo "none"
}

if [ "$SKIP_NOTARIZE" = false ]; then
    echo "🔍 Checking notarization credentials..."
    CRED_METHOD=$(get_credentials)

    case $CRED_METHOD in
        keychain)
            echo "   ✅ Using keychain profile: $KEYCHAIN_PROFILE"
            NOTARIZE_ARGS="--keychain-profile $KEYCHAIN_PROFILE"
            ;;
        env)
            echo "   ✅ Using environment variables"
            NOTARIZE_ARGS="--apple-id $NOTARIZE_APPLE_ID --team-id ${NOTARIZE_TEAM_ID:-$TEAM_ID} --password $NOTARIZE_PASSWORD"
            ;;
        none)
            echo "   ❌ No notarization credentials found"
            echo ""
            echo "   Set up credentials using one of these methods:"
            echo ""
            echo "   Method 1 - Keychain (recommended, one-time setup):"
            echo "   xcrun notarytool store-credentials \"$KEYCHAIN_PROFILE\" \\"
            echo "       --apple-id \"your@email.com\" \\"
            echo "       --team-id \"$TEAM_ID\" \\"
            echo "       --password \"your-app-specific-password\""
            echo ""
            echo "   Method 2 - Environment variables:"
            echo "   export NOTARIZE_APPLE_ID=\"your@email.com\""
            echo "   export NOTARIZE_PASSWORD=\"your-app-specific-password\""
            echo "   export NOTARIZE_TEAM_ID=\"$TEAM_ID\"  # optional"
            echo ""
            echo "   Note: Create an app-specific password at https://appleid.apple.com"
            exit 1
            ;;
    esac
    echo ""
fi

# Clean up previous artifacts
echo "🧹 Cleaning up previous artifacts..."
rm -f "$ZIP_PATH" "$DMG_PATH"
echo "   ✅ Cleaned"
echo ""

# Step 1: Create ZIP for notarization
echo "📦 Creating ZIP archive for notarization..."
ditto -c -k --keepParent "$APP_BUNDLE" "$ZIP_PATH"
ZIP_SIZE=$(du -h "$ZIP_PATH" | cut -f1)
echo "   ✅ Created $ZIP_PATH ($ZIP_SIZE)"
echo ""

# Step 2: Notarize the app
if [ "$SKIP_NOTARIZE" = false ]; then
    echo "🍎 Submitting app to Apple for notarization..."
    echo "   This may take several minutes..."
    echo ""

    # Submit and wait for result
    NOTARIZE_OUTPUT=$(xcrun notarytool submit "$ZIP_PATH" $NOTARIZE_ARGS --wait 2>&1) || {
        echo "   ❌ Notarization failed"
        echo ""
        echo "$NOTARIZE_OUTPUT"
        echo ""
        echo "   Common issues:"
        echo "   - Invalid credentials (check Apple ID and app-specific password)"
        echo "   - App contains unsigned code"
        echo "   - Hardened runtime not enabled"
        echo ""

        # Try to get submission ID for detailed log
        SUBMISSION_ID=$(echo "$NOTARIZE_OUTPUT" | grep -oE "id: [a-f0-9-]+" | head -1 | cut -d' ' -f2 || true)
        if [ -n "$SUBMISSION_ID" ]; then
            echo "   Fetching detailed log..."
            xcrun notarytool log "$SUBMISSION_ID" $NOTARIZE_ARGS 2>/dev/null || true
        fi
        exit 1
    }

    # Check for success
    if echo "$NOTARIZE_OUTPUT" | grep -q "status: Accepted"; then
        echo "   ✅ App notarization accepted by Apple"
    else
        echo "   ⚠️  Notarization result:"
        echo "$NOTARIZE_OUTPUT"
    fi
    echo ""

    # Step 3: Staple the notarization ticket to the app
    echo "📎 Stapling notarization ticket to app..."
    xcrun stapler staple "$APP_BUNDLE"
    echo "   ✅ Ticket stapled to app"
    echo ""
fi

# Step 4: Create DMG
echo "💿 Creating DMG..."

# Create a temporary directory for DMG contents
DMG_TEMP=$(mktemp -d)
trap "rm -rf $DMG_TEMP" EXIT

# Copy app to temp directory
cp -R "$APP_BUNDLE" "$DMG_TEMP/"

# Create Applications symlink for drag-to-install
ln -s /Applications "$DMG_TEMP/Applications"

# Create the DMG
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_PATH"

DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
echo "   ✅ Created $DMG_PATH ($DMG_SIZE)"
echo ""

# Step 5: Notarize the DMG
if [ "$SKIP_NOTARIZE" = false ]; then
    echo "🍎 Submitting DMG to Apple for notarization..."
    echo "   This may take several minutes..."
    echo ""

    NOTARIZE_DMG_OUTPUT=$(xcrun notarytool submit "$DMG_PATH" $NOTARIZE_ARGS --wait 2>&1) || {
        echo "   ❌ DMG notarization failed"
        echo ""
        echo "$NOTARIZE_DMG_OUTPUT"
        exit 1
    }

    if echo "$NOTARIZE_DMG_OUTPUT" | grep -q "status: Accepted"; then
        echo "   ✅ DMG notarization accepted by Apple"
    else
        echo "   ⚠️  DMG notarization result:"
        echo "$NOTARIZE_DMG_OUTPUT"
    fi
    echo ""

    # Step 6: Staple the notarization ticket to the DMG
    echo "📎 Stapling notarization ticket to DMG..."
    xcrun stapler staple "$DMG_PATH"
    echo "   ✅ Ticket stapled to DMG"
    echo ""
fi

# Clean up ZIP (no longer needed)
rm -f "$ZIP_PATH"

# Verify final DMG
echo "🔍 Verifying final DMG..."
if [ "$SKIP_NOTARIZE" = false ]; then
    spctl --assess --type open --context context:primary-signature -v "$DMG_PATH" 2>&1 && \
        echo "   ✅ DMG passes Gatekeeper validation" || \
        echo "   ⚠️  DMG may have Gatekeeper warnings (check manually)"
else
    echo "   ⏭️  Skipped (notarization was skipped)"
fi
echo ""

# Done!
echo "============================================"
echo "✅ Packaging complete!"
echo "============================================"
echo ""
echo "📍 DMG location:"
echo "   $DMG_PATH"
echo ""
if [ "$SKIP_NOTARIZE" = false ]; then
    echo "🚀 Ready for distribution!"
    echo "   Users can now install without Gatekeeper warnings."
else
    echo "⚠️  NOT ready for distribution (notarization skipped)"
    echo "   This DMG will trigger Gatekeeper warnings for users."
fi
echo ""
echo "📋 To upload to GitHub Releases:"
echo "   gh release upload v2.0.1 \"$DMG_PATH\" --clobber"
echo ""
