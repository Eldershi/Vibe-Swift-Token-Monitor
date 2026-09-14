#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="${INSTALL_DIR:-$HOME/Applications}"
SOURCE="$ROOT/dist/Token Monitor Native Beta.app"
ID="local.tokenmonitor.native.beta"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :TokenMonitorReleaseVersion' "$SOURCE/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$SOURCE/Contents/Info.plist")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$SOURCE/Contents/Info.plist")"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-beta\.[1-9][0-9]*)?$ && "$BUILD" =~ ^[1-9][0-9]*$ ]]
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE/Contents/Info.plist")" = "$ID"
mkdir -p "$DEST"
APP="$DEST/Token Monitor Native Beta $VERSION ($BUILD).app"
# Only top-level active installations participate; archived rollback copies do not.
CURRENT="$(python3 - "$DEST" "$ID" <<'PY'
import plistlib
from pathlib import Path
import re
import sys
root = Path(sys.argv[1])
legacy = root / 'Token Monitor Native Beta.app'
if legacy.exists():
    print(legacy)
else:
    candidates = []
    for path in root.glob('Token Monitor Native Beta *.app'):
        if not re.fullmatch(r'Token Monitor Native Beta \d+\.\d+\.\d+(?:-beta\.[1-9]\d*)? \(\d+\)\.app', path.name):
            continue
        info = plistlib.loads((path / 'Contents/Info.plist').read_bytes())
        if info.get('CFBundleIdentifier') == sys.argv[2]:
            candidates.append((int(info['CFBundleVersion']), str(path)))
    if len(candidates) > 1:
        raise SystemExit('Multiple active Beta applications found; organize historical copies before installing.')
    if candidates:
        print(candidates[0][1])
PY
)"
if [[ -e "$APP" && "$APP" != "$CURRENT" ]]; then
  echo 'The versioned destination already exists and is not the current Beta application.' >&2
  exit 1
fi
STAGE_DIR="$(mktemp -d "$DEST/.token-monitor-beta-install.XXXXXX")"
trap 'rm -rf "$STAGE_DIR"' EXIT
STAGED="$STAGE_DIR/$(basename "$APP")"
ditto --noextattr "$SOURCE" "$STAGED"
xattr -cr "$STAGED"
codesign --verify --deep --strict "$STAGED"
"$STAGED/Contents/MacOS/TokenMonitorNative" --smoke-test
if [[ -n "$CURRENT" ]]; then
  test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$CURRENT/Contents/Info.plist")" = "$ID"
  swift "$ROOT/scripts/quit-beta.swift"
  SERVICE_STATUS="$("$CURRENT/Contents/MacOS/TokenMonitorNative" --beta-service-status)"
  if [[ "$SERVICE_STATUS" != "Beta service status: 3" && "$SERVICE_STATUS" != "Beta service status: 0" ]]; then
    "$CURRENT/Contents/MacOS/TokenMonitorNative" --beta-unregister
  fi
  OLD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :TokenMonitorReleaseVersion' "$CURRENT/Contents/Info.plist" 2>/dev/null || /usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$CURRENT/Contents/Info.plist")"
  OLD_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$CURRENT/Contents/Info.plist")"
  ARCHIVE="$DEST/Token Monitor 历史版本"
  mkdir -p "$ARCHIVE"
  BACKUP="$ARCHIVE/Token Monitor Native Beta $OLD_VERSION ($OLD_BUILD) - $(date +%Y%m%d-%H%M%S).app"
  test ! -e "$BACKUP"
  mv "$CURRENT" "$BACKUP"
fi
test ! -e "$APP"
mv "$STAGED" "$APP"
if ! "$APP/Contents/MacOS/TokenMonitorNative" --smoke-test; then
  ARCHIVE="$DEST/Token Monitor 历史版本"
  mkdir -p "$ARCHIVE"
  mv "$APP" "$ARCHIVE/Token Monitor Native Beta $VERSION ($BUILD) - failed-$(date +%Y%m%d-%H%M%S).app"
  if [[ -n "${BACKUP:-}" ]]; then mv "$BACKUP" "$CURRENT"; open "$CURRENT"; fi
  exit 1
fi
open "$APP"
printf 'Installed Beta: %s\n' "$APP"
