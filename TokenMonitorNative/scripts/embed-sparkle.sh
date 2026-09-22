#!/bin/bash
set -euo pipefail
APP="$1"
ARTIFACT="$2"
FRAMEWORK="$ARTIFACT/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
test -d "$FRAMEWORK"
mkdir -p "$APP/Contents/Frameworks"
ditto "$FRAMEWORK" "$APP/Contents/Frameworks/Sparkle.framework"
# Preserve Sparkle's symlinks and sign nested code from the inside out.
python3 - "$APP/Contents/Frameworks/Sparkle.framework" "${SIGNING_IDENTITY:--}" <<'PY'
import pathlib, subprocess, sys
root = pathlib.Path(sys.argv[1]); identity = sys.argv[2]
bundles = sorted([p for p in root.rglob('*') if p.is_dir() and not p.is_symlink() and p.suffix in ('.app', '.xpc')], key=lambda p: len(p.parts), reverse=True)
for p in root.rglob('*'):
    if not p.is_file() or p.is_symlink(): continue
    kind = subprocess.check_output(['file', '-b', str(p)], text=True)
    if 'Mach-O' in kind:
        architectures = subprocess.check_output(['lipo', '-archs', str(p)], text=True).split()
        if len(architectures) > 1:
            subprocess.run(['lipo', str(p), '-thin', 'arm64', '-output', str(p)], check=True)
        subprocess.run(['codesign', '--force', '--sign', identity, str(p)], check=True)
for p in bundles + [root]: subprocess.run(['codesign', '--force', '--sign', identity, str(p)], check=True)
PY
mkdir -p "$APP/Contents/Resources/Licenses"
cp "$ARTIFACT/LICENSE" "$APP/Contents/Resources/Licenses/Sparkle.txt"
