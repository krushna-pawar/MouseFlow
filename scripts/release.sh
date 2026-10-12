#!/usr/bin/env bash
# Builds a Release archive of MouseFlow and packages it as a DMG.
#
# The app is signed with the project's automatic signing (Apple Development) and is not
# notarized, so users must allow it once under System Settings › Privacy & Security.
#
# Usage: scripts/release.sh
# Output: build/release/MouseFlow-<version>.dmg

set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="MouseFlow"
RELEASE_DIR="build/release"
ARCHIVE_PATH="$RELEASE_DIR/$APP_NAME.xcarchive"
STAGING_DIR="$RELEASE_DIR/dmg"

rm -rf "$RELEASE_DIR"
mkdir -p "$STAGING_DIR"

echo "==> Archiving $APP_NAME (Release)"
xcodebuild archive \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -destination "generic/platform=macOS" \
    -archivePath "$ARCHIVE_PATH" \
    -quiet

APP_PATH="$ARCHIVE_PATH/Products/Applications/$APP_NAME.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")
DMG_PATH="$RELEASE_DIR/$APP_NAME-$VERSION.dmg"

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

echo "==> Done: $DMG_PATH"
