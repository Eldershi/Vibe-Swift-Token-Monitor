'use strict';
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');

function validSecret(secret) {
  return typeof secret === 'string' && secret.trim().length > 0 && secret.length <= 4096 && !/[\r\n\0]/.test(secret);
}
// User-entered Hub credentials are local to beta. No Keychain or old-app lookup.
class HubCredentialStore {
  constructor(directory) { this.directory = directory; this.file = path.join(directory, 'hub-credential.json'); }
  read(address) {
    let fd;
    try {
      fd = fs.openSync(this.file, fs.constants.O_RDONLY | fs.constants.O_NOFOLLOW);
      const stat = fs.fstatSync(fd);
      if (!stat.isFile() || stat.uid !== process.getuid() || (stat.mode & 0o777) !== 0o600 || stat.size > 16384) throw Error();
      const value = JSON.parse(fs.readFileSync(fd, 'utf8'));
      return value.address === address && validSecret(value.secret) ? value.secret : null;
    } catch (error) {
      if (error.code === 'ENOENT') return null;
      throw Error('credentialUnavailable');
    } finally { if (fd !== undefined) fs.closeSync(fd); }
  }
  save(address, secret) {
    if (!validSecret(secret)) throw Error('invalidCredential');
    const temp = path.join(this.directory, '.hub-credential-' + crypto.randomUUID());
    let fd;
    try {
      fd = fs.openSync(temp, fs.constants.O_WRONLY | fs.constants.O_CREAT | fs.constants.O_EXCL | fs.constants.O_NOFOLLOW, 0o600);
      fs.writeFileSync(fd, JSON.stringify({ address, secret })); fs.fsyncSync(fd);
      fs.closeSync(fd); fd = undefined;
      fs.renameSync(temp, this.file);
    } catch { throw Error('credentialSaveFailed'); }
    finally { if (fd !== undefined) fs.closeSync(fd); try { fs.unlinkSync(temp); } catch {} }
  }
}
module.exports = { HubCredentialStore, validSecret };
