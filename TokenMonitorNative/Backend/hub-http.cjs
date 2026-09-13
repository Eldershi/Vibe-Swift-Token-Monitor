'use strict';
const http = require('node:http');
const https = require('node:https');
// Dedicated, non-pooled Hub requests. Collector/provider traffic cannot retain
// or starve a shared global fetch connection. Redirects are never followed.
function hubFetch(url, options = {}) {
  return new Promise((resolve, reject) => {
    const request = (url.protocol === 'https:' ? https : http).request(url, {
      method: options.method || 'GET', headers: options.headers, agent: false, signal: options.signal
    }, response => {
      const chunks = []; let size = 0;
      response.on('data', chunk => {
        size += chunk.length;
        if (size > 64 * 1024 * 1024) { request.destroy(Error('responseTooLarge')); return; }
        chunks.push(chunk);
      });
      response.on('error', reject);
      response.on('end', () => resolve({ ok: response.statusCode >= 200 && response.statusCode < 300,
        status: response.statusCode, json: async () => JSON.parse(Buffer.concat(chunks).toString('utf8')) }));
    });
    request.on('error', reject);
    if (options.body) request.write(options.body);
    request.end();
  });
}
module.exports = { hubFetch };
