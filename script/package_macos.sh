#!/usr/bin/env bash
set -euo pipefail

APP_NAME="LaserStudio"
BUNDLE_ID="studio.laserstudio.app"
APP_VERSION="${APP_VERSION:-1.0.0}"
MIN_SYSTEM_VERSION="14.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
STAGING_DIR="$DIST_DIR/.dmg-staging"
APP_BUNDLE="$STAGING_DIR/$APP_NAME.app"
DMG_PATH="$DIST_DIR/$APP_NAME-macOS.dmg"

cd "$ROOT_DIR"
"$ROOT_DIR/script/create_app_icon.sh"
swift build -c release
BUILD_BINARY="$(swift build -c release --show-bin-path)/$APP_NAME"

rm -rf "$STAGING_DIR"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BUILD_BINARY" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
chmod 755 "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat >"$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>$APP_NAME</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundleIconFile</key><string>AppIcon.icns</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>1</string>
<key>LSMinimumSystemVersion</key><string>$MIN_SYSTEM_VERSION</string>
<key>NSCameraUsageDescription</key><string>LaserStudio uses the camera to preview the work area for positioning designs.</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST

cat >"$STAGING_DIR/Install Instructions.txt" <<'TXT'
LaserStudio for macOS

1. Drag LaserStudio.app to the Applications folder.
2. Open LaserStudio from Applications.
3. If macOS blocks the first launch because the app is not signed or notarized,
   Control-click LaserStudio.app, choose Open, then confirm Open.

Requires macOS 14 or later.
TXT
ln -s /Applications "$STAGING_DIR/Applications"

plutil -lint "$APP_BUNDLE/Contents/Info.plist"
rm -f "$DMG_PATH"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING_DIR" -format UDZO -ov "$DMG_PATH"
hdiutil verify "$DMG_PATH"
rm -rf "$STAGING_DIR"

echo "Created $DMG_PATH"
