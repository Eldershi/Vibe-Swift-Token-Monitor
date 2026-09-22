#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-$(xcode-select -p)}"
[[ "$(uname -m)" == arm64 ]] || { echo "This release targets Apple Silicon." >&2; exit 1; }
python3 "$ROOT/scripts/prepare-release.py" --verify
python3 "$ROOT/scripts/check-localization.py"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/token-monitor-beta-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
# Resource accessors embed the build directory; keep it outside the source checkout.
swift build --build-system native --package-path "$ROOT" --scratch-path "$STAGE/build" -c release
BIN="$(swift build --build-system native --package-path "$ROOT" --scratch-path "$STAGE/build" -c release --show-bin-path)"
# The native SwiftPM driver copies asset catalogs; compile them explicitly.
xcrun actool "$ROOT/Sources/TokenMonitorNative/Resources/Icons.xcassets" --compile "$BIN/TokenMonitorNative_TokenMonitorNative.bundle" --platform macosx --minimum-deployment-target 26.0 --target-device mac --output-format human-readable-text
rm -rf "$BIN/TokenMonitorNative_TokenMonitorNative.bundle/Icons.xcassets"
cp "$ROOT/Resources/Symbols-Info.plist" "$BIN/TokenMonitorNative_TokenMonitorNative.bundle/Info.plist"
APP="$STAGE/Token Monitor.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
cp "$BIN/TokenMonitorNative" "$BIN/TokenMonitorBackend" "$APP/Contents/MacOS/"
xcrun strip -x "$APP/Contents/MacOS/TokenMonitorNative" "$APP/Contents/MacOS/TokenMonitorBackend"
python3 "$ROOT/scripts/prepare-release.py" --stage "$APP"
# SwiftPM resources include the unmodified, exported Apple symbol catalog.
ditto "$BIN/TokenMonitorNative_TokenMonitorNative.bundle" "$APP/Contents/Resources/TokenMonitorNative_TokenMonitorNative.bundle"
ditto "$BIN/TokenMonitorNative_MonitorCore.bundle" "$APP/Contents/Resources/TokenMonitorNative_MonitorCore.bundle"
# Main-bundle metadata and localized privacy descriptions for system language selection.
cp -R "$ROOT/Resources/en.lproj" "$ROOT/Resources/zh-Hans.lproj" "$APP/Contents/Resources/"
python3 "$ROOT/scripts/compile-app-icon.py" --app "$APP"
xattr -cr "$APP"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
# Sign every nested Mach-O before sealing the enclosing application.
while IFS= read -r -d '' binary; do
  if file -b "$binary" | /usr/bin/grep -q 'Mach-O'; then
    codesign --force --sign "$SIGNING_IDENTITY" "$binary"
  fi
done < <(find "$APP/Contents" -type f -print0)
bash "$ROOT/scripts/embed-sparkle.sh" "$APP" "$STAGE/build/artifacts/sparkle/Sparkle"
codesign --force --sign "$SIGNING_IDENTITY" --identifier local.tokenmonitor.native.beta2 "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/TokenMonitorNative" --smoke-test
"$APP/Contents/MacOS/TokenMonitorBackend" --smoke-test
RELEASE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :TokenMonitorReleaseVersion' "$APP/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
ARCHIVE="$ROOT/dist/Token-Monitor-Native-${RELEASE_VERSION}-${BUILD_NUMBER}-arm64.zip"
mkdir -p "$ROOT/dist"
# The distributable is created from the clean, signed staging directory. Verify
# the exact ZIP after extraction outside File Provider-managed Desktop folders.
ditto -c -k --zlibCompressionLevel 9 --keepParent --norsrc "$APP" "$ARCHIVE"
mkdir "$STAGE/verified"
ditto -x -k "$ARCHIVE" "$STAGE/verified"
codesign --verify --deep --strict "$STAGE/verified/Token Monitor.app"
rm -rf "$ROOT/dist/Token Monitor.app"
ditto --noextattr "$APP" "$ROOT/dist/Token Monitor.app"
# This convenience copy can receive Finder metadata again immediately. Its
# provider-managed attributes must not replace verification of the actual ZIP.
xattr -cr "$ROOT/dist/Token Monitor.app"
xattr -dr com.apple.FinderInfo "$ROOT/dist/Token Monitor.app" 2>/dev/null || true
xattr -dr 'com.apple.fileprovider.fpfs#P' "$ROOT/dist/Token Monitor.app" 2>/dev/null || true
printf 'Built Token Monitor: %s\n' "$ROOT/dist/Token Monitor.app"

KEY="${UPDATE_SIGNING_KEY:-$ROOT/../.local-private/update-signing/ed25519.seed}"
rm -f "$ROOT/dist/appcast-native.xml"
if [[ -f "$KEY" ]]; then
  python3 "$ROOT/scripts/make-update-feed.py" --app "$APP" --archive "$ARCHIVE" --key "$KEY" --sign-tool "$STAGE/build/artifacts/sparkle/Sparkle/bin/sign_update"
fi
