const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { EventEmitter } = require('node:events');
const { startBackend } = require('../main.cjs');
const { fetchClaudeLimits } = require('../vendor/src/shared/providers/claude/limits');
const { fetchCodexLimits } = require('../vendor/src/shared/providers/codex/limits');

test('authenticated local API, pause persistence, restart discovery, SSE and stable device ID', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'native-beta-test-'));
  let backend = await startBackend({ directory, fixture: true });
  const request = (route, method = 'GET') => fetch(backend.endpoint.address + route, {
    method, headers: { Authorization: `Bearer ${backend.endpoint.secret}` }
  });
  try {
    assert.equal(fs.statSync(path.join(directory, 'endpoint.json')).mode & 0o777, 0o600);
    assert.equal(fs.statSync(directory).mode & 0o777, 0o700);
    assert.equal((await fetch(backend.endpoint.address + '/api/stats')).status, 401);
    assert.equal((await request('/api/ingest', 'POST')).status, 404);
    assert.equal((await request('/api/health')).status, 200);
    const abort = new AbortController();
    const stream = await fetch(backend.endpoint.address + '/api/stats/stream', {
      signal: abort.signal, headers: { Authorization: `Bearer ${backend.endpoint.secret}` }
    });
    assert.match(stream.headers.get('content-type'), /text\/event-stream/);
    const reader = stream.body.getReader();
    assert.match(new TextDecoder().decode((await reader.read()).value), /data:/);
    abort.abort();
    assert.equal((await request('/api/beta/pause', 'POST')).status, 202);
    assert.equal((await (await request('/api/beta/status')).json()).paused, true);
    const first = backend.endpoint;
    const identity = JSON.parse(fs.readFileSync(path.join(directory, 'backend-config.json'))).deviceId;
    await backend.close();
    assert.equal(fs.existsSync(path.join(directory, 'endpoint.json')), false);
    backend = await startBackend({ directory, fixture: true });
    assert.notEqual(backend.endpoint.session, first.session);
    assert.notEqual(backend.endpoint.secret, first.secret);
    assert.equal(backend.status().paused, true);
    assert.equal(JSON.parse(fs.readFileSync(path.join(directory, 'backend-config.json'))).deviceId, identity);
    await request('/api/beta/resume', 'POST');
    assert.equal(backend.status().paused, false);
  } finally { await backend.close(); fs.rmSync(directory, { recursive: true, force: true }); }
});

test('invalid persistent state is not silently overwritten', async () => {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'native-beta-invalid-'));
  const file = path.join(directory, 'backend-config.json'); fs.writeFileSync(file, '{broken');
  await assert.rejects(startBackend({ directory, fixture: true }), /invalid backend configuration/);
  assert.equal(fs.readFileSync(file, 'utf8'), '{broken');
  fs.rmSync(directory, { recursive: true });
});

for (const status of [401, 429, 503, 'offline']) {
  test(`Claude HTTP ${status} never refreshes credentials or launches CLI`, async () => {
    let spawns = 0, writes = 0;
    await assert.rejects(fetchClaudeLimits({ readOnlyCredentials: true, claudeWebCookie: '' }, {
      env: { CLAUDE_CODE_OAUTH_TOKEN: 'synthetic-access' }, platform: 'darwin',
      fetch: async () => { if (status === 'offline') throw new Error('network unavailable'); return new Response('{}', { status }); },
      spawn() { spawns++; throw new Error('forbidden'); },
      writeFile() { writes++; throw new Error('forbidden'); },
      rename() { writes++; throw new Error('forbidden'); }
    }));
    assert.equal(spawns, 0); assert.equal(writes, 0);
  });
}

test('Claude missing credentials and locked Keychain remain unavailable', async () => {
  let launches = 0;
  await assert.rejects(fetchClaudeLimits({ readOnlyCredentials: true, claudeWebCookie: '' }, {
    env: {}, readMacKeychain: false,
    readFile: async () => { throw Object.assign(new Error('missing'), { code: 'ENOENT' }); },
    spawn() { launches++; throw new Error('forbidden'); }
  }));
  assert.equal(launches, 0);
});

test('Claude valid OAuth maps real zero quota without refresh', async () => {
  const provider = await fetchClaudeLimits({ readOnlyCredentials: true, claudeWebCookie: '' }, {
    env: { CLAUDE_CODE_OAUTH_TOKEN: 'synthetic-valid' },
    fetch: async url => new Response(JSON.stringify(url.endsWith('/profile')
      ? { account: { uuid: 'synthetic-account', email: 'fixture@example.com' }, organization: { uuid: 'synthetic-org' } }
      : { five_hour: { utilization: 0, resets_at: '2026-12-01T12:00:00Z' } }), { status: 200 })
  });
  assert.equal(provider.windows[0].usedPercent, 0);
});

for (const status of ['unauthorized', 'notConfigured', 'sourceRateLimited', 'unavailable']) {
  test(`Codex ${status} never invokes RPC or login`, async () => {
    let rpc = 0;
    await assert.rejects(fetchCodexLimits({ readOnlyCredentials: true }, {
      readFileSync: () => { throw new Error('synthetic missing file'); },
      readCodexUsage: async () => { throw Object.assign(new Error('synthetic'), { status }); },
      readCodexRpc: async () => { rpc++; throw new Error('forbidden'); }
    }));
    assert.equal(rpc, 0);
  });
}

test('locked Keychain reads fail without a login or credential mutation', async () => {
  let commands = [];
  await assert.rejects(fetchClaudeLimits({ readOnlyCredentials: true, claudeWebCookie: '' }, {
    env: {}, platform: 'darwin',
    readFile: async () => { throw Object.assign(new Error('missing'), { code: 'ENOENT' }); },
    spawn(command, args) {
      commands.push([command, ...args]);
      const child = new EventEmitter(); child.stdout = new EventEmitter(); child.stderr = new EventEmitter();
      child.kill = () => {};
      process.nextTick(() => { child.stderr.emit('data', 'synthetic Keychain locked'); child.emit('close', 44); });
      return child;
    }
  }));
  assert.deepEqual(commands, []); // Read-only mode must never start interactive security.
});
