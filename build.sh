#!/bin/bash
# Build KeyboardFixer.app — no Xcode project required.
# Produces build/KeyboardFixer.app

set -euo pipefail

cd "$(dirname "$0")"

APP_NAME="KeyboardFixer"
BUILD_DIR="build"
APP_DIR="$BUILD_DIR/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$CONTENTS/Resources"

cp Info.plist "$CONTENTS/Info.plist"
cp Resources/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"

# Compile all Swift sources into a single binary.
swiftc \
    -O \
    -target arm64-apple-macos12 \
    -framework AppKit \
    -framework Carbon \
    -framework ServiceManagement \
    -o "$MACOS/$APP_NAME" \
    Sources/*.swift

# Sign with the "KeyboardFixer Signing" certificate if this Mac has it, so
# every build has the same identity and macOS keeps the Accessibility
# permission across rebuilds and updates. Otherwise sign ad-hoc (works, but
# Accessibility has to be re-granted after each rebuild).
IDENTITY=$(security find-identity -p codesigning 2>/dev/null \
    | awk '/"KeyboardFixer Signing"/ { print $2; exit }')
if [ -n "$IDENTITY" ]; then
    codesign --force --deep --sign "$IDENTITY" "$APP_DIR"
    echo "Signed with KeyboardFixer Signing"
else
    codesign --force --deep --sign - "$APP_DIR" 2>/dev/null
    echo "Signed ad-hoc (no KeyboardFixer Signing certificate found)"
fi

echo
echo "Built: $APP_DIR"
echo "Run with:  open $APP_DIR"
echo
echo "If macOS quarantines the bundle, clear it with:"
echo "  xattr -dr com.apple.quarantine $APP_DIR"
