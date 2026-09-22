import test from 'node:test';
import assert from 'node:assert/strict';
import { reduceCycle, cycleIdentity } from '../src/quotaCycleReducer.js';
import { appendCycleObservation, readCycleHistory } from '../src/quotaCycles.js';

const T = Date.parse('2026-01-01T00:00:00.000Z');
const WEEK = 7 * 24 * 3600;
const iso = seconds => new Date(T + seconds * 1000).toISOString();
function report(at, end = WEEK, used = 0, options = {}) {
  const { window: windowOptions, ...reportOptions } = options;
  return { id: 'synthetic-' + at + '-' + end, sourceDeviceId: 'synthetic-mac',
    provider: 'codex', accountId: 'synthetic-account', status: 'ok',
    sourceObservedAt: iso(at), receivedAt: iso(at + 1),
    windows: [{kind: 'weekly', limitId: 'codex', windowMinutes: 10080,
      usedPercent: used, resetsAt: iso(end), ...windowOptions}], ...reportOptions };
}
function next(state, row) { return reduceCycle(state, row, row.windows[0]); }
function confirmed(at = 100, end = WEEK) {
  const first = next(null, report(at, end, 20));
  return next(first.state, report(at + 60, end, 21));
}
class MemoryStore {
  constructor(entries = []) { this.entries = new Map(entries); }
  async get(key) { return structuredClone(this.entries.get(key)); }
  async put(key, value) { this.entries.set(key, structuredClone(value)); }
  async list(o) {
    return new Map([...this.entries].sort(([a], [b]) => a.localeCompare(b)).filter(([key]) =>
      key.startsWith(o.prefix) && (!o.start || key >= o.start) &&
      (!o.startAfter || key > o.startAfter) && (!o.end || key < o.end)).slice(0, o.limit));
  }
  async transaction(body) {
    const copy = new MemoryStore(structuredClone([...this.entries]));
    const value = await body(copy); this.entries = copy.entries; return value;
  }
}
const history = store => readCycleHistory(store, new URL('https://example.invalid/api/quota/cycles?to=2027-01-01T00:00:00Z'));

