'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const { HubCredentialStore } = require('../hub-credential.cjs');
const { HubSync } = require('../hub-sync.cjs');
const setup = () => fs.mkdtempSync(path.join(os.tmpdir(), 'beta-manual-hub-'));

test('manual Hub secret persists across restart, binds address and has private permissions', () => {
  const directory = setup();
  try {
    const store = new HubCredentialStore(directory);
    assert.equal(store.read('https://example.test'), null);
    store.save('https://example.test', 'synthetic-key');
    assert.equal(fs.statSync(store.file).mode & 0o777, 0o600);
    assert.equal(new HubCredentialStore(directory).read('https://example.test'), 'synthetic-key');
    assert.equal(store.read('https://other.example'), null);
    store.save('https://example.test', 'synthetic-replacement');
    assert.equal(store.read('https://example.test'), 'synthetic-replacement');
    assert.deepEqual(fs.readdirSync(directory), ['hub-credential.json']);
    assert.throws(() => store.save('https://example.test', 'bad\nheader'), /invalidCredential/);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

test('credential reads reject broad permissions, corrupt data and symlinks', () => {
  const directory = setup();
  try {
    const store = new HubCredentialStore(directory); store.save('https://example.test', 'synthetic-key');
    fs.chmodSync(store.file, 0o644);
    assert.throws(() => store.read('https://example.test'), /credentialUnavailable/);
    fs.chmodSync(store.file, 0o600); fs.writeFileSync(store.file, '{bad');
    assert.throws(() => store.read('https://example.test'), /credentialUnavailable/);
    fs.renameSync(store.file, store.file + '.target'); fs.symlinkSync(store.file + '.target', store.file);
    assert.throws(() => store.read('https://example.test'), /credentialUnavailable/);
  } finally { fs.rmSync(directory, { recursive: true, force: true }); }
});

const record = { deviceId: 'existing', periods: Object.fromEntries(['today','month','allTime'].map(key => [key, { totalTokens: 10 }])), history: { daily: [], monthly: [] } };
test('manual connection validates before save, preserves baseline, never exposes secret in status', async () => {
  const directory = setup(); const store = new HubCredentialStore(directory);
  const requests = [];
  const transport = async (url, init) => {
    requests.push(init.headers.Authorization);
    if (init.headers.Authorization === 'Bearer wrong') return { ok: false, status: 401 };
    return { ok: true, json: async () => String(url).endsWith('/devices') ? { devices: [record] } : { devices: [], daily: [] } };
  };
  const options = { directory, credential: address => store.read(address), persistCredential: (address, secret) => store.save(address, secret), fetchImpl: transport };
  let sync = new HubSync(options);
  try {
    await assert.rejects(sync.configure({ address: 'https://example.test', deviceId: 'existing', secret: 'wrong', enabled: true }, record), /unauthorized/);
    assert.equal(fs.existsSync(store.file), false);
    await sync.configure({ address: 'https://example.test', deviceId: 'existing', secret: 'synthetic-key', enabled: true }, record);
    const baseline = fs.readFileSync(sync.stateFile, 'utf8');
    for (const visible of [sync.status(), sync.config, sync.state, sync.cache]) assert.ok(!JSON.stringify(visible).includes('synthetic-key'));
    assert.ok(sync.lastSuccess);
    sync.close(); sync = new HubSync(options); await sync.flush();
    assert.equal(sync.error, null); assert.equal(requests.at(-1), 'Bearer synthetic-key');
    await assert.rejects(sync.configure({ address: 'https://example.test', deviceId: 'existing', secret: 'wrong', enabled: true }, record));
    assert.equal(store.read('https://example.test'), 'synthetic-key');
    assert.equal(fs.readFileSync(sync.stateFile, 'utf8'), baseline);
    await sync.configure({ enabled: false }); assert.equal(store.read('https://example.test'), 'synthetic-key');
  } finally { sync.close(); fs.rmSync(directory, { recursive: true, force: true }); }
});

test('failed credential save never enables uploads or creates a handoff baseline', async () => {
  const directory = setup(); let uploads = 0;
  const sync = new HubSync({ directory, credential: () => null,
    persistCredential: () => { throw Error('credentialSaveFailed'); },
    fetchImpl: async (_, init) => { if (init.method === 'POST') uploads++; return { ok: true, json: async () => ({ devices: [record] }) }; }
  });
  try {
    await assert.rejects(sync.configure({ address: 'https://example.test', deviceId: 'existing', secret: 'synthetic-key', enabled: true }, record), /credentialSaveFailed/);
    assert.equal(sync.config.enabled, false); assert.equal(uploads, 0);
    assert.equal(fs.existsSync(sync.stateFile), false);
  } finally { sync.close(); fs.rmSync(directory, { recursive: true, force: true }); }
});

test('authenticated local API saves manual credentials and reconnects after backend restart', async () => {
  const http = require('node:http');
  const { startBackend } = require('../main.cjs');
  const directory = setup(); let unauthorized = 0;
  const remote = http.createServer((req, res) => {
    if (req.headers.authorization !== 'Bearer synthetic-manual-key') { unauthorized++; res.writeHead(401); res.end(); return; }
    res.setHeader('Content-Type', 'application/json');
    res.end(JSON.stringify(req.url.endsWith('/devices') ? { devices: [record] } : { devices: [], daily: [] }));
  });
  await new Promise(resolve => remote.listen(0, '127.0.0.1', resolve));
  let backend = await startBackend({ directory, fixture: true });
  const config = { enabled: true, address: `http://127.0.0.1:${remote.address().port}`, deviceId: 'existing' };
  const post = body => fetch(backend.endpoint.address + '/api/beta/hub', { method: 'POST',
    headers: { Authorization: `Bearer ${backend.endpoint.secret}`, 'Content-Type': 'application/json' }, body: JSON.stringify(body) });
  try {
    backend.hub.ingest(record);
    let response = await post({ ...config, secret: 'synthetic-manual-key' });
    assert.equal(response.status, 200); assert.ok(!(await response.text()).includes('synthetic-manual-key'));
    await backend.close(); backend = await startBackend({ directory, fixture: true });
    response = await post(config); assert.equal(response.status, 200);
    const state = await response.json(); assert.equal(state.error, null); assert.ok(state.lastSuccess);
    assert.equal(unauthorized, 0);
  } finally {
    await backend.close(); await new Promise(resolve => remote.close(resolve));
    fs.rmSync(directory, { recursive: true, force: true });
  }
});
