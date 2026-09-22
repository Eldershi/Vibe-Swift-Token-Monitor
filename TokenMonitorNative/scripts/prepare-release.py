#!/usr/bin/env python3
"""Stage the native macOS release; no external runtime is downloaded."""
import argparse
import json
import pathlib
import plistlib
import re
import shutil

ROOT = pathlib.Path(__file__).resolve().parents[1]
PACKAGE = json.loads((ROOT / 'release.json').read_text())

def verify():
    if not re.fullmatch(r'\d+\.\d+\.\d+', PACKAGE['version']) or not isinstance(PACKAGE['buildNumber'], int) or PACKAGE['buildNumber'] <= 0:
        raise RuntimeError('Unexpected release metadata')
    version = PACKAGE['version']
    for path, expected in [
        ('Sources/NativeBackendCore/NativeSnapshot.swift', '"agentVersion": "' + version + '"'),
        ('Sources/TokenMonitorBackend/NativeService.swift', '"version": "' + version + '"'),
        ('Sources/TokenMonitorBackend/NativeService.swift', '"TokenMonitor/' + version + '"'),
    ]:
        if expected not in (ROOT / path).read_text():
            raise RuntimeError('Release metadata differs from Swift backend: ' + path)
    source = ROOT / 'Sources/TokenMonitorBackend/NativeService.swift'
    if not source.exists():
        raise RuntimeError('Native backend is missing')


def stage(app):
    resources = app / 'Contents/Resources'
    resources.mkdir(parents=True, exist_ok=True)
    shutil.copy2(ROOT / 'Resources/DEVICE-ICON-CREDITS.md', resources / 'DEVICE-ICON-CREDITS.md')
    shutil.copy2(ROOT / 'THIRD_PARTY_NOTICES.md', resources / 'THIRD_PARTY_NOTICES.md')
    with (ROOT / 'Resources/Info.plist').open('rb') as source:
        info = plistlib.load(source)
    info.update(CFBundleIdentifier='local.tokenmonitor.native.beta2',
                CFBundleName='Token Monitor',
                CFBundleDisplayName='Token Monitor',
                CFBundleShortVersionString=PACKAGE['version'], CFBundleVersion=str(PACKAGE['buildNumber']),
                TokenMonitorReleaseVersion=PACKAGE['version'])
    # Separate feed prevents pre-0.7 clients from replacing a different app identity.
    info.update(SUPublicEDKey=(ROOT / 'Resources/UpdatePublicKey.txt').read_text().strip(),
                SUFeedURL='https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/latest/download/appcast-native.xml',
                SURequireSignedFeed=True, SUVerifyUpdateBeforeExtraction=True)
    shutil.copy2(ROOT / 'Resources/TOKEN-MONITOR-LICENSE', resources / 'TOKEN-MONITOR-LICENSE')
    info.update(SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False,
                SUAllowsAutomaticUpdates=False, SUSendProfileInfo=False)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    agent = {'Label': 'local.tokenmonitor.native.beta2.backend',
             'BundleProgram': 'Contents/MacOS/TokenMonitorBackend',
             'RunAtLoad': True, 'KeepAlive': {'SuccessfulExit': False},
             'ThrottleInterval': 10, 'ProcessType': 'Standard', 'Umask': 0o077}
    (app / 'Contents/Library/LaunchAgents/local.tokenmonitor.native.beta2.backend.plist').write_bytes(plistlib.dumps(agent))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--stage', type=pathlib.Path)
    args = parser.parse_args()
    if args.verify or args.stage: verify()
    if args.stage: stage(args.stage)
