#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 3 ]]; then
  echo "usage: $0 <binary> <app-bundle> <signing-identity>" >&2
  exit 2
fi

SOURCE_BINARY="$1"
APP_BUNDLE="$2"
SIGNING_IDENTITY="$3"
APP_NAME="mGBA"
BUNDLE_ID="io.mgba.mGBANative"
MIN_SYSTEM_VERSION="14.0"
MARKETING_VERSION="${MGBA_MARKETING_VERSION:-0.11.0}"
BUILD_VERSION="${MGBA_BUILD_VERSION:-1}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
RESOURCE_BUNDLE_NAME="mGBANative_mGBAApp.bundle"
SOURCE_RESOURCE_BUNDLE="$(dirname "$SOURCE_BINARY")/$RESOURCE_BUNDLE_NAME"

if [[ ! -f "$SOURCE_BINARY" || "$APP_BUNDLE" != */mGBA.app ]]; then
  echo "Refusing to stage an invalid binary or app-bundle target." >&2
  exit 2
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$SOURCE_BINARY" "$APP_BINARY"
cp "$ROOT_DIR/res/mgba.icns" "$APP_RESOURCES/mgba.icns"
if [[ -d "$SOURCE_RESOURCE_BUNDLE" ]]; then
  /usr/bin/ditto --norsrc \
    "$SOURCE_RESOURCE_BUNDLE" \
    "$APP_RESOURCES/$RESOURCE_BUNDLE_NAME"
fi
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>mGBA</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleIconFile</key>
  <string>mgba.icns</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$MARKETING_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_VERSION</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.games</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Game Boy ROM</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>CFBundleTypeIconFile</key>
      <string>mgba.icns</string>
      <key>CFBundleTypeExtensions</key>
      <array>
        <string>gba</string>
        <string>gb</string>
        <string>gbc</string>
        <string>zip</string>
      </array>
    </dict>
  </array>
</dict>
</plist>
PLIST

if [[ "$SIGNING_IDENTITY" == "-" ]]; then
  /usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"
else
  /usr/bin/codesign \
    --force \
    --deep \
    --options runtime \
    --timestamp \
    --sign "$SIGNING_IDENTITY" \
    "$APP_BUNDLE"
fi

/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
/usr/bin/plutil -lint "$INFO_PLIST"
