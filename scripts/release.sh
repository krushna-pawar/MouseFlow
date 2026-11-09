#!/usr/bin/env bash
# Builds a Release archive of MouseFlow, packages it as a DMG, and writes the Sparkle update feed.
#
# The app is signed with the project's automatic signing (Apple Development) and is not
# notarized, so users must allow it once under System Settings › Privacy & Security.
# After that, Sparkle installs updates in place.
#
# Each release needs a higher build number (CURRENT_PROJECT_VERSION) than the one before:
# Sparkle compares build numbers, not the version shown to people.
#
# The DMG is signed for Sparkle with the private key stored in the login Keychain
# (created once with Sparkle's generate_keys). Back that key up: without it, installed
# copies can't receive updates.
#
# Usage: scripts/release.sh
# Output: build/release/MouseFlow-<version>.dmg and an updated appcast.xml
#
# Then publish in this order, so the feed never points at a missing file:
#   1. gh release create v<version> build/release/MouseFlow-<version>.dmg
#   2. commit and push appcast.xml

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MouseFlow"
REPO_URL="https://github.com/krushna-pawar/MouseFlow"
RELEASE_DIR="build/release"
ARCHIVE_PATH="$RELEASE_DIR/$APP_NAME.xcarchive"
STAGING_DIR="$RELEASE_DIR/dmg"
APPCAST_PATH="${APPCAST_PATH:-appcast.xml}"

rm -rf "$RELEASE_DIR"
mkdir -p "$STAGING_DIR"

echo "==> Archiving $APP_NAME (Release)"
xcodebuild archive \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -derivedDataPath build \
    -archivePath "$ARCHIVE_PATH" \
    -quiet

APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :CFBundleVersion" "$INFO_PLIST")
MIN_SYSTEM=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$INFO_PLIST")
DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$RELEASE_DIR/$DMG_NAME"
DOWNLOAD_URL="${DOWNLOAD_URL:-$REPO_URL/releases/download/v$VERSION/$DMG_NAME}"

# A new version with an old build number would never be offered to anyone.
if [[ -f "$APPCAST_PATH" ]]; then
    PREV_BUILD=$(sed -n 's:.*<sparkle\:version>\(.*\)</sparkle\:version>.*:\1:p' "$APPCAST_PATH" | head -1)
    PREV_VERSION=$(sed -n 's:.*<sparkle\:shortVersionString>\(.*\)</sparkle\:shortVersionString>.*:\1:p' "$APPCAST_PATH" | head -1)
    if [[ -n "$PREV_BUILD" && "$PREV_VERSION" != "$VERSION" && "$BUILD" -le "$PREV_BUILD" ]]; then
        echo "error: build $BUILD of $VERSION is not higher than build $PREV_BUILD of $PREV_VERSION in $APPCAST_PATH." >&2
        echo "Raise CURRENT_PROJECT_VERSION in the project and run again." >&2
        exit 1
    fi
fi

echo "==> Verifying signature"
codesign --verify --deep --strict "$APP_PATH"

echo "==> Staging DMG contents"
cp -R "$APP_PATH" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"
cp LICENSE THIRD_PARTY_NOTICES.md "$STAGING_DIR/"

echo "==> Creating $DMG_PATH"
hdiutil create \
    -volname "$APP_NAME $VERSION" \
    -srcfolder "$STAGING_DIR" \
    -fs HFS+ \
    -format UDZO \
    -ov \
    "$DMG_PATH" >/dev/null

rm -rf "$STAGING_DIR"

echo "==> Signing $DMG_NAME for Sparkle"
SIGN_UPDATE="build/SourcePackages/artifacts/sparkle/Sparkle/bin/sign_update"
SIGNATURE=$("$SIGN_UPDATE" "$DMG_PATH")   # sparkle:edSignature="…" length="…"

echo "==> Writing $APPCAST_PATH"
PUB_DATE=$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")
cat > "$APPCAST_PATH" <<EOF
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
    <channel>
        <title>$APP_NAME</title>
        <link>$REPO_URL</link>
        <item>
            <title>$APP_NAME $VERSION</title>
            <pubDate>$PUB_DATE</pubDate>
            <sparkle:version>$BUILD</sparkle:version>
            <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
            <sparkle:minimumSystemVersion>$MIN_SYSTEM</sparkle:minimumSystemVersion>
            <enclosure url="$DOWNLOAD_URL" $SIGNATURE type="application/octet-stream"/>
        </item>
    </channel>
</rss>
EOF

echo "==> Done: $DMG_PATH ($VERSION, build $BUILD)"
echo "Next: gh release create v$VERSION $DMG_PATH, then commit and push $APPCAST_PATH."
