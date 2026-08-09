#!/usr/bin/env bash
set -euo pipefail

APP_NAME="mGBA"
MIN_SYSTEM_VERSION="14.0"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/src/platform/macos-native"
CORE_BUILD_DIR="$ROOT_DIR/build-native-core-release"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
ARCHIVE="$RELEASE_DIR/mGBA-macOS-arm64.zip"

SIGNING_IDENTITY="${MGBA_SIGN_IDENTITY:-}"
if [[ -z "$SIGNING_IDENTITY" ]]; then
  SIGNING_IDENTITY="$(/usr/bin/security find-identity -p codesigning -v | /usr/bin/sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | /usr/bin/head -n 1)"
fi
if [[ -z "$SIGNING_IDENTITY" ]]; then
  echo "No Developer ID Application identity was found. Set MGBA_SIGN_IDENTITY explicitly." >&2
  exit 1
fi

cmake -S "$ROOT_DIR" -B "$CORE_BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET="$MIN_SYSTEM_VERSION" \
  -DBUILD_QT=OFF \
  -DBUILD_SDL=OFF \
  -DBUILD_SHARED=OFF \
  -DBUILD_STATIC=ON \
  -DBUILD_GL=OFF \
  -DBUILD_GLES2=OFF \
  -DBUILD_GLES3=OFF \
  -DBUILD_TEST=OFF \
  -DBUILD_SUITE=OFF \
  -DBUILD_CINEMA=OFF \
  -DBUILD_HEADLESS=OFF \
  -DBUILD_EXAMPLE=OFF \
  -DBUILD_PYTHON=OFF \
  -DBUILD_LIBRETRO=OFF \
  -DENABLE_DEBUGGERS=OFF \
  -DENABLE_GDB_STUB=OFF \
  -DENABLE_SCRIPTING=OFF \
  -DUSE_EDITLINE=OFF \
  -DUSE_FFMPEG=OFF \
  -DUSE_EPOXY=OFF \
  -DUSE_ELF=OFF \
  -DUSE_PNG=OFF \
  -DUSE_SQLITE3=OFF \
  -DUSE_LUA=OFF \
  -DUSE_DISCORD_RPC=OFF \
  -DUSE_FREETYPE=OFF \
  -DUSE_LIBZIP=OFF \
  -DUSE_LZMA=OFF

cmake --build "$CORE_BUILD_DIR" --target mgba -j 8
export MGBA_CORE_BUILD_DIR="build-native-core-release"
export MGBA_BUILD_VERSION="${MGBA_BUILD_VERSION:-$(git -C "$ROOT_DIR" rev-list --count HEAD)}"
swift build --package-path "$PACKAGE_DIR" -c release

BUILD_BINARY="$(swift build --package-path "$PACKAGE_DIR" -c release --show-bin-path)/$APP_NAME"
mkdir -p "$RELEASE_DIR"
"$ROOT_DIR/script/stage_macos_app.sh" "$BUILD_BINARY" "$APP_BUNDLE" "$SIGNING_IDENTITY"

rm -f "$ARCHIVE"
/usr/bin/ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"

/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
/usr/bin/file "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
echo "Release archive: $ARCHIVE"
