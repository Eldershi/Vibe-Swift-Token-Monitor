'use strict';
const test=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const {run}=require('../conversion/bridge.cjs'),{ConversionService}=require('../conversion/service.cjs');
function setup(t){const dir=fs.mkdtempSync(path.join(os.tmpdir(),'bridge-test-'));t.after(()=>fs.rmSync(dir,{recursive:true,force:true}));const put=(file,data)=>fs.writeFileSync(path.join(dir,file),JSON.stringify(data),{mode:0o600});put('endpoint.json',{address:'http://127.0.0.1:12345',secret:'synthetic-local',pid:42,session:'synthetic'});put('backend-config.json',{deviceId:'local-device'});return{dir,put};}
test('old resident backend can supply data to the bundled converter without replacement or a second totals uploader',async t=>{
 const {dir,put}=setup(t),now=new Date().toISOString(),logs=path.join(dir,'logs');fs.mkdirSync(logs);put('hub-sync.json',{address:'https://synthetic.invalid',enabled:true,deviceId:'existing-device'});put('hub-credential.json',{address:'https://synthetic.invalid',secret:'synthetic-hub'});
 fs.writeFileSync(path.join(logs,'usage.jsonl'),[{timestamp:now,type:'session_meta',payload:{id:'synthetic-session'}},{timestamp:now,type:'turn_context',payload:{model:'gpt-6-astra',service_tier:'standard'}},{timestamp:now,type:'event_msg',payload:{type:'token_count',info:{total_token_usage:{input_tokens:100,cached_input_tokens:20,output_tokens:50}}}}].map(JSON.stringify).join('\n'));
 const requests=[],saved={events:[],coverage:[]};
 const fake=async(url,options)=>{const u=new URL(url);requests.push(u.pathname);let body;
  if(u.pathname==='/api/beta/status')body={pid:42,session:'synthetic',paused:false};
  else if(u.pathname==='/local/api/stats')body={limits:{providers:[]}};
  else if(u.pathname==='/api/devices')body={devices:[{deviceId:'existing-device'}]};
  else if(u.pathname==='/api/health')body={usageEventsVersion:1};
  else if(u.pathname.startsWith('/api/usage/')){const kind=u.pathname.split('/').at(-1);if(options.method==='POST'){saved[kind]=JSON.parse(options.body).records;body={accepted:saved[kind].map(r=>r.id)};}else body={schemaVersion:1,records:saved[kind],snapshotThrough:now,nextCursor:null};}
  else throw Error('unexpected request');return{ok:true,json:async()=>body};
 };
 class Service{constructor(options){const s=new ConversionService({...options,roots:[logs],fixture:true});s.ledger.set('pricingStatus',{checkedAt:now});return s;}}
 const r=await run(dir,null,fake,Service);assert.equal(r.deviceId,'existing-device');assert.equal(r.result.devices[0].tokens,150);assert.equal(saved.events.length,1);assert.equal(saved.events[0].deviceId,'existing-device');assert(!requests.includes('/api/ingest'));assert.equal(r.error,null);
 assert(!JSON.stringify(saved).includes('synthetic-hub'));assert(!JSON.stringify(saved).includes(logs));
 requests.length=0;const cached=await run(dir,{action:'cached'},fake,Service);assert.equal(cached.result.devices[0].tokens,150);assert(!requests.includes('/api/health'));assert(!requests.some(p=>p.startsWith('/api/usage/')));
});
test('paused or changed resident service is not bypassed',async t=>{const {dir}=setup(t);for(const data of [{pid:42,session:'synthetic',paused:true},{pid:43,session:'synthetic'}])await assert.rejects(run(dir,null,async()=>({ok:true,json:async()=>data})),/collectionPaused|localBackendChanged/);});

test('rolling trend reads committed events while the resident converter owns the writer lock',async t=>{
 const {dir}=setup(t),service=new ConversionService({directory:path.join(dir,'conversion'),deviceId:'local-device',fixture:true});t.after(()=>service.close());
 service.ledger.put('events',{id:'event',eventKey:'event',revision:1,deviceId:'local-device',occurredAt:new Date().toISOString(),input:80,cached:20,output:20});
 const fake=async url=>{const pathname=new URL(url).pathname;return{ok:true,json:async()=>pathname==='/api/beta/status'?{pid:42,session:'synthetic',paused:false}:{limits:{providers:[]}}};};
 const result=await run(dir,{action:'rollingTrend'},fake);assert.equal(result.trend.hourly.version,2);assert.equal(result.trend.hourly.points.length,24);assert.equal(result.trend.hourly.points.reduce((n,p)=>n+(p.tokens||0),0),100);
});