test('derive start from stable deadline without a drop in percent', () => {
  const result = confirmed();
  assert.equal(result.reason, 'confirmed');
  assert.equal(result.event.inferredStartAt, iso(0));
  assert.equal(result.event.kind, 'initialDiscovery');
  assert.equal(result.event.firstUsedPercent, 20);
  assert.equal(result.event.latestUsedPercent, 21);
  assert.notEqual(result.event.inferredStartAt, result.event.confirmedAt);
});
test('additional replenishment creates a new cycle from the new deadline', () => {
  let state = confirmed().state;
  state = next(state, report(4000, WEEK + 3900, 25)).state;
  const result = next(state, report(4060, WEEK + 3900, 26));
  assert.equal(result.event.kind, 'cycleChanged');
  assert.equal(result.event.inferredStartAt, iso(3900));
  assert.equal(result.event.previousStartAt, iso(0));
  assert.equal(result.event.cause, 'unspecified');
});
test('a percentage drop with an unchanged deadline creates no invented cycle', () => {
  const result = next(confirmed().state, report(1000, WEEK, 0));
  assert.equal(result.reason, 'unchanged'); assert.equal(result.event, null);
});
test('zero-use deadlines that move with the clock remain pending', () => {
  let state;
  for (let at = 0; at <= 600; at += 60) {
    const r = next(state, report(at, WEEK + at)); state = r.state;
    assert.equal(r.reason, 'pending'); assert.equal(r.event, null);
  }
});
test('after idle drift, stabilized deadline produces one start', () => {
  let state = next(null, report(0, WEEK)).state;
  state = next(state, report(300, WEEK + 300)).state;
  state = next(state, report(600, WEEK + 500, 1)).state;
  const result = next(state, report(900, WEEK + 500, 1));
  assert.equal(result.event.inferredStartAt, iso(500));
});
test('zero percent can confirm if the actual deadline is stable', () => {
  const first = next(null, report(100));
  assert.equal(next(first.state, report(160)).reason, 'confirmed');
});
test('jitter within two seconds does not split a confirmed cycle', () => {
  let state = confirmed().state;
  for (let n = 1; n <= 5; n++) {
    const r = next(state, report(200 + n * 60, WEEK + (n % 2 ? 1 : -1)));
    assert.equal(r.reason, 'unchanged'); state = r.state;
  }
});
test('slow jitter drift compares against anchor, not successive samples', () => {
  let state;
  for (let at = 0; at < 100; at += 10) {
    const r = next(state, report(at, WEEK + at / 10)); state = r.state;
    assert.equal(r.event, null);
  }
});
test('cached duplicate source timestamp cannot confirm across devices', () => {
  const first = next(null, report(100));
  const r = next(first.state, report(100, WEEK, 0, {id:'same-source-new-id',sourceDeviceId:'synthetic-pc',receivedAt:iso(200)}));
  assert.equal(r.reason, 'stale'); assert.equal(r.event, null);
});
test('two fresh sources of one account can corroborate one event', async () => {
  const store = new MemoryStore();
  await appendCycleObservation(store, report(100));
  await appendCycleObservation(store, report(160, WEEK, 2, {sourceDeviceId:'synthetic-pc'}));
  const events = (await history(store)).events;
  assert.equal(events.length, 1);
  assert.deepEqual(events[0].evidenceDevices, ['synthetic-mac','synthetic-pc']);
});
test('unknown accounts are device-scoped and cannot merge', async () => {
  const store = new MemoryStore();
  await appendCycleObservation(store, report(100, WEEK, 0, {accountId:null}));
  await appendCycleObservation(store, report(160, WEEK, 0, {accountId:null,sourceDeviceId:'synthetic-pc'}));
  assert.equal((await history(store)).events.length, 0);
  await appendCycleObservation(store, report(220, WEEK, 1, {accountId:null}));
  assert.equal((await history(store)).events[0].identityConfidence, 'deviceOnly');
});
test('accounts, Spark, and duration changes have independent timelines', async () => {
  const store = new MemoryStore();
  const options = [ {}, {accountId:'synthetic-account-b'}, {window:{limitId:'codex_bengalfox'}},
    {window:{windowMinutes:120,kind:'session'}} ];
  for (const opt of options) for (const at of [100,160]) {
    await appendCycleObservation(store, report(at, opt.window?.windowMinutes ? 7200 : WEEK, 1, opt));
  }
  assert.equal((await history(store)).events.length, 4);
});
test('stale, unhealthy, rolling, unsupported and missing source time do not confirm', () => {
  for (const [row, reason] of [
    [report(100,WEEK,1,{receivedAt:iso(2000)}),'delayed'],
    [report(100,WEEK,1,{status:'unauthorized'}),'unhealthy'],
    [report(100,WEEK,1,{window:{rolling:true}}),'unsupported'],
    [report(100,WEEK,1,{provider:'unverified-provider'}),'unsupported'],
    [report(100,WEEK,1,{sourceObservedAt:null}),'invalid'],
    [report(100,WEEK,1,{window:{windowSeconds:3600}}),'invalid'],
  ]) assert.equal(next(null,row).reason, reason);
});
test('invalid time, expired deadline, and impossible future start are rejected', () => {
  for (const row of [report(100,50),report(100,WEEK+500),report(100,WEEK,0,{receivedAt:iso(0)}),
    report(100,WEEK,0,{window:{resetsAt:'not-a-date'}})]) {
    assert.equal(next(null,row).reason,'invalid');
  }
});
test('late observation and backward deadline cannot roll state back', () => {
  const state = confirmed().state;
  assert.equal(next(state,report(150,WEEK+100)).reason,'stale');
  assert.equal(next(state,report(200,WEEK-100)).reason,'regressed');
  assert.equal(state.active.inferredStartAt,iso(0));
});
test('duration arithmetic uses seconds even across DST calendar shifts', () => {
  const row = report(100);
  row.sourceObservedAt='2026-03-09T12:00:00Z';row.receivedAt='2026-03-09T12:00:01Z';
  row.windows[0].resetsAt='2026-03-15T12:00:00Z';
  const first=next(null,row);
  const second=structuredClone(row);second.id='dst-second';second.sourceObservedAt='2026-03-09T12:01:00Z';second.receivedAt='2026-03-09T12:01:01Z';
  assert.equal(next(first.state,second).event.inferredStartAt,'2026-03-08T12:00:00.000Z');
});
test('pending state survives restart and repeated replay stays idempotent', async () => {
  let store=new MemoryStore();await appendCycleObservation(store,report(100));
  store=new MemoryStore(JSON.parse(JSON.stringify([...store.entries])));
  await appendCycleObservation(store,report(160));
  const saved=JSON.stringify([...store.entries]);
  await appendCycleObservation(store,report(100));await appendCycleObservation(store,report(160));
  assert.equal(JSON.stringify([...store.entries]),saved);
  assert.equal((await history(store)).events.length,1);
});
test('transaction failure does not commit raw report without derived state', async () => {
  const store=new MemoryStore();await appendCycleObservation(store,report(100));
  const saved=JSON.stringify([...store.entries]);
  await assert.rejects(store.transaction(async tx=>{
    await tx.put('raw:synthetic',report(160));await appendCycleObservation(tx,report(160));
    throw new Error('synthetic crash before commit');
  }));
  assert.equal(JSON.stringify([...store.entries]),saved);
});
test('paginated event history uses discovery time and validates cursors', async () => {
  const store=new MemoryStore();
  for (const at of [100,160]) await appendCycleObservation(store,report(at));
  for (const at of [4000,4060]) await appendCycleObservation(store,report(at,WEEK+3900));
  const url=new URL('https://example.invalid/api/quota/cycles?limit=1&to=2027-01-01T00:00:00Z');
  const first=await readCycleHistory(store,url);assert.equal(first.events.length,1);assert(first.nextCursor);
  url.searchParams.set('cursor',first.nextCursor);
  const second=await readCycleHistory(store,url);assert.equal(second.events.length,1);assert.equal(second.nextCursor,null);
  assert.notEqual(first.events[0].id,second.events[0].id);
  url.searchParams.set('cursor','dev:another-record');assert.equal((await readCycleHistory(store,url)).error,'invalid_cursor');
});
test('a reducer state from another account or policy is not silently adopted', () => {
  const state=confirmed().state;
  assert.throws(()=>next(state,report(200,WEEK,1,{accountId:'synthetic-different'})),/contract_mismatch/);
  assert.throws(()=>next({...state,policyVersion:99},report(200)),/contract_mismatch/);
  assert.equal(cycleIdentity(report(100),report(100).windows[0]).durationMs,WEEK*1000);
});

