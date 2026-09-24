#!/usr/bin/env python3
"""End-to-end synthetic Hub handoff test; never contacts the production Hub."""
import argparse
import copy
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import tempfile
import threading
import time
import urllib.request

parser = argparse.ArgumentParser()
parser.add_argument('--backend', type=Path, required=True)
parser.add_argument('--usage-module', type=Path)
parser.add_argument('--mixed-agents', action='store_true', help='Preserve other Agent history and devices across Codex-only uploads')
args = parser.parse_args()

now = datetime.now(timezone.utc)
cutoff = now - timedelta(minutes=2)
date_key = now.astimezone().strftime('%Y-%m-%d')
month_key = now.astimezone().strftime('%Y-%m')
stamp = lambda value: value.isoformat(timespec='milliseconds').replace('+00:00', 'Z')
device_id = 'synthetic-native-handoff'
period = {'totalTokens': 1000, 'cacheReadTokens': 0, 'outputTokens': 0,
          'clients': {'codex': 1000}, 'models': {'gpt-6-sol': 1000},
          'clientModels': {'codex': {'gpt-6-sol': 1000}}}
remote = {'deviceId': device_id, 'hostname': socket.gethostname(), 'osName': 'macOS',
          'agentRuntime': 'native-beta', 'updatedAt': stamp(cutoff),
          'periodWindows': {'today': {'key': date_key}, 'month': {'key': month_key}},
          'periods': {key: dict(period) for key in ('today', 'month', 'allTime')},
          'history': {'daily': [{'date': date_key, 'tokens': 1000, 'perClient': {'codex': {'tokens': 1000}}}],
                      'monthly': [{'month': month_key, 'tokens': 1000, 'perClient': {'codex': {'tokens': 1000}}}]}}
if args.mixed_agents:
    for row in remote['periods'].values():
        # Deep copies keep the three period fixtures independent.
        row.update(totalTokens=1400, clients={'codex': 1000, 'claude': 400},
                   models={'gpt-6-sol': 1000, 'other-model': 400},
                   clientModels={'codex': {'gpt-6-sol': 1000}, 'claude': {'other-model': 400}})
    for rows in remote['history'].values():
        for row in rows:
            row['tokens'] = 1400
            row['perClient']['claude'] = {'tokens': 400}
    remote['trackedClients'] = ['codex', 'claude']
    remote['limits'] = {'providers': [{'provider': 'claude', 'status': 'ok', 'updatedAt': stamp(cutoff),
        'windows': [{'kind': 'weekly', 'usedPercent': 35, 'remainingPercent': 65, 'windowMinutes': 10080}]}]}
other_device = copy.deepcopy(remote)
other_device['deviceId'] = 'synthetic-other-client'
other_before = copy.deepcopy(other_device)
extra = 400 if args.mixed_agents else 0


def assert_preserved(expected):
    assert remote['periods']['allTime']['totalTokens'] == expected + extra
    assert other_device == other_before
    if not args.mixed_agents:
        return
    assert uploads[-1]['trackedClients'] == ['codex']
    for row in remote['periods'].values():
        assert row['clients']['claude'] == 400
        assert row['clientModels']['claude']['other-model'] == 400
        assert row['clients']['codex'] == expected
        assert row['totalTokens'] == expected + 400
    for field in ('daily', 'monthly'):
        row = remote['history'][field][-1]
        assert row['perClient']['claude']['tokens'] == 400
        assert row['perClient']['codex']['tokens'] == expected
        assert row['tokens'] == expected + 400
    assert remote['limits']['providers'][0]['provider'] == 'claude'
    assert remote['limits']['providers'][0]['windows'][0]['remainingPercent'] == 65


uploads = []
lock = threading.Lock()


class Hub(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, value):
        data = json.dumps(value).encode()
        self.send_response(200)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        assert self.headers.get('Authorization') == 'Bearer synthetic-secret'
        if self.path == '/api/devices':
            with lock: self.send({'devices': [remote, other_device]})
        elif self.path == '/api/stats':
            with lock: self.send({'updatedAt': remote['updatedAt'], 'periods': remote['periods'], 'devices': [remote, other_device]})
        elif self.path == '/api/history':
            with lock: self.send(remote['history'])
        else: self.send_error(404)

    def do_POST(self):
        assert self.path == '/api/ingest'
        assert self.headers.get('Authorization') == 'Bearer synthetic-secret'
        value = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        assert value['deviceId'] == device_id and 'limits' not in value
        assert all('clientModelCosts' not in row and 'modelCosts' not in row
                   for row in value['periods'].values()), 'Display pricing leaked into upload ledger'
        with lock:
            uploads.append(value)
            if args.usage_module:
                merged = subprocess.run(['node', '-e',
                    'const {mergeDeviceRecord}=require(process.argv[1]);let s="";process.stdin.on("data",x=>s+=x);process.stdin.on("end",()=>{const v=JSON.parse(s);process.stdout.write(JSON.stringify(mergeDeviceRecord(v.existing,v.incoming)))});',
                    str(args.usage_module.resolve())], input=json.dumps({'existing': remote, 'incoming': value}),
                    capture_output=True, text=True, check=True)
                remote.clear(); remote.update(json.loads(merged.stdout))
            else: remote.update(value)
            self.send({'ok': True, 'deviceId': device_id, 'stats': {}})


