#!/bin/bash
#
#  release.sh
#  Complete release automation: notarize + create DMG + update appcast + GitHub release
#
#  Usage: ./release.sh [version] [release-notes-file]
#  Example: ./release.sh 2.1.0 release_notes_2.1.0.txt
#
#  Copyright (c) 2025-2026 Oliver Ames. All rights reserved.
#  Licensed under the MIT License.
#

set -e

# Configuration
VERSION="${1}"
RELEASE_NOTES="${2:-RELEASE_NOTES.md}"
APP_NAME="Ping Warden"
BUNDLE_ID="com.amesvt.pingwarden"
DMG_NAME="PingWarden-${VERSION}.dmg"
ZIP_NAME="PingWarden-${VERSION}.zip"
BUILD_DIR="build"
SPARKLE_KEY="$HOME/sparkle_private_key"
GITHUB_USER="oliverames"
REPO_NAME="ping-warden"

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
    echo "Example: ./release.sh 2.1.0"
    exit 1
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo -e "  ${BLUE}Ping Warden Release Automation v${VERSION}${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Step 1: Notarize
echo -e "${GREEN}Step 1: Notarizing app...${NC}"
./notarize.sh "$VERSION"

if [ $? -ne 0 ]; then
    echo -e "${RED}Notarization failed!${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Notarization complete${NC}"
echo ""

# Step 2: Verify DMG exists
if [ ! -f "$DMG_NAME" ]; then
    echo -e "${RED}Error: DMG not found: $DMG_NAME${NC}"
    echo "notarize.sh should have created it"
    exit 1
fi

echo -e "${GREEN}✓ DMG found: $DMG_NAME${NC}"
echo ""

# Step 3: Sign update for Sparkle (if key exists)
if [ -f "$SPARKLE_KEY" ]; then
    echo -e "${GREEN}Step 2: Signing update for Sparkle...${NC}"
    
    # Find sign_update tool (from Sparkle SPM package)
    SIGN_TOOL=$(find ~/Library/Developer/Xcode/DerivedData -name "sign_update" -type f 2>/dev/null | head -1)
    
    if [ -z "$SIGN_TOOL" ]; then
        echo -e "${YELLOW}⚠ sign_update tool not found${NC}"
        echo "Sparkle may not be installed yet. Skipping signature."
        SIGNATURE=""
    else
        # Create ZIP if it doesn't exist (notarize.sh cleans it up)
        if [ ! -f "$ZIP_NAME" ]; then
            cd "$BUILD_DIR"
            ditto -c -k --keepParent "${APP_NAME}.app" "../${ZIP_NAME}"
            cd ..
        fi
        
        SIGNATURE=$("$SIGN_TOOL" "$ZIP_NAME" --ed-key-file "$SPARKLE_KEY")
        echo -e "${GREEN}✓ Signature: ${SIGNATURE}${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Sparkle private key not found at $SPARKLE_KEY${NC}"
    echo "Skipping Sparkle signature (updates won't work until you add Sparkle)"
    SIGNATURE=""
fi

echo ""

# Step 4: Get file size and date
DMG_SIZE=$(stat -f%z "$DMG_NAME")
DMG_DATE=$(date -u +"%a, %d %b %Y %H:%M:%S %Z")

echo -e "${GREEN}Step 3: Preparing release metadata...${NC}"
echo "  Version: $VERSION"
echo "  DMG Size: $DMG_SIZE bytes"
echo "  Date: $DMG_DATE"
echo ""

# Step 5: Update appcast.xml
echo -e "${GREEN}Step 4: Updating appcast.xml...${NC}"

# Check if appcast exists
APPCAST_FILE="appcast.xml"
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
        url=\"https://github.com/$GITHUB_USER/$REPO_NAME/releases/download/v$VERSION/$DMG_NAME\"
        sparkle:version=\"$VERSION\"
        sparkle:shortVersionString=\"$VERSION\"
        length=\"$DMG_SIZE\"
        type=\"application/octet-stream\"
        $([ -n "$SIGNATURE" ] && echo "sparkle:edSignature=\"$SIGNATURE\"")
      />
    </item>"

# Insert new item after <language>en</language> line
sed -i "" "/<language>en<\/language>/a\\
$NEW_ITEM
" "$APPCAST_FILE"

echo -e "${GREEN}✓ Appcast updated${NC}"
echo ""

# Step 6: Create GitHub release
echo -e "${GREEN}Step 5: Creating GitHub release...${NC}"

if ! command -v gh &> /dev/null; then
    echo -e "${YELLOW}⚠ GitHub CLI (gh) not installed${NC}"
    echo ""
    echo "To create release manually:"
    echo "1. Go to https://github.com/$GITHUB_USER/$REPO_NAME/releases/new"
    echo "2. Tag: v$VERSION"
    echo "3. Title: Ping Warden v$VERSION"
    echo "4. Upload: $DMG_NAME"
    echo "5. Copy notes from $RELEASE_NOTES"
    echo ""
else
    # Create release with gh CLI
    if [ -f "$RELEASE_NOTES" ]; then
        gh release create "v$VERSION" \
            "$DMG_NAME" \
            --title "Ping Warden v$VERSION" \
            --notes-file "$RELEASE_NOTES"
    else
        gh release create "v$VERSION" \
            "$DMG_NAME" \
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
echo "  • $DMG_NAME"
echo "  • GitHub release: https://github.com/$GITHUB_USER/$REPO_NAME/releases/tag/v$VERSION"
echo "  • Appcast: $APPCAST_FILE (needs to be pushed to gh-pages)"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