test('backfill cursor and events resume atomically, with repeat and incremental catch-up', async () => {
  const {backfillCycleHistory}=await import('../src/quotaCycles.js');
  const store=new MemoryStore();
  for(const row of[report(100),report(160),report(4000,WEEK+3900),report(4060,WEEK+3900)]) {
    await store.put('quota:v1:observation:'+row.receivedAt+':'+row.id,row);
  }
  let progress=await backfillCycleHistory(store,{through:iso(200),limit:1});assert(!progress.complete);
  progress=await backfillCycleHistory(store,{through:iso(200),limit:1});assert(progress.complete);assert.equal(progress.count,2);
  assert.deepEqual(await backfillCycleHistory(store,{through:iso(200),limit:1}),progress);
  progress=await backfillCycleHistory(store,{through:iso(5000),limit:2});assert(progress.complete);assert.equal(progress.count,4);
  assert.equal((await history(store)).events.length,2);
  await assert.rejects(backfillCycleHistory(store,{through:iso(100)}),/regressed/);
});


test('legacy seconds and minutes describe the same account timeline', () => {
  const first = report(100);
  const second = report(160, WEEK, undefined, {window: {windowMinutes: undefined, windowSeconds: WEEK, usedPercent: undefined, percent: 4}});
  assert.deepEqual(cycleIdentity(first, first.windows[0]), cycleIdentity(second, second.windows[0]));
  const result = next(next(null, first).state, second);
  assert.equal(result.reason, 'confirmed');
  assert.equal(result.event.latestUsedPercent, null);
});
test('missing window identity and unknown schemas preserve raw-only eligibility', () => {
  assert.equal(next(null, report(100, WEEK, 0, {window: {limitId: undefined}})).reason, 'invalid');
  assert.equal(next(null, report(100, WEEK, 0, {schemaVersion: 2})).reason, 'unsupported_schema');
});
test('a regressed deadline breaks a pending confirmation sequence', () => {
  let state = confirmed().state;
  state = next(state, report(4000, WEEK + 3900)).state;
  const regressed = next(state, report(4030, WEEK - 100));
  assert.equal(regressed.reason, 'regressed');
  const result = next(regressed.state, report(4060, WEEK + 3900));
  assert.equal(result.reason, 'pending');
  assert.equal(result.event, null);
});
