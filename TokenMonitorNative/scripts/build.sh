#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${VERSION:-0.4.1}"
BUILD_NUMBER="${BUILD_NUMBER:-21}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ || ! "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]]; then
  echo 'VERSION must be x.y.z and BUILD_NUMBER a positive integer' >&2; exit 1
fi
if [[ -z "${DEVELOPER_DIR:-}" && -d /Applications/Xcode-beta.app ]]; then
  export DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer
fi
# The native SPM driver respects Package.swift's macOS 26 deployment target.
swift build --build-system native --package-path "$ROOT" -c release
BIN="$(swift build --build-system native --package-path "$ROOT" -c release --show-bin-path)"
# The native SwiftPM driver copies asset catalogs; compile them explicitly.
xcrun actool "$ROOT/Sources/TokenMonitorNative/Resources/Icons.xcassets" --compile "$BIN/TokenMonitorNative_TokenMonitorNative.bundle" --platform macosx --minimum-deployment-target 26.0 --target-device mac --output-format human-readable-text
cp "$ROOT/Resources/Symbols-Info.plist" "$BIN/TokenMonitorNative_TokenMonitorNative.bundle/Info.plist"
BUILD_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/token-monitor-build.XXXXXX")"
trap 'rm -rf "$BUILD_STAGE"' EXIT
APP="$BUILD_STAGE/Token Monitor Native.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/TokenMonitorNative" "$APP/Contents/MacOS/TokenMonitorNative"
cp "$ROOT/Resources/Info.plist" "$APP/Contents/Info.plist"
# SwiftPM resources include the unmodified, exported Apple symbol catalog.
ditto "$BIN/TokenMonitorNative_TokenMonitorNative.bundle" "$APP/Contents/Resources/TokenMonitorNative_TokenMonitorNative.bundle"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP/Contents/Info.plist"
# Local ad-hoc signature. Supply SIGNING_IDENTITY later for a stable signing certificate.
xattr -cr "$APP"
codesign --force --sign "${SIGNING_IDENTITY:--}" --identifier local.tokenmonitor.native "$APP"
codesign --verify --strict "$APP"
"$APP/Contents/MacOS/TokenMonitorNative" --smoke-test
# Sign outside synced folders: Finder/iCloud may add attributes while signing.
mkdir -p "$ROOT/dist"
ditto --noextattr "$APP" "$ROOT/dist/Token Monitor Native.app"
printf 'Built: %s\n' "$ROOT/dist/Token Monitor Native.app"
