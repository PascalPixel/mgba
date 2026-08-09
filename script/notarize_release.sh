#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_BUNDLE="$ROOT_DIR/dist/release/mGBA.app"
ARCHIVE="$ROOT_DIR/dist/release/mGBA-macOS-arm64.zip"
NOTARY_PROFILE="${MGBA_NOTARY_PROFILE:-}"

if [[ -z "$NOTARY_PROFILE" ]]; then
  echo "Set MGBA_NOTARY_PROFILE to a notarytool keychain profile." >&2
  exit 2
fi
if [[ ! -d "$APP_BUNDLE" || ! -f "$ARCHIVE" ]]; then
  echo "Run ./script/package_release.sh before notarizing." >&2
  exit 2
fi

xcrun notarytool submit "$ARCHIVE" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"

rm -f "$ARCHIVE"
/usr/bin/ditto -c -k --norsrc --keepParent "$APP_BUNDLE" "$ARCHIVE"
/usr/sbin/spctl -a -vv --type execute "$APP_BUNDLE"
echo "Notarized archive: $ARCHIVE"
