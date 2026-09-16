'use strict';
// This entry point never loads upstream .env, agent.pid, or Electron settings.
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const os = require('node:os');
const { ConversionService } = require('./conversion/service.cjs');
const { HubSync } = require('./hub-sync.cjs');
const { createNativeKeychainReader } = require('./native-keychain.cjs');
const { HubCredentialStore } = require('./hub-credential.cjs');

function atomic(file, value) {
  const temp = `${file}.${process.pid}.tmp`;
  fs.writeFileSync(temp, JSON.stringify(value), { mode: 0o600 });
  fs.renameSync(temp, file);
}

async function startBackend({ directory, fixture = false } = {}) {
  if (!path.isAbsolute(directory || '')) throw new Error('absolute beta directory required');
  process.umask(0o077);
  fs.mkdirSync(directory, { recursive: true, mode: 0o700 });
  process.env.TOKEN_MONITOR_SHARED_DIR = directory;
  process.env.TOKSCALE_CONFIG_DIR = path.join(directory, 'tokscale');
  // Source roots remain real tool roots. Only collector-owned writes are redirected.
  const { createHub } = require('./vendor/src/hub/server');
  const { runAgent } = require('./vendor/src/agent/runtime');
  const { captureSessionUsageArchive, readSessionUsageArchive, writeSessionUsageArchive,
    applySessionUsageArchive, sessionUsageArchiveDate } = require('./vendor/src/shared/sessionUsageArchive');
  const secret = crypto.randomBytes(32).toString('hex');
  const session = crypto.randomUUID();
  const configFile = path.join(directory, 'backend-config.json');
  const endpointFile = path.join(directory, 'endpoint.json');
  let config;
  try { config = JSON.parse(fs.readFileSync(configFile, 'utf8')); }
  catch (error) { if (error.code !== 'ENOENT') throw new Error('invalid backend configuration'); config = {}; }
  config = { paused: config.paused === true, deviceId: config.deviceId || crypto.randomUUID() };
  atomic(configFile, config);
  let conversion = null;
  let runtime = null, closing = false, controlBusy = false, generation = 0;
  let lastSuccess = null, failure = null;
  const clients = new Set();
  const readCredential = createNativeKeychainReader({ helper: path.resolve(__dirname, '../../MacOS/TokenMonitorBackend') });
  const hubCredential = new HubCredentialStore(directory);
  const sync = new HubSync({ directory, credential: address => hubCredential.read(address),
    persistCredential: (address, value) => hubCredential.save(address, value), changed: () => {
    const stats = sync.config.enabled ? sync.cache?.stats : hub.getStats();
    if (stats) for (const res of clients) res.write(`event: stats\ndata: ${JSON.stringify({ type: 'stats', stats })}\n\n`);
  } });
  const json = (res, code, value) => {
    res.writeHead(code, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' });
    res.end(JSON.stringify(value));
  };
  const authenticated = req => {
    const provided = Buffer.from(req.headers.authorization || '');
    const expected = Buffer.from(`Bearer ${secret}`);
    return provided.length === expected.length && crypto.timingSafeEqual(provided, expected);
  };
  const status = () => ({ version: '0.6.0', session, paused: config.paused,
    lastSuccess, failure, collecting: runtime?.getDiagnostics().usage?.tickInFlight === true,
    pid: process.pid, sync: sync.status(), providers: (runtime?.getSnapshot()?.limits?.providers || Object.values(hub.getDevices())[0]?.limits?.providers || []).map(p => ({ provider: p.provider, status: p.status })) });
  const hub = createHub({ port: 0, host: '127.0.0.1', secret,
    dataFile: path.join(directory, 'devices.json'),
    logger: { log() {}, warn() {}, error() {} },
    async interceptRequest(req, res) {
      let pathname = new URL(req.url, 'http://127.0.0.1').pathname;
      const local = pathname.startsWith('/local/');
      if (local) { pathname = pathname.slice(6); req.url = pathname; }
      if (!authenticated(req)) { json(res, 401, { error: 'unauthorized' }); return true; }
      if (pathname === '/api/beta/conversion') {
        if(!conversion){json(res,503,{error:'conversionStarting'});return true;}
        try {
          if(req.method==='GET')json(res,200,conversion.status());
          else if(req.method==='POST'){
            const { readJsonBody }=require('./vendor/src/shared/http');
            json(res,200,await conversion.command(await readJsonBody(req,32768)));
          }else json(res,405,{error:'methodNotAllowed'});
        }catch{json(res,400,{error:'conversionRequestFailed'});}
        return true;
      }
      if (pathname === '/api/beta/status' && req.method === 'GET') {
        json(res, 200, status()); return true;
      }
      if (pathname === '/api/beta/hub' && req.method === 'POST') {
        if (controlBusy) { json(res, 409, { error: 'busy' }); return true; }
        controlBusy = true;
        try {
          const { readJsonBody } = require('./vendor/src/shared/http');
          const config = await readJsonBody(req, 8192);
          await sync.configure(config, hub.getDevices()[0]);
          await conversion?.close(); startConversion();
          json(res, 200, sync.status());
        } catch { json(res, 400, { error: 'hubConfigurationFailed' }); }
        finally { controlBusy = false; }
        return true;
      }
      if (!local && sync.config.enabled && req.method === 'GET') {
        if (pathname === '/api/stats' || pathname === '/api/history') {
          const value = pathname.endsWith('/stats') ? sync.cache?.stats : sync.cache?.history;
          json(res, value ? 200 : 503, value || { error: 'hubNotReady' }); return true;
        }
        if (pathname === '/api/stats/stream') {
          res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-store' });
          clients.add(res);
          if (sync.cache?.stats) res.write(`event: snapshot\ndata: ${JSON.stringify({ type: 'stats', stats: sync.cache.stats })}\n\n`);
          const heartbeat = setInterval(() => res.write(': hb\n\n'), 15000);
          req.on('close', () => { clearInterval(heartbeat); clients.delete(res); });
          return true;
        }
      }
      const action = pathname.match(/^\/api\/beta\/(refresh|pause|resume|restart)$/)?.[1];
      if (action && req.method === 'POST') {
        if (controlBusy) { json(res, 409, { error: 'busy' }); return true; }
        controlBusy = true;
        try {
          if (action === 'pause' || action === 'resume') {
            config.paused = action === 'pause'; atomic(configFile, config);
            await stopRuntime();
            if (!config.paused) startRuntime();
          } else if (action === 'refresh' && runtime) {
            readCredential.invalidate();
            // Accept immediately. The collector serializes/coalesces overlapping ticks.
            sync.retryAt = 0; void sync.flush();
            void runtime.tick('manual', { forceHistory: true }).catch(() => { failure = 'collectionFailed'; });
            void runtime.refreshLimits({}, 'manual').catch(() => {});
          }
          json(res, 202, status());
          if (action === 'restart') setTimeout(() => { void close().then(() => process.exit(1)); }, 100);
        } finally { controlBusy = false; }
        return true;
      }
      // Local beta is not an ingest endpoint for other devices.
      if (req.method !== 'GET' || !['/api/health', '/api/stats', '/api/history', '/api/stats/stream'].includes(pathname)) {
        json(res, 404, { error: 'not_found' }); return true;
      }
      return false;
    }
  });
  lastSuccess = Object.values(hub.getDevices())[0]?.updatedAt || null;
  async function stopRuntime() {
    generation++; const previous = runtime; runtime = null; previous?.stop();
    await previous?.whenIdle();
  }
  function startRuntime() {
    if (fixture || config.paused || closing) return;
    const epoch = ++generation;
    runtime = runAgent({
      envelope: { deviceId: config.deviceId, hostname: os.hostname(), agentVersion: '0.6.0', agentRuntime: 'native-beta' },
      usageOptions: {
        clients: 'codex,claude', allTimeSince: '1970-01-01', deviceId: config.deviceId,
        agentVersion: '0.6.0', agentRuntime: 'native-beta',
        projectsEnabled: false, historyEnabled: true, historyIntervalMs: 60000,
        dailyHistoryArchiveEnabled: true, dailyHistoryArchiveWriteEnabled: true,
        anchorPersistenceEnabled: true, intervalMs: 60000,
        watchEnabled: true, watchDebounceMs: 1500, wslScanEnabled: false,
        commandTimeoutMs: 120000,
        onError() { if (epoch === generation) failure = 'collectionFailed'; }, logger() {}
      },
      limitsOptions: { limitsEnabled: true, limitProviders: 'codex,claude',
        limitsRefreshMode: 'adaptive', limitsRefreshMs: 300000,
        readOnlyCredentials: true, claudeWebCookie: '', opencodeAmbientEnabled: false },
      transformUsage(summary) {
        if (epoch !== generation) return summary;
        const day = sessionUsageArchiveDate(summary, new Date());
        const archive = captureSessionUsageArchive(readSessionUsageArchive(), summary, day);
        writeSessionUsageArchive(archive);
        return applySessionUsageArchive(summary, archive, { now: day });
      },
      deliver(record) { if (epoch === generation && !closing) { const normalized = hub.ingest(record); sync.enqueue(normalized); } },
      onRecord(record, meta) {
        if (epoch === generation && meta.source === 'usage') { lastSuccess = new Date().toISOString(); failure = null; }
      },
      onError() { if (epoch === generation) failure = 'collectionFailed'; }
    }, { deviceRuntimeDeps: { limitsDeps: {
      readMacKeychainSecret: () => readCredential('claude')
    } } });
  }
  async function close() {
    if (closing) return;
    closing = true; await conversion?.close(); sync.close(); for (const res of clients) res.end(); await stopRuntime();
    try {
      if (JSON.parse(fs.readFileSync(endpointFile, 'utf8')).session === session) fs.unlinkSync(endpointFile);
    } catch (_) {}
    await hub.stop();
  }
  await hub.start();
  atomic(endpointFile, { version: 1, session, pid: process.pid,
    address: `http://127.0.0.1:${hub.server.address().port}`, secret });
  function startConversion() {
    conversion = new ConversionService({directory:path.join(directory,'conversion'),deviceId:sync.config.deviceId||config.deviceId,
      request:(endpoint,body)=>sync.request(endpoint,body),remoteEnabled:()=>sync.config.enabled,
      source:()=>sync.config.address||'local',localReports:()=>runtime?.getSnapshot()?.limits?.providers||[],enabled:()=>!config.paused&&!closing,fixture});
    conversion.start();
  }
  startRuntime(); startConversion();
  return { close, hub, status, endpoint: JSON.parse(fs.readFileSync(endpointFile, 'utf8')) };
}

if (require.main === module) {
  // Never serialize raw upstream exceptions (which can include response bodies).
  console.log = console.warn = console.error = () => {};
  startBackend({ directory: process.env.TOKEN_MONITOR_BETA_DIR }).then(backend => {
    for (const signal of ['SIGTERM', 'SIGINT']) process.on(signal, () => {
      const timeout = setTimeout(() => process.exit(0), 5000); timeout.unref();
      void backend.close().then(() => process.exit(0));
    });
  }).catch(() => { process.stderr.write('Beta backend failed to start.\n'); process.exit(1); });
}
module.exports = { startBackend, atomic };
