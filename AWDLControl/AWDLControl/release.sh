#!/bin/bash
#
#  release.sh
#  Complete release automation: notarize + create DMG + update appcast + GitHub release
#
#  Usage: ./release.sh [version] [release-notes-file]
#  Example: ./release.sh 2.1.1 release_notes_2.1.1.txt
#
#  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
#  Licensed under the MIT License.
#

set -e

# Resolve paths relative to this script so execution is cwd-independent.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
REPO_ROOT="$(cd "$PROJECT_ROOT/.." && pwd)"

# Configuration
VERSION="${1}"
RELEASE_NOTES="${2:-RELEASE_NOTES.md}"
APP_NAME="Ping Warden"
BUNDLE_ID="com.amesvt.pingwarden"
DMG_BASENAME="PingWarden-${VERSION}.dmg"
DMG_PATH="$PROJECT_ROOT/$DMG_BASENAME"
BUILD_DIR="$PROJECT_ROOT/build"
SPARKLE_KEY="$HOME/sparkle_private_key"
SPARKLE_KEYCHAIN_ACCOUNT="${SPARKLE_KEYCHAIN_ACCOUNT:-ed25519}"
GITHUB_USER="oliverames"
REPO_NAME="ping-warden"
NOTARIZE_SCRIPT="$SCRIPT_DIR/notarize.sh"
APPCAST_FILE="$REPO_ROOT/appcast.xml"
APP_INFO_PLIST="$PROJECT_ROOT/AWDLControl/Info.plist"

