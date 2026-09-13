'use strict';
const test = require('node:test');
const assert = require('node:assert/strict');
const { createNativeKeychainReader } = require('../native-keychain.cjs');
const { fetchClaudeLimits } = require('../vendor/src/shared/providers/claude/limits');

test('concurrent credential requests share one helper; later refresh rereads credentials', async () => {
  let calls = 0;
  const read = createNativeKeychainReader({ helper: '/test/bundled-helper', execute: async (file, args) => {
    assert.equal(file, '/test/bundled-helper'); assert.deepEqual(args, ['--claude-secret']);
    calls++; return { stdout: 'fixture-only' };
  } });
  assert.deepEqual(await Promise.all(Array.from({ length: 6 }, () => read('claude'))), Array(6).fill('fixture-only'));
  assert.equal(calls, 1);
  await read('claude'); assert.equal(calls, 2);
});

test('denied reads back off, redact errors and retry after explicit refresh or expiry', async () => {
  let calls = 0, time = 0;
  const read = createNativeKeychainReader({ helper: '/test/helper', now: () => time, execute: () => {
    calls++; throw Object.assign(Error('sensitive-fixture-output'), { stderr: 'private-fixture' });
  } });
  const denied = error => error.status === 'unauthorized' && error.message === 'keychainUnavailable' && !error.stderr;
  for (let i = 0; i < 6; i++) await assert.rejects(read('claude'), denied);
  assert.equal(calls, 1);
  read.invalidate(); await assert.rejects(read('claude'), denied); assert.equal(calls, 2);
  time = 30001; await assert.rejects(read('claude'), denied); assert.equal(calls, 3);
});

test('missing credential differs from denied access', async () => {
  const read = createNativeKeychainReader({ helper: '/test/helper', execute: async () => { throw { code: 44 }; } });
  assert.equal(await read('claude'), '');
  await assert.rejects(read('hub'), /unsupportedCredential/);
});

const missingFiles = { platform: 'darwin', env: {}, stat: async () => { throw { code: 'ENOENT' }; },
  spawn: () => { throw Error('interactive security CLI must not run'); } };
test('read-only Claude preserves denied status and never falls back to interactive security', async () => {
  await assert.rejects(fetchClaudeLimits({ readOnlyCredentials: true }, {
    ...missingFiles,
    readMacKeychainSecret: async () => { throw Object.assign(Error('keychainUnavailable'), { status: 'unauthorized' }); }
  }), error => error.status === 'unauthorized');
  await assert.rejects(fetchClaudeLimits({ readOnlyCredentials: true }, missingFiles), error => error.status === 'notConfigured');
});
