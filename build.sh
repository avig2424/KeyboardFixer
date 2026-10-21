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

SPARKLE="Vendor/Sparkle/Sparkle.framework"

rm -rf "$APP_DIR"
mkdir -p "$MACOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"

cp Info.plist "$CONTENTS/Info.plist"
cp Resources/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"
# Sparkle (automatic updates). ditto keeps the framework's symlinks intact.
ditto "$SPARKLE" "$CONTENTS/Frameworks/Sparkle.framework"

# Compile all Swift sources into a single binary.
swiftc \
    -O \
    -target arm64-apple-macos12 \
    -framework AppKit \
    -framework Carbon \
    -framework ServiceManagement \
    -F Vendor/Sparkle -framework Sparkle \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    -o "$MACOS/$APP_NAME" \
    Sources/*.swift

# Sign with the "KeyboardFixer Signing" certificate if this Mac has it, so
# every build has the same identity and macOS keeps the Accessibility
# permission across rebuilds and updates. Otherwise sign ad-hoc (works, but
# Accessibility has to be re-granted after each rebuild).
IDENTITY=$(security find-identity -p codesigning 2>/dev/null \
    | awk '/"KeyboardFixer Signing"/ { print $2; exit }')
SIGN_AS="${IDENTITY:--}"   # "-" means ad-hoc

# Sign inside-out: Sparkle's helpers, the framework, then the app, so every
# piece carries the same identity (Sparkle checks this before updating).
FW="$CONTENTS/Frameworks/Sparkle.framework/Versions/B"
for item in "$FW/XPCServices/Installer.xpc" "$FW/XPCServices/Downloader.xpc" \
            "$FW/Autoupdate" "$FW/Updater.app" "$CONTENTS/Frameworks/Sparkle.framework" \
            "$APP_DIR"; do
    # Keep Sparkle's own entitlements (its downloader is sandboxed).
    codesign --force --preserve-metadata=entitlements --sign "$SIGN_AS" "$item"
done

if [ -n "$IDENTITY" ]; then
    echo "Signed with KeyboardFixer Signing"
else
    echo "Signed ad-hoc (no KeyboardFixer Signing certificate found)"
fi

echo
echo "Built: $APP_DIR"
echo "Run with:  open $APP_DIR"
echo
echo "If macOS quarantines the bundle, clear it with:"
echo "  xattr -dr com.apple.quarantine $APP_DIR"
