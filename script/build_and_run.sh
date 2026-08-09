#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="mGBA"
BUNDLE_ID="io.mgba.mGBANative"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/src/platform/macos-native"
CORE_BUILD_DIR="$ROOT_DIR/build-native-core"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

cmake -S "$ROOT_DIR" -B "$CORE_BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Debug \
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
swift build --package-path "$PACKAGE_DIR"

BUILD_BINARY="$(swift build --package-path "$PACKAGE_DIR" --show-bin-path)/$APP_NAME"
"$ROOT_DIR/script/stage_macos_app.sh" "$BUILD_BINARY" "$APP_BUNDLE" -

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
