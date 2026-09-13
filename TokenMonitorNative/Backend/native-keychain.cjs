'use strict';
const { execFile } = require('node:child_process');
const { promisify } = require('node:util');

// Only the bundled helper reads Keychain. It disables interaction process-wide.
// Coalesce concurrent reads and briefly cache failures; never persist secrets.
function createNativeKeychainReader({ helper, execute = promisify(execFile), now = Date.now } = {}) {
  const pending = new Map();
  const deniedUntil = new Map();
  async function read(kind, address = '') {
    if (kind !== 'claude') throw Error('unsupportedCredential');
    const key = kind + ':' + address;
    if (deniedUntil.get(key) > now()) throw Object.assign(Error('keychainUnavailable'), { status: 'unauthorized' });
    if (pending.has(key)) return pending.get(key);
    const operation = Promise.resolve().then(async () => {
      try {
        const args = ['--claude-secret'];
        const result = await execute(helper, args, { timeout: 10000, maxBuffer: 1024 * 1024 });
        return result.stdout.trim();
      } catch (error) {
        if (error.code === 44) return '';
        deniedUntil.set(key, now() + 30000);
        throw Object.assign(Error('keychainUnavailable'), { status: 'unauthorized' });
      } finally { pending.delete(key); }
    });
    pending.set(key, operation);
    return operation;
  }
  read.invalidate = () => deniedUntil.clear();
  return read;
}
module.exports = { createNativeKeychainReader };
