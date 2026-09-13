#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${INSTALL_DIR:-$HOME/Applications}"
APP="$DEST/Token Monitor Native Beta.app"
SOURCE="$ROOT/dist/Token Monitor Native Beta.app"
ID="local.tokenmonitor.native.beta"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE/Contents/Info.plist")" = "$ID"
mkdir -p "$DEST"
STAGED="$DEST/.Token Monitor Native Beta.installing.app"
if [[ -e "$STAGED" ]]; then
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$STAGED/Contents/Info.plist")" = "$ID"
  rm -rf "$STAGED"
fi
ditto --noextattr "$SOURCE" "$STAGED"
xattr -cr "$STAGED"
codesign --verify --deep --strict "$STAGED"
"$STAGED/Contents/MacOS/TokenMonitorNative" --smoke-test
if [[ -e "$APP" ]]; then
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$APP/Contents/Info.plist")" = "$ID"
  swift "$ROOT/scripts/quit-beta.swift"
  SERVICE_STATUS="$("$APP/Contents/MacOS/TokenMonitorNative" --beta-service-status)"
  if [[ "$SERVICE_STATUS" != "Beta service status: 3" && "$SERVICE_STATUS" != "Beta service status: 0" ]]; then
    "$APP/Contents/MacOS/TokenMonitorNative" --beta-unregister
  fi
  BACKUP="$DEST/Token Monitor Native Beta.previous.$(date +%Y%m%d-%H%M%S).app"
  mv "$APP" "$BACKUP"
fi
mv "$STAGED" "$APP"
if ! "$APP/Contents/MacOS/TokenMonitorNative" --smoke-test; then
  mv "$APP" "$DEST/Token Monitor Native Beta.failed.$(date +%Y%m%d-%H%M%S).app"
  if [[ -n "${BACKUP:-}" ]]; then mv "$BACKUP" "$APP"; open "$APP"; fi
  exit 1
fi
open "$APP"
printf 'Installed Beta only: %s\n' "$APP"