def until(fn, timeout=30):
    end = time.monotonic() + timeout
    while time.monotonic() < end:
        try:
            value = fn()
            if value: return value
        except (OSError, ValueError, KeyError):
            pass
        time.sleep(.1)
    try:
        state = local_request(root, '/api/beta/status')
        print('diagnostic:', {'uploadCount': len(uploads), 'sync': {key: state['sync'].get(key)
              for key in ('enabled', 'uploadEnabled', 'error', 'lastSuccess', 'syncing')},
              'collectionFailure': state.get('failure')})
        print('service log tail:', (home / 'service.log').read_text()[-500:])
    except (OSError, ValueError, KeyError):
        pass
    raise AssertionError('timed out waiting for synthetic Hub handoff')


def local_request(root, route, body=None):
    endpoint = json.loads((root / 'endpoint.json').read_text())
    request = urllib.request.Request(endpoint['address'] + route,
                                     headers={'Authorization': 'Bearer ' + endpoint['secret'],
                                              'Content-Type': 'application/json'},
                                     data=json.dumps(body).encode() if body is not None else None)
    return json.load(urllib.request.urlopen(request, timeout=5))


def token_line(at, total, last):
    usage = lambda amount: {'input_tokens': amount, 'cached_input_tokens': 0, 'output_tokens': 0}
    return json.dumps({'type': 'event_msg', 'timestamp': stamp(at),
                       'payload': {'type': 'token_count', 'info': {'total_token_usage': usage(total),
                                                                   'last_token_usage': usage(last)}}}) + '\n'


with tempfile.TemporaryDirectory(prefix='token-monitor-native-upload-') as temp:
    home = Path(temp)
    root = home / 'backend'
    sessions = home / 'codex' / 'sessions'
    sessions.mkdir(parents=True)
    log = sessions / 'synthetic.jsonl'
    log.write_text(json.dumps({'type': 'turn_context', 'timestamp': stamp(now - timedelta(minutes=1)),
                               'payload': {'model': 'gpt-6-sol'}}) + '\n' +
                   token_line(now - timedelta(minutes=1), 50, 50))
    server = ThreadingHTTPServer(('127.0.0.1', 0), Hub)
    threading.Thread(target=server.serve_forever, daemon=True).start()
    env = dict(os.environ, TOKEN_MONITOR_BETA2_DIR=str(root), TOKEN_MONITOR_BETA2_CODEX_ROOT=str(home / 'codex'))
    output = open(home / 'service.log', 'w')

    def start():
        process = subprocess.Popen([str(args.backend.resolve())], env=env, stdout=output, stderr=output)
        until(lambda: (root / 'endpoint.json').exists() and
              json.loads((root / 'endpoint.json').read_text()).get('pid') == process.pid)
        return process

    process = start()
    try:
        config = {'enabled': True, 'uploadEnabled': True, 'address': f'http://127.0.0.1:{server.server_port}',
                  'secret': 'synthetic-secret', 'deviceId': device_id}
        local_request(root, '/api/beta/hub', config)
        until(lambda: remote['periods']['allTime']['totalTokens'] == 1050 + extra)
        assert uploads[-1]['history']['daily'][-1]['tokens'] == 1050 + extra
        assert local_request(root, '/api/beta/status')['sync']['uploadEnabled'] is True
        until(lambda: json.loads((root / 'hub-handoff.json').read_text())['pendingUpload'] is False)
        assert_preserved(1050)
        print('PASS: existing device received only post-cutoff tokens')
        local_stats = local_request(root, '/local/api/stats')
        local_cost = local_stats['periods']['allTime']['clientModelCosts']['codex']['gpt-6-sol']
        assert abs(local_cost - 50 * 2 / 1_000_000) < 1e-12, local_cost
        print('PASS: local display pricing available without changing uploaded costs')
        local_request(root, '/api/beta/refresh', {})
        time.sleep(.5)
        assert remote['periods']['allTime']['totalTokens'] == 1050 + extra
        assert_preserved(1050)
        print('PASS: repeated absolute snapshot did not double count')
        os.kill(process.pid, signal.SIGKILL)
        process.wait(timeout=5)
        log.write_text(log.read_text() + token_line(datetime.now(timezone.utc), 70, 20))
        process = start()
        until(lambda: remote['periods']['allTime']['totalTokens'] == 1070 + extra)
        until(lambda: json.loads((root / 'hub-handoff.json').read_text())['pendingUpload'] is False)
        assert remote['periods']['allTime']['totalTokens'] == 1070 + extra
        assert_preserved(1070)
        downloaded = local_request(root, '/api/stats')
        assert len(downloaded['devices']) == 2
        if args.mixed_agents:
            assert downloaded['devices'][0]['periods']['allTime']['clients']['claude'] == 400
            print('PASS: mixed Agent history, quota, other device and downloaded wire data retained')
        print('PASS: persisted handoff resumed after crash and added only the new increment')
    finally:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill()
        server.shutdown()
        output.close()