if [[ "$RELEASE_NOTES" = /* ]]; then
    RELEASE_NOTES_PATH="$RELEASE_NOTES"
else
    if [ -f "$PROJECT_ROOT/$RELEASE_NOTES" ]; then
        RELEASE_NOTES_PATH="$PROJECT_ROOT/$RELEASE_NOTES"
    else
        RELEASE_NOTES_PATH="$REPO_ROOT/$RELEASE_NOTES"
    fi
fi

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m'

# Validation
if [ -z "$VERSION" ]; then
    echo -e "${RED}Error: Version required${NC}"
    echo "Usage: ./release.sh [version] [release-notes-file]"
    echo "Example: ./release.sh 2.1.1"
    exit 1
fi

# Ensure the app bundle version matches the release argument
PLIST_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_INFO_PLIST" 2>/dev/null || true)
if [ -z "$PLIST_VERSION" ]; then
    echo -e "${RED}Error: Failed to read CFBundleShortVersionString from $APP_INFO_PLIST${NC}"
    exit 1
fi

if [ "$PLIST_VERSION" != "$VERSION" ]; then
    echo -e "${RED}Error: Version mismatch${NC}"
    echo "  release.sh version: $VERSION"
    echo "  Info.plist version: $PLIST_VERSION"
    echo "Update Info.plist before running release.sh."
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${BLUE}Ping Warden Release Automation v${VERSION}${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Notarize (or reuse existing notarized DMG)
if [ "${SKIP_NOTARIZE:-0}" = "1" ]; then
    echo -e "${YELLOW}Step 1: Skipping notarization (SKIP_NOTARIZE=1)${NC}"
else
    echo -e "${GREEN}Step 1: Notarizing app...${NC}"
    "$NOTARIZE_SCRIPT" "$VERSION"

    if [ $? -ne 0 ]; then
        echo -e "${RED}Notarization failed!${NC}"
        exit 1
    fi

    echo -e "${GREEN}✓ Notarization complete${NC}"
fi
echo ""

# Step 2: Verify DMG exists
if [ ! -f "$DMG_PATH" ]; then
    echo -e "${RED}Error: DMG not found: $DMG_PATH${NC}"
    echo "notarize.sh should have created it"
    exit 1
fi

echo -e "${GREEN}✓ DMG found: $(basename "$DMG_PATH")${NC}"
echo ""

# Step 3: Sign update for Sparkle (required)
echo -e "${GREEN}Step 2: Signing update for Sparkle...${NC}"

# Find sign_update tool (from Sparkle SPM package)
SIGN_TOOL=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -type f 2>/dev/null | head -1)

if [ -z "$SIGN_TOOL" ]; then
    echo -e "${RED}Error: sign_update tool not found${NC}"
    echo "Build Sparkle command line tools first so update signatures can be generated."
    exit 1
fi

if [ -f "$SPARKLE_KEY" ]; then
    SIGNATURE=$("$SIGN_TOOL" "$DMG_PATH" --ed-key-file "$SPARKLE_KEY" -p | tr -d '\r\n')
else
    echo -e "${YELLOW}Sparkle private key file not found at $SPARKLE_KEY${NC}"
    echo "Falling back to keychain account '$SPARKLE_KEYCHAIN_ACCOUNT'..."
    SIGNATURE=$("$SIGN_TOOL" "$DMG_PATH" --account "$SPARKLE_KEYCHAIN_ACCOUNT" -p | tr -d '\r\n')
fi

if [ -z "$SIGNATURE" ]; then
    echo -e "${RED}Error: Sparkle signature generation returned an empty signature${NC}"
    echo "Ensure your EdDSA key exists either at $SPARKLE_KEY or in the login keychain account '$SPARKLE_KEYCHAIN_ACCOUNT'."
    exit 1
fi

echo -e "${GREEN}✓ Signature: ${SIGNATURE}${NC}"

echo ""

# Step 4: Get file size and date
DMG_SIZE=$(stat -f%z "$DMG_PATH")
DMG_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S %Z")

echo -e "${GREEN}Step 3: Preparing release metadata...${NC}"
echo "  Version: $VERSION"
echo "  DMG Size: $DMG_SIZE bytes"
echo "  Date: $DMG_DATE"
echo ""

# Step 5: Update appcast.xml
echo -e "${GREEN}Step 4: Updating appcast.xml...${NC}"

# Check if appcast exists
if [ ! -f "$APPCAST_FILE" ]; then
    echo "Creating new appcast.xml"
    cat > "$APPCAST_FILE" << 'EOF'
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Ping Warden Updates</title>
    <link>https://GITHUB_USER.github.io/REPO_NAME/appcast.xml</link>
    <description>Updates for Ping Warden</description>
    <language>en</language>
  </channel>
</rss>
EOF
    # Replace placeholders
    sed -i "" "s/GITHUB_USER/$GITHUB_USER/g" "$APPCAST_FILE"
    sed -i "" "s/REPO_NAME/$REPO_NAME/g" "$APPCAST_FILE"
fi

# Create new item entry
NEW_ITEM="    <item>
      <title>Version $VERSION</title>
      <link>https://github.com/$GITHUB_USER/$REPO_NAME/releases/tag/v$VERSION</link>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <description><![CDATA[
        <h2>What's New in $VERSION</h2>
        <p>See release notes on GitHub</p>
      ]]></description>
      <pubDate>$DMG_DATE</pubDate>
      <enclosure
        url=\"https://github.com/$GITHUB_USER/$REPO_NAME/releases/download/v$VERSION/$DMG_BASENAME\"
        sparkle:version=\"$VERSION\"
        sparkle:shortVersionString=\"$VERSION\"
        length=\"$DMG_SIZE\"
        type=\"application/octet-stream\"
        $([ -n "$SIGNATURE" ] && echo "sparkle:edSignature=\"$SIGNATURE\"")
      />
      <sparkle:minimumSystemVersion>13.0</sparkle:minimumSystemVersion>
    </item>"

# Insert new item after <language>en</language> line (idempotent)
if grep -q "<sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>" "$APPCAST_FILE"; then
    echo "Version $VERSION already exists in appcast.xml; skipping insert."
else
    INSERT_FILE=$(mktemp /tmp/pingwarden-appcast-item.XXXXXX)
    printf "%s\n" "$NEW_ITEM" > "$INSERT_FILE"
    awk -v insert_file="$INSERT_FILE" '
        /<language>en<\/language>/ {
            print
            while ((getline line < insert_file) > 0) {
                print line
            }
            close(insert_file)
            next
        }
        { print }
    ' "$APPCAST_FILE" > "$APPCAST_FILE.tmp"
    mv "$APPCAST_FILE.tmp" "$APPCAST_FILE"
    rm -f "$INSERT_FILE"
fi

echo -e "${GREEN}✓ Appcast updated${NC}"
echo ""

# Validate appcast is well-formed and latest version matches requested release
if ! xmllint --noout "$APPCAST_FILE" 2>/dev/null; then
    echo -e "${RED}Error: appcast.xml is not valid XML${NC}"
    exit 1
fi

LATEST_APPCAST_VERSION=$(grep -m1 "<sparkle:shortVersionString>" "$APPCAST_FILE" | sed -E 's/.*<sparkle:shortVersionString>([^<]+)<\/sparkle:shortVersionString>.*/\1/')
if [ "$LATEST_APPCAST_VERSION" != "$VERSION" ]; then
    echo -e "${RED}Error: appcast latest version is $LATEST_APPCAST_VERSION, expected $VERSION${NC}"
    exit 1
fi

# Step 6: Create GitHub release
echo -e "${GREEN}Step 5: Creating GitHub release...${NC}"

if ! command -v gh &> /dev/null; then
    echo -e "${YELLOW}⚠ GitHub CLI (gh) not installed${NC}"
    echo ""
    echo "To create release manually:"
    echo "1. Go to https://github.com/$GITHUB_USER/$REPO_NAME/releases/new"
    echo "2. Tag: v$VERSION"
    echo "3. Title: Ping Warden v$VERSION"
    echo "4. Upload: $DMG_PATH"
    echo "5. Copy notes from $RELEASE_NOTES"
    echo ""
else
    # Create release with gh CLI
    if [ -f "$RELEASE_NOTES_PATH" ]; then
        gh release create "v$VERSION" \
            "$DMG_PATH" \
            --title "Ping Warden v$VERSION" \
            --notes-file "$RELEASE_NOTES_PATH"
    else
        gh release create "v$VERSION" \
            "$DMG_PATH" \
            --title "Ping Warden v$VERSION" \
            --notes "See CHANGELOG for details"
    fi
    
    echo -e "${GREEN}✓ GitHub release created${NC}"
fi

echo ""

# Step 7: Instructions for appcast
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "${GREEN}Release Complete!${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Next steps:"
echo ""
echo "1. Update appcast on GitHub Pages:"
echo "   ${BLUE}git checkout gh-pages${NC}"
echo "   ${BLUE}cp appcast.xml .${NC}"
echo "   ${BLUE}git add appcast.xml${NC}"
echo "   ${BLUE}git commit -m 'Update appcast for v$VERSION'${NC}"
echo "   ${BLUE}git push origin gh-pages${NC}"
echo "   ${BLUE}git checkout main${NC}"
echo ""
echo "2. Test the update:"
echo "   - Install an older version"
echo "   - Click 'Check for Updates'"
echo "   - Verify v$VERSION is offered"
echo ""
echo "3. Announce on Reddit:"
echo "   - r/GeForceNOW"
echo "   - r/xcloud"
echo "   - r/macgaming"
echo ""
echo "Release artifacts:"
echo "  • $DMG_PATH"
echo "  • GitHub release: https://github.com/$GITHUB_USER/$REPO_NAME/releases/tag/v$VERSION"
echo "  • Appcast: $APPCAST_FILE (needs to be pushed to gh-pages)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
