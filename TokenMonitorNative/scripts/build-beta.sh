#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode-beta.app/Contents/Developer}"
python3 "$ROOT/scripts/prepare-beta.py" --verify
python3 "$ROOT/scripts/check-localization.py"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/token-monitor-beta-build.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
# Resource accessors embed the build directory; keep it outside the source checkout.
swift build --build-system native --package-path "$ROOT" --scratch-path "$STAGE/build" -c release
BIN="$(swift build --build-system native --package-path "$ROOT" --scratch-path "$STAGE/build" -c release --show-bin-path)"
# The native SwiftPM driver copies asset catalogs; compile them explicitly.
xcrun actool "$ROOT/Sources/TokenMonitorNative/Resources/Icons.xcassets" --compile "$BIN/TokenMonitorNative_TokenMonitorNative.bundle" --platform macosx --minimum-deployment-target 26.0 --target-device mac --output-format human-readable-text
cp "$ROOT/Resources/Symbols-Info.plist" "$BIN/TokenMonitorNative_TokenMonitorNative.bundle/Info.plist"
APP="$STAGE/Token Monitor Native Beta.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Library/LaunchAgents"
cp "$BIN/TokenMonitorNative" "$BIN/TokenMonitorBackend" "$APP/Contents/MacOS/"
xcrun strip -S "$APP/Contents/MacOS/TokenMonitorNative" "$APP/Contents/MacOS/TokenMonitorBackend"
python3 "$ROOT/scripts/prepare-beta.py" --stage "$APP"
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
codesign --force --sign "$SIGNING_IDENTITY" --identifier local.tokenmonitor.native.beta "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/TokenMonitorNative" --smoke-test
"$APP/Contents/MacOS/TokenMonitorBackend" --smoke-test
RELEASE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :TokenMonitorReleaseVersion' "$APP/Contents/Info.plist")"
BUILD_NUMBER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$APP/Contents/Info.plist")"
ARCHIVE="$ROOT/dist/Token-Monitor-Native-${RELEASE_VERSION}-${BUILD_NUMBER}-arm64.zip"
mkdir -p "$ROOT/dist"
rm -rf "$ROOT/dist/Token Monitor Native Beta.app"
ditto --noextattr "$APP" "$ROOT/dist/Token Monitor Native Beta.app"
# Desktop file providers may attach Finder metadata anywhere in the copied
# bundle. Clear extended attributes after copying, then validate that copy.
xattr -cr "$ROOT/dist/Token Monitor Native Beta.app"
codesign --verify --deep --strict "$ROOT/dist/Token Monitor Native Beta.app"
ditto -c -k --keepParent --norsrc "$APP" "$ARCHIVE"
printf 'Built independent Beta: %s\n' "$ROOT/dist/Token Monitor Native Beta.app"

UPDATE_KEY="${UPDATE_SIGNING_KEY:-$ROOT/../.local-private/update-signing/ed25519.seed}"
rm -f "$ROOT/dist/appcast.xml"
if [[ -f "$UPDATE_KEY" ]]; then
  python3 "$ROOT/scripts/make-update-feed.py" --app "$ROOT/dist/Token Monitor Native Beta.app" \
    --archive "$ARCHIVE" \
    --key "$UPDATE_KEY" --sign-tool "$STAGE/build/artifacts/sparkle/Sparkle/bin/sign_update"
else
  echo 'No update signing key: appcast.xml was not generated. Restore the original key before publishing updates.'
fi
