#!/usr/bin/env python3
"""Compile the Icon Composer source with Apple's asset tool into the main bundle."""
import argparse
import json
from pathlib import Path
import plistlib
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
ICON = ROOT / 'Resources/Token Monitor.icon'

def compile_icon(app: Path):
    resources = app / 'Contents/Resources'
    info_path = app / 'Contents/Info.plist'
    resources.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='token-app-icon-') as work:
        partial = Path(work) / 'partial.plist'
        subprocess.run(['xcrun', 'actool', str(ICON), '--compile', str(resources),
                        '--platform', 'macosx', '--minimum-deployment-target', '26.0',
                        '--target-device', 'mac', '--app-icon', ICON.stem,
                        '--output-partial-info-plist', str(partial),
                        '--output-format', 'human-readable-text'], check=True)
        metadata = plistlib.loads(partial.read_bytes())
        assert metadata.get('CFBundleIconName') == ICON.stem, metadata
        assert metadata.get('CFBundleIconFile') == ICON.stem, metadata
        info = plistlib.loads(info_path.read_bytes())
        info.update(metadata)
        info_path.write_bytes(plistlib.dumps(info))
    assert (resources / 'Assets.car').stat().st_size > 0
    assert (resources / (ICON.stem + '.icns')).read_bytes().startswith(b'icns')
    assets = json.loads(subprocess.check_output(['xcrun', 'assetutil', '--info', str(resources / 'Assets.car')]))
    appearances = {row.get('Appearance') for row in assets
                   if row.get('Name') == ICON.stem and row.get('AssetType') == 'IconImageStack'}
    assert {'NSAppearanceNameAqua', 'NSAppearanceNameDarkAqua', 'ISAppearanceTintable'} <= appearances, 'Missing layered icon appearances'
    print('App icon: Icon Composer catalog, ICNS fallback and main-bundle metadata verified')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--app', type=Path, required=True)
    compile_icon(parser.parse_args().app)
