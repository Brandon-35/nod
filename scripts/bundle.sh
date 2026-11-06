#!/bin/bash
# Wraps the build into dist/Nod.app. Usage: scripts/bundle.sh [version]
# It must be a .app with NSMotionUsageDescription: a bare binary aborts in the Motion permission check.
# Signing: set NOD_SIGN_IDENTITY to a codesign identity; the default is ad-hoc ("-"), which is fine for local use but
# makes macOS forget the Motion and Accessibility grants after every rebuild.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION="${1:-0.1.0}"
BUILD="$(git rev-list --count HEAD 2>/dev/null || echo 1)"
CONFIG="${NOD_CONFIG:-release}"
RES="Sources/Nod/Resources"
APP="dist/Nod.app"

swift build -c "$CONFIG" --product Nod
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"

/bin/rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/Nod" "$APP/Contents/MacOS/Nod"
sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD/" "$RES/Info.plist.template" > "$APP/Contents/Info.plist"
plutil -lint -s "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
if [[ -d "$RES/AppIcon.iconset" ]]; then
    iconutil -c icns "$RES/AppIcon.iconset" -o "$APP/Contents/Resources/Nod.icns"
    /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string Nod" "$APP/Contents/Info.plist"
fi

xattr -cr "$APP"
IDENTITY="${NOD_SIGN_IDENTITY:--}"
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" --entitlements "$RES/Nod.entitlements" "$APP"
codesign --verify --deep --strict "$APP"
echo "$APP $VERSION ($BUILD) signed: $IDENTITY"
