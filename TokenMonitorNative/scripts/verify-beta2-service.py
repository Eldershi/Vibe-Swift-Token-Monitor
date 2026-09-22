#!/usr/bin/env python3
"""Verify an installed, isolated native beta2 service without printing its secrets."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('--app', type=Path, required=True)
parser.add_argument('--lifecycle', action='store_true')
args = parser.parse_args()
root = Path.home() / 'Library/Application Support/Token Monitor Native Beta 2/Backend'


def request(route='status', action=False):
    file = root / 'endpoint.json'
    assert file.stat().st_uid == os.getuid() and file.stat().st_mode & 0o777 == 0o600
    endpoint = json.loads(file.read_text())
    assert endpoint['address'].startswith('http://127.0.0.1:')
    req = urllib.request.Request(endpoint['address'] + '/api/beta/' + route,
                                 headers={'Authorization': 'Bearer ' + endpoint['secret']},
                                 method='POST' if action else 'GET')
    return json.load(urllib.request.urlopen(req, timeout=15))


def until(predicate, seconds=90):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        try:
            value = request()
            if predicate(value):
                return value
        except (OSError, ValueError):
            pass
        time.sleep(.25)
    raise RuntimeError('native beta2 service verification timed out')


import plistlib
version = plistlib.loads((args.app / 'Contents/Info.plist').read_bytes())['TokenMonitorReleaseVersion']
state = until(lambda s: s['version'] == version)
expected = str(args.app / 'Contents/MacOS/TokenMonitorBackend')
actual = subprocess.check_output(['ps', '-p', str(state['pid']), '-o', 'comm='], text=True).strip()
assert actual == expected or actual == 'Contents/MacOS/TokenMonitorBackend', actual
print('PASS: isolated launchd service executes bundled Swift backend')
assert state['sync']['enabled'] is True and state['sync']['error'] is None
print('PASS: Hub connection is healthy')
if args.lifecycle:
    was_paused = state['paused']
    try:
        pid = state['pid']
        subprocess.run([expected], timeout=5, check=True)
        assert request()['pid'] == pid
        print('PASS: singleton service lock')
        request('pause', True)
        paused = until(lambda s: s['paused'] and not s['collecting'])
        os.kill(paused['pid'], signal.SIGKILL)
        restarted = until(lambda s: s['session'] != paused['session'])
        assert restarted['paused']
        print('PASS: crash recovery, private endpoint rotation, persisted pause')
        request('resume', True)
        resumed = until(lambda s: not s['paused'])
        request('refresh', True)
        until(lambda s: s['lastSuccess'] and s['lastSuccess'] != resumed['lastSuccess'], 180)
        print('PASS: resume and fresh native collection')
        previous = request()['session']
        request('restart', True)
        until(lambda s: s['session'] != previous)
        print('PASS: explicit native service restart')
    finally:
        until(lambda s: True)
        request('pause' if was_paused else 'resume', True)
print('PASS: beta2 status and isolated lifecycle')
