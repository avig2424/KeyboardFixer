#!/bin/bash
# Build KeyboardFixer and package it as a drag-to-install disk image.
# Produces build/KeyboardFixer-<version>.dmg — upload it to a GitHub Release.

set -euo pipefail
cd "$(dirname "$0")"

./build.sh

VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
DMG="build/KeyboardFixer-$VERSION.dmg"
STAGING="$(mktemp -d)/KeyboardFixer"

mkdir -p "$STAGING"
cp -R build/KeyboardFixer.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"   # drag target

rm -f "$DMG"
hdiutil create -volname "KeyboardFixer" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null

echo
echo "Created: $DMG"
