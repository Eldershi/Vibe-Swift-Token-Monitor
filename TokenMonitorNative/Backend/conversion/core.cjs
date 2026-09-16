'use strict';
const crypto = require('node:crypto');
const hash = value => crypto.createHash('sha256').update(typeof value === 'string' ? value : JSON.stringify(value)).digest('hex');
const iso = value => typeof value === 'string' && Number.isFinite(Date.parse(value)) ? new Date(value).toISOString() : null;
const finite = n => typeof n === 'number' && Number.isFinite(n) && n >= 0;
const accountId = key => typeof key === 'string' && key.trim() ? hash('codex\n' + key.slice(0,256)) : null;
function currentWindow(observation, window, now = new Date().toISOString()) {
  if (observation.provider !== 'codex' || !['ok','rateLimited'].includes(observation.status) || !observation.sourceTimeKnown) return { reason: 'observationUnavailable' };
  if (!['session','weekly','daily'].includes(window.kind) || (window.boundaryKind != null && window.boundaryKind !== 'fixed') || window.rolling === true) return { reason: 'windowUnsupported' };
  const seconds = window.windowSeconds, minutes = window.windowMinutes;
  if ((seconds != null && (!finite(seconds) || seconds <= 0)) || (minutes != null && (!finite(minutes) || minutes <= 0))) return { reason: 'windowDurationUnknown' };
  if (seconds != null && minutes != null && Math.abs(seconds - minutes * 60) > 0.001) return { reason: 'windowDurationConflict' };
  const duration = seconds ?? (minutes == null ? null : minutes * 60);
  const end = iso(window.resetsAt), observed = iso(observation.sourceObservedAt);
  if (!duration || duration > 366 * 86400 || !end || !observed) return { reason: 'windowDurationUnknown' };
  const start = new Date(Date.parse(end) - duration * 1000).toISOString();
  if (observed < start || observed >= end) return { reason: 'windowObservationMismatch' };
  if (now >= end || Date.parse(now) - Date.parse(observed) > 600000 || Date.parse(observed) > Date.parse(now) + 60000) return { reason: 'observationExpired' };
  const remaining = window.remainingPercent ?? (finite(window.usedPercent) ? 100 - window.usedPercent : null);
  if (!finite(remaining) || remaining > 100 || (window.usedPercent != null && Math.abs(remaining + window.usedPercent - 100) > 0.01)) return { reason: 'percentInvalid' };
  return { start, end, observedAt: observed, used: 100 - remaining, remaining, inferred: true, durationSeconds: duration };
}
function priceFor(event, versions, simulate = false) {
  const sorted = versions.filter(v => v.unit === 'credits').sort((a,b) => a.fetchedAt.localeCompare(b.fetchedAt));
  const candidates = simulate ? sorted : sorted.filter(v => (v.effectiveFrom || v.fetchedAt) <= event.occurredAt);
  const version = candidates.at(-1);
  if (!version) return null;
  // A change without an effective date leaves the interval between checks ambiguous.
  if (!simulate && sorted.some(v => v.id !== version.id && !v.effectiveFrom && v.previousCheckedAt && event.occurredAt >= v.previousCheckedAt && event.occurredAt < v.fetchedAt)) return null;
  const row = version.rates.find(r => r.model === event.model && r.tier === event.serviceTier);
  if (!row || ![row.input,row.cached,row.output].every(finite)) return null;
  return { version, row };
}
function weight(event, priced) {
  if (!priced || ![event.input,event.cached,event.output].every(finite) || event.cached > event.input) return null;
  const { row } = priced;
  const value = ((event.input-event.cached)*row.input + event.cached*row.cached + event.output*row.output)/1e6;
  return Number.isFinite(value) ? value : null;
}
function bindingFor(event, bindings) {
  if (event.accountId) return event.accountId;
  const matches = bindings.filter(b => b.deviceId === event.deviceId && b.from <= event.occurredAt && (!b.to || b.to >= event.occurredAt));
  const accounts = [...new Set(matches.map(b=>b.accountId))];
  return accounts.length === 1 ? accounts[0] : null;
}
function covered(deviceId, from, to, coverage) {
  let cursor = from;
  const rows = coverage.filter(c => c.deviceId === deviceId && c.complete && c.from && c.to).sort((a,b)=>a.from.localeCompare(b.from));
  for (const c of rows) {
    if (c.from > cursor) continue;
    if ((c.gaps || []).some(g => g.from < to && g.to > from)) continue;
    if (c.to > cursor) cursor = c.to;
    if (cursor >= to) return true;
  }
  return false;
}
function calculate({ observation, window, events = [], coverage = [], bindings = [], versions = [], scope, previous = [], now = new Date().toISOString() }) {
  const range = currentWindow(observation, window, now);
  const base = { schemaVersion:1, range, mode:'currentWindow', devices:[], models:[], totalWeight:0, simulationWeight:0, unknownTokens:0, priceVersionIds:[], remainingTokens:null, reasons:[] };
  if (range.reason) {
    const rows=new Map(),latest=new Map();for(const e of events){const key=e.deviceId+':'+(e.eventKey||e.id);if(!latest.has(key)||(latest.get(key).revision||1)<=(e.revision||1))latest.set(key,e);}
    for(const e of latest.values()){const tokens=e.input+e.output;if(!Number.isFinite(tokens))continue;const amount=weight(e,priceFor(e,versions));const row=rows.get(e.deviceId)||{id:e.deviceId,tokens:0,weight:0,unknownTokens:0,quota:null};row.tokens+=tokens;row.weight+=amount||0;row.unknownTokens+=amount==null?tokens:0;rows.set(e.deviceId,row);}
    const devices=[...rows.values()];return {...base,mode:'unmatched',devices,totalWeight:devices.reduce((n,r)=>n+r.weight,0),unknownTokens:devices.reduce((n,r)=>n+r.unknownTokens,0),reasons:[range.reason]};
  }
  if (!observation.accountId) base.reasons.push('accountUnknown');
  const latestCorrection = new Map();
  for (const e of events) { const key = e.deviceId + ':' + (e.eventKey || e.id); const old = latestCorrection.get(key); if (!old || (e.revision || 1) >= (old.revision || 1)) latestCorrection.set(key,e); }
  const all = [...latestCorrection.values()];
  const requested = scope?.deviceIds || [];
  const scopeValid = scope?.confirmed === true && scope.accountId === observation.accountId && scope.from <= range.observedAt && (!scope.to || scope.to >= range.observedAt) && requested.length > 0;
  if (!scopeValid) base.reasons.push('accountScopeUnconfirmed');
  let start = range.start, used = range.used;
  const complete = (from) => scopeValid && scope.from <= from && requested.every(id => covered(id,from,range.observedAt,coverage));
  const lane = w => [w.kind,w.limitId || '',w.additional || false,w.resetsAt,w.windowMinutes ?? '',w.windowSeconds ?? ''].join('|');
  const priorRows = previous.filter(o => o.accountId === observation.accountId && o.provider === observation.provider && o.planLabel === observation.planLabel && o.sourceTimeKnown && ['ok','rateLimited'].includes(o.status) && o.sourceObservedAt >= range.start && o.sourceObservedAt < range.observedAt);
  if (priorRows.some(o => o.windows.some(w => lane(w) === lane(window) && finite(w.remainingPercent) && w.remainingPercent < range.remaining))) base.reasons.push('intervalIncomparable');
  if (!complete(start)) {
    const candidate = priorRows.sort((a,b)=>a.sourceObservedAt.localeCompare(b.sourceObservedAt)).find(o => {
      const w = o.windows.find(w=>lane(w)===lane(window));
      return w && finite(w.remainingPercent) && w.remainingPercent-range.remaining >= 5 && complete(o.sourceObservedAt);
    });
    if (candidate) { start = candidate.sourceObservedAt; used = candidate.windows.find(w=>lane(w)===lane(window)).remainingPercent-range.remaining; base.mode='coveredInterval'; }
    else base.reasons.push('coverageIncomplete');
  }
  base.range = { ...range, calculationStart:start, used };
  const devices = new Map(), models = new Map();
  const selected = all.filter(e => e.occurredAt >= start && e.occurredAt <= range.observedAt);
  for (const e of selected) {
    const bound = bindingFor(e,bindings);
    if (bound && bound !== observation.accountId) continue;
    if (!bound) base.reasons.push('accountUnknown');
    if (scopeValid && !requested.includes(e.deviceId)) { base.reasons.push('accountScopeIncomplete'); }
    const tokens = e.input + e.output;
    const priced = priceFor(e, versions), amount = weight(e,priced), simulation = weight(e,priceFor(e,versions,true));
    if (simulation != null) base.simulationWeight += simulation;
    if (amount == null) { base.unknownTokens += tokens; base.reasons.push(e.serviceTier==='unknown'?'serviceTierUnknown':![e.input,e.cached,e.output].every(finite)?'tokenClassificationUnknown':!versions.some(v=>v.rates.some(r=>r.model===e.model))?'modelPriceUnknown':'pricingUnknown'); }
    else { base.totalWeight += amount; base.priceVersionIds.push(priced.version.id); }
    for (const [map,id] of [[devices,e.deviceId],[models,e.model]]) {
      const row = map.get(id) || { id,tokens:0,weight:0,unknownTokens:0,quota:null };
      row.tokens += tokens; row.weight += amount || 0; row.unknownTokens += amount == null ? tokens : 0; map.set(id,row);
    }
  }
  base.devices=[...devices.values()];base.models=[...models.values()];
  if (!base.totalWeight) base.reasons.push('noPricedUsage');
  if (![base.totalWeight,base.simulationWeight,base.unknownTokens].every(Number.isFinite)) base.reasons.push('invalidTotals');
  for (const row of [...base.devices,...base.models]) row.share=base.totalWeight>0?row.weight/base.totalWeight:0;
  const trusted = base.reasons.length===0;
  base.attributionAvailable = trusted;
  if (trusted) for (const row of [...base.devices,...base.models]) row.quota=used*row.share;
  base.priceVersionIds=[...new Set(base.priceVersionIds)];base.reasons=[...new Set(base.reasons)];return base;
}
module.exports={hash,iso,finite,accountId,currentWindow,priceFor,weight,bindingFor,covered,calculate};
