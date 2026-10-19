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

# Ad-hoc sign so the bundle has a code identity. Without this every
# rebuild looks like a brand-new binary to TCC and Accessibility breaks.
codesign --force --deep --sign - "$APP_DIR" 2>/dev/null

echo
echo "Built: $APP_DIR"
echo "Run with:  open $APP_DIR"
echo
echo "If macOS quarantines the bundle, clear it with:"
echo "  xattr -dr com.apple.quarantine $APP_DIR"
