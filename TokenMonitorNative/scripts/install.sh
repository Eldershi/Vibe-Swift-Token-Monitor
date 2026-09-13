#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${INSTALL_DIR:-$HOME/Applications}"
SOURCE="${1:-$ROOT/dist/Token Monitor Native.app}"
TARGET="$DESTINATION/Token Monitor Native.app"
BACKUP="$DESTINATION/Token Monitor Native.previous.app"
STAGE="$DESTINATION/.Token Monitor Native.installing.app"
PLIST="$SOURCE/Contents/Info.plist"
[[ -f "$PLIST" ]] || { echo 'Build the app first.' >&2; exit 1; }
ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")"
[[ "$ID" == local.tokenmonitor.native ]] || { echo 'Unexpected application identity' >&2; exit 1; }
if [[ -d "$TARGET" ]]; then
  OLD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$TARGET/Contents/Info.plist")"
  NEW="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"
  [[ "$NEW" =~ ^[1-9][0-9]*$ && "$OLD" =~ ^[1-9][0-9]*$ && "$NEW" -gt "$OLD" ]] || { echo 'New BUILD_NUMBER must exceed the installed build. Use rollback.sh to restore.' >&2; exit 1; }
fi
mkdir -p "$DESTINATION"
[[ ! -e "$STAGE" ]] || { echo 'An unfinished install exists; inspect the .installing.app directory.' >&2; exit 1; }
ditto --noextattr "$SOURCE" "$STAGE"
xattr -cr "$STAGE"
codesign --verify --strict "$STAGE"
"$STAGE/Contents/MacOS/TokenMonitorNative" --smoke-test
# Only terminates this independent native UI. Never stops the collector or Hub.
swift "$ROOT/scripts/quit-native.swift"
SETTINGS="$HOME/Library/Application Support/Token Monitor Native/settings.json"
if [[ -f "$SETTINGS" ]]; then cp -p "$SETTINGS" "$SETTINGS.pre-upgrade-backup"; fi
if [[ -d "$BACKUP" ]]; then
  BACKUP_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BACKUP/Contents/Info.plist")"
  [[ "$BACKUP_ID" == local.tokenmonitor.native ]] || { echo 'Backup has unexpected identity' >&2; exit 1; }
  rm -rf "$BACKUP"
fi
if [[ -d "$TARGET" ]]; then mv "$TARGET" "$BACKUP"; fi
if ! mv "$STAGE" "$TARGET"; then
  [[ ! -d "$BACKUP" ]] || mv "$BACKUP" "$TARGET"
  exit 1
fi
if ! "$TARGET/Contents/MacOS/TokenMonitorNative" --smoke-test; then
  mv "$TARGET" "$DESTINATION/Token Monitor Native.failed-$(date +%s).app"
  [[ ! -d "$BACKUP" ]] || mv "$BACKUP" "$TARGET"
  echo 'Launch failed. Previous application restored.' >&2; exit 1
fi
printf 'Installed: %s\nOpen it from Finder. The Hub has not been stopped.\n' "$TARGET"
