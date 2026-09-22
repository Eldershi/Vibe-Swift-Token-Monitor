#!/bin/bash
# Optional compact download. The application itself is identical to the ZIP.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$ROOT/dist/Token Monitor.app}"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :TokenMonitorReleaseVersion' "$APP/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/token-monitor-dmg.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir "$WORK/payload"
ditto --noextattr "$APP" "$WORK/payload/$(basename "$APP")"
xattr -cr "$WORK/payload"
codesign --verify --deep --strict "$WORK/payload/$(basename "$APP")"
ln -s /Applications "$WORK/payload/Applications"
IMAGE="$ROOT/dist/Token-Monitor-Native-${VERSION}-${BUILD}-arm64.dmg"
hdiutil create -srcfolder "$WORK/payload" -volname "Token Monitor $VERSION" -fs HFS+ -format ULMO -ov "$IMAGE"
hdiutil verify "$IMAGE"
printf 'Built LZMA disk image: %s\n' "$IMAGE"
