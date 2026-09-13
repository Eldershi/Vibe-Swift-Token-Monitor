#!/usr/bin/env python3
"""Exercise the installed beta service; its configured shared Hub synchronization may continue."""
import argparse
import json
import os
from pathlib import Path
import signal
import subprocess
import time
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('--lifecycle', action='store_true')
args = parser.parse_args()
root = Path.home() / 'Library/Application Support/Token Monitor Native Beta/Backend'
app = Path.home() / 'Applications/Token Monitor Native Beta.app'

def endpoint():
    file = root / 'endpoint.json'
    assert file.stat().st_uid == os.getuid() and file.stat().st_mode & 0o777 == 0o600
    value = json.loads(file.read_text())
    assert value['address'].startswith('http://127.0.0.1:')
    return value

def request(route='status', action=False):
    value = endpoint()
    req = urllib.request.Request(value['address'] + '/api/beta/' + route,
                                 headers={'Authorization': 'Bearer ' + value['secret']},
                                 method='POST' if action else 'GET')
    return json.load(urllib.request.urlopen(req, timeout=10))

def until(predicate, timeout=45):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        try:
            state = request()
            if predicate(state): return state
        except (OSError, ValueError): pass
        time.sleep(0.25)
    raise RuntimeError('beta verification timed out')

state = until(lambda s: True)
command = subprocess.check_output(['ps', '-p', str(state['pid']), '-o', 'comm='], text=True).strip()
assert command == str(app / 'Contents/Resources/Backend/runtime/node'), command
print('PASS: service uses bundled Node, private authenticated loopback endpoint')
if args.lifecycle:
    original_pause = state['paused']
    try:
        pid = state['pid']
        result = subprocess.run([str(app / 'Contents/MacOS/TokenMonitorBackend')], timeout=5)
        assert result.returncode == 0 and request()['pid'] == pid
        print('PASS: singleton helper lock')
        request('pause', True)
        paused = until(lambda s: s['paused'] and not s['collecting'])
        os.kill(paused['pid'], signal.SIGKILL)
        restarted = until(lambda s: s['session'] != paused['session'])
        assert restarted['paused']
        print('PASS: crash recovery, credential rotation, persisted pause')
        request('resume', True)
        until(lambda s: not s['paused'])
        request('refresh', True)
        until(lambda s: s['lastSuccess'] and s['lastSuccess'] != restarted['lastSuccess'], timeout=120)
        print('PASS: resume and new successful collection')
        previous = request()['session']
        request('restart', True)
        until(lambda s: s['session'] != previous)
        print('PASS: explicit service restart')
    finally:
        until(lambda s: True)
        request('pause' if original_pause else 'resume', True)
print('Status:', json.dumps({key: request().get(key) for key in ['version', 'paused', 'lastSuccess', 'failure']}, ensure_ascii=False))
