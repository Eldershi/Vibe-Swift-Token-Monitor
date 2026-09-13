'use strict';
const fs = require('node:fs');
const { hubFetch } = require('./hub-http.cjs');
const { validSecret } = require('./hub-credential.cjs');
const path = require('node:path');
const { aggregateDevices, aggregateHistory } = require('./vendor/src/shared/usage');
const { historyRevision, historyPreview } = require('./vendor/src/shared/history');
const clone = x => structuredClone(x);
const derived = new Set(['intensity', 'tokenIntensity', 'costIntensity', 'activeDays', 'currentStreak', 'longestStreak', 'peakDayTokens', 'summary']);
// A durable handoff baseline is an offset, never a second device. Compare with a
// persisted high-water mark so truncated/replayed collector snapshots add nothing.
function advance(base, seen, current, key = '') {
  if (typeof current === 'number') {
    if (derived.has(key)) return [base ?? current, Math.max(seen || 0, current)];
    const high = Math.max(Number(seen) || 0, current);
    return [(Number(base) || 0) + high - (Number(seen) || 0), high];
  }
  if (Array.isArray(current)) {
    const rows = new Map((base || []).map(r => [r.date || r.month, clone(r)]));
    const previous = new Map((seen || []).map(r => [r.date || r.month, r]));
    for (const row of current) {
      const id = row.date || row.month;
      if (!id) continue;
      const [next, high] = advance(rows.get(id) || {}, previous.get(id) || {}, row);
      rows.set(id, next); previous.set(id, high);
    }
    return [[...rows.values()].sort((a,b) => String(a.date || a.month).localeCompare(String(b.date || b.month))), [...previous.values()]];
  }
  if (current && typeof current === 'object') {
    const out = clone(base || {}), high = clone(seen || {});
    for (const [k, v] of Object.entries(current)) {
      if (derived.has(k) || ['sessions','projects'].includes(k)) continue;
      [out[k], high[k]] = advance(out[k], high[k], v, k);
    }
    return [out, high];
  }
  return [current, current];
}
function initialSeen(local, remote) {
  if (typeof local === 'number') return Math.min(local, Number(remote) || 0);
  if (Array.isArray(local)) return local.map(row => initialSeen(row, (remote || []).find(r => (r.date || r.month) === (row.date || row.month))));
  if (local && typeof local === 'object') return Object.fromEntries(Object.entries(local).map(([k,v]) => [k, initialSeen(v, remote?.[k])]));
  return local;
}
function initializeBaseline(remote, local) {
  const state = advanceRecord({ version: 1, establishedAt: new Date().toISOString(), output: clone(remote), seen: initialSeen(local, remote) }, local);
  // Per-client totals are authoritative when recovering different tool coverage.
  for (const period of Object.values(state.output.periods)) {
    if (Object.keys(period.clients || {}).length) period.totalTokens = Object.values(period.clients).reduce((a,b)=>a+b,0);
    if (Object.keys(period.clientCosts || {}).length) period.costUsd = Object.values(period.clientCosts).reduce((a,b)=>a+b,0);
  }
  return state;
}
function advanceRecord(state, record) {
  const result = clone(state.output), seen = clone(state.seen);
  for (const name of ['today','month','allTime']) {
    const sameWindow = name === 'allTime' || state.output.periodWindows?.[name]?.key === record.periodWindows?.[name]?.key;
    if (sameWindow) [result.periods[name], seen.periods[name]] = advance(result.periods[name], seen.periods[name], record.periods[name]);
    else { result.periods[name] = clone(record.periods[name]); seen.periods[name] = clone(record.periods[name]); }
  }
  [result.history, seen.history] = advance(result.history || {}, seen.history || {}, record.history || {});
  for (const key of ['periodWindows','updatedAt','limits','osName','osVersion','hostname','platform']) result[key] = clone(record[key]);
  // Untracked tools retain their original status timestamps; fresh timestamps are
  // supplied only for the tools that this collector actually inspected.
  result.clientStatus = { ...result.clientStatus, ...record.clientStatus };
  result.clientHealth = { ...result.clientHealth, ...record.clientHealth };
  result.trackedClients = record.trackedClients;
  result.agentVersion = '0.5.0-beta.2'; result.agentRuntime = 'native-beta';
  result.projectsEnabled = false;
  for (const p of Object.values(result.periods)) { p.sessions = {}; p.projects = {}; }
  seen.periodWindows = clone(record.periodWindows);
  return { ...state, output: result, seen };
}
function atomic(file, value) {
  const tmp = file + '.tmp'; fs.writeFileSync(tmp, JSON.stringify(value), { mode: 0o600 }); fs.renameSync(tmp, file);
}
function load(file, fallback) { try { return JSON.parse(fs.readFileSync(file, 'utf8')); } catch (e) { if (e.code !== 'ENOENT') throw Error('invalid_sync_storage'); return fallback; } }
class HubSync {
  constructor({ directory, credential, persistCredential, fetchImpl = hubFetch, changed = () => {} }) {
    this.directory = directory; this.credential = credential; this.persistCredential = persistCredential; this.fetch = fetchImpl; this.changed = changed;
    this.configFile = path.join(directory, 'hub-sync.json'); this.stateFile = path.join(directory, 'hub-baseline.json');
    this.cacheFile = path.join(directory, 'hub-cache.json');
    this.config = load(this.configFile, { enabled: false }); this.state = load(this.stateFile, null); this.cache = load(this.cacheFile, null);
    this.lastSuccess = this.cache?.syncedAt || null; this.error = null; this.running = false; this.pending = null; this.delay = 30000;
    this.timer = setInterval(() => { if (this.config.enabled) void this.flush(); }, 30000); this.timer.unref();
  }
  status() { return { enabled: this.config.enabled, configured: !!this.config.address, address: this.config.address || '', deviceId: this.config.deviceId || '', lastSuccess: this.lastSuccess, error: this.error, errorDetail: this.errorDetail || null, durationMs: this.durationMs || null, syncing: this.running }; }
  async request(endpoint, body) {
    if (!this.secretPromise) this.secretPromise = Promise.resolve(this.credential(this.config.address)).catch(() => null);
    const secret = await this.secretPromise;
    if (!secret) this.secretPromise = null;
    if (!secret) throw Error('credentialUnavailable');
    const response = await this.fetch(new URL(endpoint, this.config.address.replace(/\/?$/, '/')), {
      method: body ? 'POST' : 'GET', headers: { Authorization: `Bearer ${secret}`, 'Content-Type': 'application/json' },
      ...(body ? { body: JSON.stringify(body) } : {}), signal: AbortSignal.timeout(45000), redirect: 'error'
    });
    if (response.status === 401) this.secretPromise = null;
    if (!response.ok) throw Error(response.status === 401 ? 'unauthorized' : response.status === 429 ? 'rateLimited' : 'hubUnavailable');
    return response.json();
  }
  async configure(config, local) {
    if (this.running) throw Error('busy');
    if (config.enabled === false) { this.config.enabled = false; atomic(this.configFile, this.config); this.changed(); return; }
    const url = new URL(config.address);
    if (!['http:','https:'].includes(url.protocol) || url.username || url.password || url.search || url.hash || !config.deviceId) throw Error('invalidConfiguration');
    if (!local?.history) throw Error('localHistoryNotReady');
    if (config.secret !== undefined && !validSecret(config.secret)) throw Error('invalidCredential');
    const previous = this.config;
    this.secretPromise = config.secret === undefined ? null : Promise.resolve(config.secret);
    this.config = { address: url.toString().replace(/\/$/, ''), deviceId: config.deviceId, enabled: false };
    try {
      const devices = (await this.request('api/devices')).devices;
      const matches = devices.filter(d => d.deviceId === config.deviceId);
      if (matches.length !== 1) throw Error('deviceNotMatched');
      const needsBaseline = !this.state || previous.address !== this.config.address || previous.deviceId !== config.deviceId;
      if (needsBaseline && this.state) throw Error('existingBaselineRequiresExplicitReset');
      const nextState = needsBaseline ? initializeBaseline(matches[0], local) : this.state;
      if (config.secret !== undefined) {
        if (!this.persistCredential) throw Error('credentialSaveFailed');
        await this.persistCredential(this.config.address, config.secret);
      }
      if (needsBaseline) {
        atomic(path.join(this.directory, 'hub-remote-before-handoff.json'), matches[0]);
        atomic(path.join(this.directory, 'hub-handoff-backup.json'), nextState);
        atomic(this.stateFile, nextState); this.state = nextState;
      }
      this.config.enabled = true; atomic(this.configFile, this.config);
      this.retryAt = 0; this.delay = 30000;
      this.pending = local; await this.flush();
    } catch (error) { this.config = previous; this.secretPromise = null; throw error; }
  }
  enqueue(record) { if (!this.config.enabled) return; this.pending = clone(record); void this.flush(); }
  async flush() {
    if (this.running || !this.config.enabled || Date.now() < (this.retryAt || 0)) return;
    this.running = true; this.startedAt = Date.now(); this.stage = 'baseline';
    try {
      const record = this.pending; this.pending = null;
      if (record) {
        if (!this.state) throw Error('baselineMissing');
        this.state = advanceRecord(this.state, record); this.state.pendingUpload = true; atomic(this.stateFile, this.state);
      }
      // Retry the same absolute snapshot after uncertain delivery; never add a delta twice.
      if (this.state?.pendingUpload) {
        this.stage = 'upload'; await this.request('api/ingest', this.state.output);
        this.state.pendingUpload = false; atomic(this.stateFile, this.state);
      }
      this.stage = 'read';
      const [stats, history] = await Promise.all([this.request('api/stats'), this.request('api/history')]);
      this.stage = 'cache'; this.cache = { stats, history, syncedAt: new Date().toISOString() }; atomic(this.cacheFile, this.cache);
      this.lastSuccess = this.cache.syncedAt; this.error = null; this.errorDetail = null; this.delay = 30000;
    } catch (e) {
      this.errorDetail = this.stage + ':' + String(e.cause?.code || e.code || e.name).replace(/[^a-zA-Z0-9_]/g, '').slice(0, 40);
      this.error = ['credentialUnavailable','unauthorized','rateLimited','baselineMissing'].includes(e.message) ? e.message : 'hubUnavailable';
      this.retryAt = Date.now() + this.delay; this.delay = Math.min(300000, this.delay * 2);
    } finally { this.durationMs = Date.now() - this.startedAt; this.running = false; this.changed(); }
  }
  close() { clearInterval(this.timer); }
}
module.exports = { HubSync, advance, advanceRecord, initializeBaseline };
