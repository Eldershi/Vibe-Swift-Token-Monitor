'use strict';
const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const { advanceRecord, HubSync, initializeBaseline } = require('../hub-sync.cjs');
function record(n, date = '2026-09-13') {
  const period = { totalTokens:n, costUsd:n/100, clients:{codex:n}, models:{test:n}, clientModels:{codex:{test:n}}, sessions:{},projects:{} };
  return {deviceId:'existing',updatedAt: date+'T12:00:00Z', periods: {today:structuredClone(period),month:structuredClone(period),allTime:structuredClone(period)}, periodWindows:{today:{key:date},month:{key:date.slice(0,7)}}, history:{daily:[{date,tokens:n,cost:n/100,perClient:{codex:{tokens:n,cost:n/100}},perModel:{test:{tokens:n}}}],monthly:[{month:date.slice(0,7),tokens:n,cost:n/100}]}, trackedClients:['codex'],clientStatus:{codex:{status:'ok'}},limits:{providers:[]} };
}
test('handoff preserves remote totals and missing history; append, truncate, replay and restart are idempotent', () => {
  const remote=record(1000); remote.history.daily.unshift({date:'2026-01-01',tokens:40});
  const local=record(100); let state={output:remote,seen:local};
  state=advanceRecord(state,local); assert.equal(state.output.periods.allTime.totalTokens,1000);
  state=advanceRecord(state,record(130)); assert.equal(state.output.periods.allTime.totalTokens,1030);
  assert.equal(state.output.history.daily[1].perModel.test.tokens,1030);
  state=advanceRecord(JSON.parse(JSON.stringify(state)),record(40));
  state=advanceRecord(state,record(130)); assert.equal(state.output.periods.allTime.totalTokens,1030);
  assert.equal(state.output.history.daily[0].tokens,40);
});
test('new dates and months reset window snapshots but preserve all-time and daily history', () => {
  let state={output:record(1000),seen:record(100)};
  const next=record(20,'2026-10-01'); next.periods.allTime=record(120).periods.allTime;
  state=advanceRecord(state,next);
  assert.equal(state.output.periods.today.totalTokens,20); assert.equal(state.output.periods.month.totalTokens,20);
  assert.equal(state.output.periods.allTime.totalTokens,1020); assert.equal(state.output.history.daily.length,2);
});
test('cost, real zero and absent tools remain distinct; unsupported tool timestamps stay unchanged', () => {
  const remote=record(1000);remote.periods.allTime.clients.claude=0;remote.clientStatus.other={status:'ok',updatedAt:'2026-01-01'};
  const state=advanceRecord({output:remote,seen:record(100)},record(125));
  assert.equal(state.output.periods.allTime.costUsd,10.25);
  assert.equal(state.output.agentVersion,'0.6.0');
  assert.equal(state.output.periods.allTime.clients.claude,0);assert.equal(state.output.periods.allTime.clients.missing,undefined);
  assert.equal(state.output.clientStatus.other.updatedAt,'2026-01-01');
});
test('serial upload, persisted retry snapshot, 429 and disabled state', async () => {
  const directory=fs.mkdtempSync(path.join(os.tmpdir(),'beta-sync-test-'));let active=0,peak=0,posts=[];let fail=false;
  const sync=new HubSync({directory,credential:async()=> 'test-secret',fetchImpl:async(url,opts)=>{
    active++;peak=Math.max(active,peak);await new Promise(r=>setTimeout(r,2));active--;
    if(opts.method==='POST'){ posts.push(JSON.parse(opts.body));if(fail)return{ok:false,status:429}; }
    return {ok:true,json:async()=>String(url).endsWith('/devices')?{devices:[record(1000)]}:String(url).endsWith('/history')?record(1).history:{devices:[]}};
  }});
  try {
    await sync.configure({enabled:true,address:'https://hub.example',deviceId:'existing'},record(100));
    assert.equal(posts[0].periods.allTime.totalTokens,1000);
    fail=true;sync.pending=record(150);await sync.flush();assert.equal(sync.status().error,'rateLimited');
    fail=false;sync.retryAt=0;await sync.flush();assert.equal(posts.at(-1).periods.allTime.totalTokens,1050);
    assert.equal(fs.statSync(path.join(directory,'hub-baseline.json')).mode & 0o777,0o600);
    await sync.configure({enabled:false});const n=posts.length;sync.enqueue(record(200));await sync.flush();assert.equal(posts.length,n);
    // Reads may run in parallel, but there is never a second upload loop.
    assert.ok(peak<=2);
    const restored=new HubSync({directory,credential:async()=>null});assert.equal(restored.config.enabled,false);restored.close();
  } finally {sync.close();fs.rmSync(directory,{recursive:true,force:true});}
});

test('initial catch-up includes unsent local growth while retaining remote-only tools', () => {
  const remote=record(1000); remote.periods.allTime.clients.other=50;remote.periods.allTime.totalTokens=1050;
  const state=initializeBaseline(remote,record(1100));
  assert.equal(state.output.periods.allTime.totalTokens,1150);
  assert.equal(state.output.periods.allTime.clients.codex,1100);
  assert.equal(advanceRecord(state,record(1100)).output.periods.allTime.totalTokens,1150);
});

test('collector raw envelope is normalized before baseline updates, including quota-only writes', () => {
  const {mergeDeviceRecord}=require('../vendor/src/shared/usage');
  const raw={deviceId:'existing',today:{totalTokens:100,clients:{codex:100}},month:{totalTokens:100,clients:{codex:100}},allTime:{totalTokens:100,clients:{codex:100}},history:record(100).history};
  const normalized=mergeDeviceRecord(null,raw);
  assert.ok(normalized.periods.today);
  const baseline=initializeBaseline(normalized,normalized);
  const quota=mergeDeviceRecord(normalized,{deviceId:'existing',limitsOnly:true,limits:{providers:[]}});
  assert.equal(advanceRecord(baseline,quota).output.periods.allTime.totalTokens,100);
});
