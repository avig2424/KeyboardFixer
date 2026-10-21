#!/bin/bash
# Build KeyboardFixer and package a release:
#   build/release/KeyboardFixer-<version>.dmg   drag-to-install disk image
#   build/release/appcast.xml                   update feed for Sparkle
# Upload both to a GitHub Release tagged v<version>. Installed apps read the
# feed from the latest release and offer the update.
#
# Before each release, raise CFBundleShortVersionString (e.g. 2.1 -> 2.2) and
# CFBundleVersion (e.g. 3 -> 4) in Info.plist; Sparkle compares CFBundleVersion.

set -euo pipefail
cd "$(dirname "$0")"

REPO="avig2424/KeyboardFixer"

./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
OUT="build/release"
DMG="$OUT/KeyboardFixer-$VERSION.dmg"
STAGING="$(mktemp -d)/KeyboardFixer"

rm -rf "$OUT"
mkdir -p "$OUT" "$STAGING"
cp -R build/KeyboardFixer.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"   # drag target
hdiutil create -volname "KeyboardFixer" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

# Sign the DMG with the update key in your keychain and write the feed.
Vendor/Sparkle/bin/generate_appcast \
    --download-url-prefix "https://github.com/$REPO/releases/download/v$VERSION/" \
    "$OUT"

echo
echo "Release v$VERSION ready in $OUT:"
ls -1 "$OUT"
echo
echo "Next: https://github.com/$REPO/releases/new"
echo "  Tag: v$VERSION   Attach: both files above   Then: Publish release"
