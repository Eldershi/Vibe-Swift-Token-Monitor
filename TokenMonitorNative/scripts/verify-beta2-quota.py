#!/usr/bin/env python3
"""Synthetic native quota outbox, crash retry and cycle pagination checks; no production access."""
import argparse
from datetime import datetime, timedelta, timezone
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import hashlib
from urllib.parse import urlparse, parse_qs
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
args = parser.parse_args()

now = datetime.now(timezone.utc)
cutoff = now - timedelta(minutes=2)
date_key = now.astimezone().strftime('%Y-%m-%d')
month_key = now.astimezone().strftime('%Y-%m')
stamp = lambda value: value.isoformat(timespec='milliseconds').replace('+00:00', 'Z')
device_id = 'synthetic-native-handoff'
period = {'totalTokens': 1000, 'cacheReadTokens': 0, 'outputTokens': 0,
          'clients': {'codex': 1000}, 'models': {'synthetic': 1000},
          'clientModels': {'codex': {'synthetic': 1000}}}
remote = {'deviceId': device_id, 'hostname': socket.gethostname(), 'osName': 'macOS',
          'agentRuntime': 'native-beta', 'updatedAt': stamp(cutoff),
          'periodWindows': {'today': {'key': date_key}, 'month': {'key': month_key}},
          'periods': {key: dict(period) for key in ('today', 'month', 'allTime')},
          'history': {'daily': [{'date': date_key, 'tokens': 1000, 'perClient': {'codex': {'tokens': 1000}}}],
                      'monthly': [{'month': month_key, 'tokens': 1000, 'perClient': {'codex': {'tokens': 1000}}}]}}
uploads = []
quota_attempts = []
quota_accepted = []
fail_quota = True
fail_page_two = True
cycle_requests = []
cycle_events = [{'id': 'synthetic-cycle-'+str(i)} for i in range(2)]
lock = threading.Lock()


class Hub(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, value, code=200):
        data = json.dumps(value).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        assert self.headers.get('Authorization') == 'Bearer synthetic-secret'
        if self.path == '/api/health':
            self.send({'quotaCycleVersion': 1})
        elif self.path.startswith('/api/quota/cycles?'):
            cursor = parse_qs(urlparse(self.path).query).get('cursor', [None])[0]
            cycle_requests.append(cursor)
            if cursor and fail_page_two:
                self.send({'error': 'synthetic'}, 503)
            else:
                self.send({'schemaVersion': 1, 'policyVersion': 1, 'snapshotThrough': stamp(now),
                           'events': [cycle_events[1 if cursor else 0]],
                           'nextCursor': None if cursor else 'synthetic-next-page'})
        elif self.path == '/api/devices':
            with lock: self.send({'devices': [remote]})
        elif self.path == '/api/stats':
            with lock: self.send({'updatedAt': remote['updatedAt'], 'periods': remote['periods'], 'devices': [remote]})
        elif self.path == '/api/history':
            with lock: self.send(remote['history'])
        else: self.send_error(404)

    def do_POST(self):
        assert self.path == '/api/ingest'
        assert self.headers.get('Authorization') == 'Bearer synthetic-secret'
        value = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        assert value['deviceId'] == device_id
        if value.get('limitsOnly'):
            assert not any(k in value for k in ['periods', 'history', 'today', 'month', 'allTime'])
            quota_attempts.append(value)
            if fail_quota:
                self.send({'error': 'synthetic'}, 503)
                return
            quota_accepted.append(value)
            with lock:
                before = json.loads(json.dumps(remote['periods']))
                if args.usage_module:
                    merged = subprocess.run(['node', '-e',
                        'const {mergeDeviceRecord}=require(process.argv[1]);let s="";process.stdin.on("data",x=>s+=x);process.stdin.on("end",()=>{const v=JSON.parse(s);process.stdout.write(JSON.stringify(mergeDeviceRecord(v.existing,v.incoming)))});',
                        str(args.usage_module.resolve())], input=json.dumps({'existing': remote, 'incoming': value}),
                        capture_output=True, text=True, check=True)
                    remote.clear(); remote.update(json.loads(merged.stdout))
                assert remote['periods'] == before
                self.send({'ok': True, 'deviceId': device_id})
            return
        assert 'limits' not in value
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
                               'payload': {'model': 'synthetic'}}) + '\n' +
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
        until(lambda: uploads and uploads[-1]['periods']['allTime']['totalTokens'] == 1050)
        until(lambda: json.loads((root / 'hub-handoff.json').read_text())['pendingUpload'] is False)
        until(lambda: (root / 'quota-cycles.json').exists() and json.loads((root / 'quota-cycles.json').read_text()).get('cursor'))
        os.kill(process.pid, signal.SIGKILL); process.wait(timeout=5)
        scope = hashlib.sha256((config['address']+'\n'+device_id+'\n'+config['secret']).encode()).hexdigest()
        provider = {'provider': 'codex', 'status': 'ok', 'accountKey': 'synthetic-account',
                    'updatedAt': stamp(now), 'windows': [{'kind':'weekly','limitId':'codex','windowMinutes':10080,
                    'usedPercent':25, 'remainingPercent':75, 'resetsAt':stamp(now+timedelta(days=6))}]}
        outbox = {'scope':scope,'latest':provider,'pending':[{'id':'synthetic-observation','provider':provider}]}
        (root / 'quota-outbox.json').write_text(json.dumps(outbox)); (root / 'quota-outbox.json').chmod(0o600)
        process = start()
        until(lambda: len(quota_attempts) > 0)
        assert len(json.loads((root / 'quota-outbox.json').read_text())['pending']) == 1
        os.kill(process.pid, signal.SIGKILL); process.wait(timeout=5)
        fail_quota = False; fail_page_two = False
        process = start()
        until(lambda: json.loads((root / 'quota-outbox.json').read_text())['pending'] == [])
        until(lambda: len(json.loads((root / 'quota-cycles.json').read_text()).get('events',[])) == 2)
        assert quota_attempts[0]['limits'] == quota_accepted[0]['limits']
        assert remote['periods']['allTime']['totalTokens'] == 1050
        assert 'synthetic-next-page' in cycle_requests
        assert (root / 'quota-outbox.json').stat().st_mode & 0o777 == 0o600
        assert (root / 'quota-cycles.json').stat().st_mode & 0o777 == 0o600
        print('PASS: failed quota upload survives crash, exact source timestamp retries, usage totals unchanged')
        print('PASS: cycle pagination checkpoint resumes after crash; completed cache contains both pages')
    finally:
        process.terminate()
        try: process.wait(timeout=5)
        except subprocess.TimeoutExpired: process.kill()
        server.shutdown()
        output.close()
