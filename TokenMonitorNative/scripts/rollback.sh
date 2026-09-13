#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DESTINATION="${INSTALL_DIR:-$HOME/Applications}"
TARGET="$DESTINATION/Token Monitor Native.app"
BACKUP="$DESTINATION/Token Monitor Native.previous.app"
[[ -d "$BACKUP" ]] || { echo 'No previous application available.' >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$BACKUP/Contents/Info.plist")" == local.tokenmonitor.native ]] || exit 1
codesign --verify --strict "$BACKUP"
"$BACKUP/Contents/MacOS/TokenMonitorNative" --smoke-test
swift "$ROOT/scripts/quit-native.swift"
if [[ -d "$TARGET" ]]; then mv "$TARGET" "$DESTINATION/Token Monitor Native.restored-from-$(date +%s).app"; fi
mv "$BACKUP" "$TARGET"
SETTINGS="$HOME/Library/Application Support/Token Monitor Native/settings.json"
if [[ -f "$SETTINGS.pre-upgrade-backup" ]]; then
  [[ ! -f "$SETTINGS" ]] || cp -p "$SETTINGS" "$SETTINGS.before-rollback"
  cp -p "$SETTINGS.pre-upgrade-backup" "$SETTINGS"
fi
printf 'Restored: %s\nThe Keychain entry and Hub are unchanged.\n' "$TARGET"
