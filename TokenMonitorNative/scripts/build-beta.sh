#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
python3 "$ROOT/scripts/prepare-beta.py" --verify
swift build --build-system native --package-path "$ROOT" -c release
BIN="$(swift build --build-system native --package-path "$ROOT" -c release --show-bin-path)"
# The native SwiftPM driver copies asset catalogs; compile them explicitly.
xcrun actool "$ROOT/Sources/TokenMonitorNative/Resources/Icons.xcassets" --compile "$BIN/TokenMonitorNative_TokenMonitorNative.bundle" --platform macosx --minimum-deployment-target 26.0 --target-device mac --output-format human-readable-text
cp "$ROOT/Resources/Symbols-Info.plist" "$BIN/TokenMonitorNative_TokenMonitorNative.bundle/Info.plist"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/token-monitor-beta-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
APP="$STAGE/Token Monitor Native Beta.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
cp "$BIN/TokenMonitorNative" "$BIN/TokenMonitorBackend" "$APP/Contents/MacOS/"
python3 "$ROOT/scripts/prepare-beta.py" --stage "$APP"
# SwiftPM resources include the unmodified, exported Apple symbol catalog.
ditto "$BIN/TokenMonitorNative_TokenMonitorNative.bundle" "$APP/Contents/Resources/TokenMonitorNative_TokenMonitorNative.bundle"
xattr -cr "$APP"
SIGNING_IDENTITY="${SIGNING_IDENTITY:--}"
# Sign every nested Mach-O before sealing the enclosing application.
while IFS= read -r -d '' binary; do
  if file -b "$binary" | /usr/bin/grep -q 'Mach-O'; then
    codesign --force --sign "$SIGNING_IDENTITY" "$binary"
  fi
done < <(find "$APP/Contents" -type f -print0)
codesign --force --sign "$SIGNING_IDENTITY" --identifier local.tokenmonitor.native.beta "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/TokenMonitorNative" --smoke-test
"$APP/Contents/MacOS/TokenMonitorBackend" --smoke-test
mkdir -p "$ROOT/dist"
rm -rf "$ROOT/dist/Token Monitor Native Beta.app"
ditto --noextattr "$APP" "$ROOT/dist/Token Monitor Native Beta.app"
ditto -c -k --keepParent --norsrc "$APP" "$ROOT/dist/Token-Monitor-Native-0.5.0-arm64.zip"
printf 'Built independent Beta: %s\n' "$ROOT/dist/Token Monitor Native Beta.app"
