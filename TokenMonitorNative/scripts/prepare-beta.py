#!/usr/bin/env python3
"""Reproducible runtime staging; does not read an installed Token Monitor app."""
import argparse
import hashlib
import json
import pathlib
import plistlib
import shutil
import subprocess
import tarfile
import tempfile
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
BACKEND = ROOT / 'Backend'
PIN = json.loads((BACKEND / 'runtime-pin.json').read_text())['node']
TOK = json.loads((BACKEND / 'tokscale-pin.json').read_text())

def download(url, target, digest):
    with urllib.request.urlopen(url, timeout=120) as response:
        data = response.read()
    if hashlib.sha256(data).hexdigest() != digest:
        raise RuntimeError('download checksum mismatch')
    target.write_bytes(data)

def prepare():
    runtime = BACKEND / 'runtime'
    runtime.mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='token-monitor-beta-deps-') as temp:
        archive = pathlib.Path(temp) / PIN['archive']
        download(PIN['url'], archive, PIN['sha256'])
        with tarfile.open(archive) as tar:
            prefix = PIN['archive'].removesuffix('.tar.gz')
            for source, target in [('bin/node', 'node'), ('LICENSE', 'NODE-LICENSE')]:
                (runtime / target).write_bytes(tar.extractfile(f'{prefix}/{source}').read())
        (runtime / 'node').chmod(0o755)
    subprocess.run(['npm', 'ci', '--ignore-scripts', '--no-audit', '--no-fund'], cwd=BACKEND, check=True)
    pin = TOK['platforms']['darwin-arm64']
    binary = BACKEND / 'node_modules/@tokscale/cli-darwin-arm64/bin/tokscale'
    download(f"https://github.com/{TOK['releaseRepo']}/releases/download/{TOK['releaseTag']}/{pin['asset']}", binary, pin['sha256'])
    binary.chmod(0o755)

def verify():
    runtime = BACKEND / 'runtime/node'
    version = subprocess.check_output([str(runtime), '--version'], text=True).strip()
    if version != 'v' + PIN['version']:
        raise RuntimeError('Node version mismatch')
    binary = BACKEND / 'node_modules/@tokscale/cli-darwin-arm64/bin/tokscale'
    if hashlib.sha256(binary.read_bytes()).hexdigest() != TOK['platforms']['darwin-arm64']['sha256']:
        raise RuntimeError('Tokscale checksum mismatch; run prepare-beta.py --download')
    subprocess.run([str(runtime), '-e', "require('./vendor/src/agent/runtime'); require('./vendor/src/hub/server')"], cwd=BACKEND, check=True)

def stage(app):
    resources = app / 'Contents/Resources/Backend'
    resources.mkdir(parents=True, exist_ok=True)
    for directory in ['vendor', 'node_modules', 'runtime']:
        shutil.copytree(BACKEND / directory, resources / directory, ignore=shutil.ignore_patterns('.DS_Store'))
    for file in ['main.cjs', 'hub-sync.cjs', 'hub-http.cjs', 'native-keychain.cjs', 'hub-credential.cjs', 'package.json', 'package-lock.json', 'runtime-pin.json', 'tokscale-pin.json', 'UPSTREAM.md', 'TOKSCALE-LICENSE']:
        shutil.copy2(BACKEND / file, resources / file)
    shutil.copy2(ROOT / 'THIRD_PARTY_NOTICES.md', app / 'Contents/Resources/THIRD_PARTY_NOTICES.md')
    shutil.copy2(ROOT / 'Resources/DEVICE-ICON-CREDITS.md', app / 'Contents/Resources/DEVICE-ICON-CREDITS.md')
    with (ROOT / 'Resources/Info.plist').open('rb') as source:
        info = plistlib.load(source)
    info.update(CFBundleIdentifier='local.tokenmonitor.native.beta', CFBundleName='Token Monitor Native Beta',
                CFBundleDisplayName='Token Monitor Native Beta', CFBundleShortVersionString='0.5.2', CFBundleVersion='35',
                TokenMonitorReleaseVersion='0.5.2')
    info.update(SUPublicEDKey=(ROOT / 'Resources/UpdatePublicKey.txt').read_text().strip(),
                SUFeedURL='https://github.com/Eldershi/Vibe-Swift-Token-Monitor/releases/latest/download/appcast.xml',
                SUEnableAutomaticChecks=False, SUAutomaticallyUpdate=False, SUAllowsAutomaticUpdates=False,
                SUSendProfileInfo=False, SUVerifyUpdateBeforeExtraction=True, SURequireSignedFeed=True,
                SUEnableJavaScript=False)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    agent = {'Label': 'local.tokenmonitor.native.beta.backend',
             'BundleProgram': 'Contents/MacOS/TokenMonitorBackend',
             'RunAtLoad': True, 'KeepAlive': {'SuccessfulExit': False},
             'ThrottleInterval': 10, 'ProcessType': 'Standard', 'Umask': 0o077}
    (app / 'Contents/Library/LaunchAgents/local.tokenmonitor.native.beta.backend.plist').write_bytes(plistlib.dumps(agent))

if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('--download', action='store_true')
    parser.add_argument('--verify', action='store_true')
    parser.add_argument('--stage', type=pathlib.Path)
    args = parser.parse_args()
    if args.download: prepare()
    if args.verify: verify()
    if args.stage: stage(args.stage)
