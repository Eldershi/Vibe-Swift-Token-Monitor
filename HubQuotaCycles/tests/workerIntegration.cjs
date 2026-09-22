const test = require('node:test');
const assert = require('node:assert/strict');
async function setup(enabled = true) {
  const { HubDO } = await import('../../worker/src/index.js');
  const map = new Map(); let fail = false;
  const storage = {
    async get(key) { return structuredClone(map.get(key)); },
    async put(key, value) { if (fail && key.startsWith('dev:')) throw Error('synthetic failure'); map.set(key, structuredClone(value)); },
    async delete(key) { map.delete(key); },
    async list(o = {}) { return new Map([...map].sort(([a],[b])=>a.localeCompare(b)).filter(([k]) =>
      (!o.prefix||k.startsWith(o.prefix)) && (!o.start||k>=o.start) && (!o.startAfter||k>o.startAfter) && (!o.end||k<o.end)).slice(0,o.limit??Infinity)); },
    async transaction(body) { const before=structuredClone(map);try{return await body(this);}catch(e){map.clear();for(const [k,v]of before)map.set(k,v);throw e;} },
  };
  const hub = new HubDO({storage}, {TOKEN_MONITOR_SECRET:'synthetic-secret',QUOTA_CYCLES_ENABLED:enabled?'true':'false'});
  const call = (route, body, auth=true) => hub.fetch(new Request('https://test.invalid'+route,{
    method:body?'POST':'GET',headers:{...(auth?{authorization:'Bearer synthetic-secret'}:{}),'content-type':'application/json'},
    ...(body?{body:JSON.stringify(body)}:{}),
  }));
  return {call,map,storage,hub,fail:()=>{fail=true;}};
}
const base=Date.now()-300000;
function payload(delta=0){return{deviceId:'synthetic-device',today:{totalTokens:123},limits:{providers:[{
 provider:'codex',status:'ok',source:'oauth',accountKey:'synthetic-account',updatedAt:new Date(base+delta).toISOString(),
 windows:[{kind:'weekly',limitId:'codex',windowMinutes:10080,usedPercent:20+delta/60000,resetsAt:new Date(base-300000+604800000).toISOString()}]
}]}};}
test('cycle records follow authenticated fresh ingestion while old clients remain compatible',async()=>{
 const s=await setup();for(const data of[payload(),payload(60000),payload(60000)])assert.equal((await s.call('/api/ingest',data)).status,200);
 const cycles=await(await s.call('/api/quota/cycles')).json();assert.equal(cycles.events.length,1);
 assert.equal(cycles.events[0].inferredStartAt,new Date(base-300000).toISOString());
 assert.equal((await s.call('/api/quota/cycles',null,false)).status,401);
 assert.equal((await s.call('/api/quota/cycles?cursor=dev:bad')).status,400);
 const stats=await(await s.call('/api/stats')).json();assert(!('events'in stats));
 assert.equal((await s.call('/api/ingest',{id:'synthetic-device',today:{totalTokens:456}})).status,200);
 assert.equal((await(await s.call('/api/quota/history')).json()).observations.length,2);
 assert.equal((await(await s.call('/api/quota/cycles')).json()).events.length,1);
 assert.equal((await(await s.call('/api/devices')).json()).devices[0].periods.today.totalTokens,456);
});
test('feature off leaves existing ingestion and quota history working',async()=>{
 const s=await setup(false);await s.call('/api/ingest',payload());await s.call('/api/ingest',payload(60000));
 assert.equal((await s.call('/api/quota/cycles')).status,404);
 assert.equal((await(await s.call('/api/health')).json()).quotaCycleVersion,0);
 assert.equal((await(await s.call('/api/quota/history')).json()).observations.length,2);
 assert(![...s.map.keys()].some(k=>k.startsWith('quota:cycles:')));
});
test('device write failure rolls raw observation and inferred cycle back together',async()=>{
 const s=await setup();await s.call('/api/ingest',payload());const before=JSON.stringify([...s.map]);s.fail();
 await assert.rejects(()=>s.call('/api/ingest',payload(60000)));
 assert.equal(JSON.stringify([...s.map]),before);
});
test('quota-only upload keeps existing usage while contributing cycle evidence',async()=>{
 const s=await setup();await s.call('/api/ingest',payload());
 const second=payload(60000);delete second.today;second.limitsOnly=true;
 assert.equal((await s.call('/api/ingest',second)).status,200);
 assert.equal((await(await s.call('/api/devices')).json()).devices[0].periods.today.totalTokens,123);
 assert.equal((await(await s.call('/api/quota/cycles')).json()).events.length,1);
});

test('bounded backfill serializes concurrent ingest and resumes across restart', async()=>{
 const s=await setup(false);
 const now=Date.now();
 // Populate raw history without touching device records or relying on live clock waits.
 for(let i=0;i<245;i++){
  const at=new Date(now-600000+i*1000).toISOString();
  const row={schemaVersion:1,id:'synthetic-'+i,provider:'codex',status:'ok',sourceDeviceId:'synthetic-history',accountId:'synthetic-account',
   sourceObservedAt:at,receivedAt:at,windows:[{kind:'weekly',limitId:'codex',windowMinutes:10080,usedPercent:20,resetsAt:new Date(now-700000+604800000).toISOString()}]};
  s.map.set('quota:v1:observation:'+at+':'+row.id,row);
 }
 s.hub.env.QUOTA_CYCLES_ENABLED='true';
 const first=await(await s.call('/api/health')).json();assert.equal(first.quotaCycleVersion,0);
 const requests=await Promise.all([s.call('/api/ingest',payload()),s.call('/api/ingest',payload(60000)),s.call('/api/health')]);
 assert(requests.every(r=>r.status===200));
 assert.equal((await(await s.call('/api/health')).json()).quotaCycleVersion,1);
 const before=[...s.map].filter(([k])=>k.startsWith('quota:cycles:v1:event:'));
 assert.equal(before.length,2);
 const {HubDO}=await import('../../worker/src/index.js');
 const restarted=new HubDO({storage:s.storage},s.hub.env);
 for(let i=0;i<4;i++)await restarted.fetch(new Request('https://test.invalid/api/health'));
 assert.deepEqual([...s.map].filter(([k])=>k.startsWith('quota:cycles:v1:event:')),before);
 assert.equal((await(await s.call('/api/devices')).json()).devices[0].periods.today.totalTokens,123);
});
