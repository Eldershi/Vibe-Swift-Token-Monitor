'use strict';
const {aggregateDevice}=require('./summary-estimate.cjs');
const {approximate}=require('./approximation.cjs');
const path=require('node:path');const os=require('node:os');
const {Ledger}=require('./store.cjs');const {Collector}=require('./collector.cjs');const {calculate,currentWindow,accountId,hash,iso}=require('./core.cjs');const {refreshPricing}=require('./pricing.cjs');
function hourlyTrend(events,now=new Date()){
 const y=now.getFullYear(),m=now.getMonth(),d=now.getDate(),currentStart=new Date(y,m,d,now.getHours()),rangeStart=new Date(currentStart.getTime()-23*3600000),rangeEnd=new Date(currentStart.getTime()+3600000),values=Array(24).fill(null),latest=new Map();
 for(const event of events){const key=event.deviceId+':'+(event.eventKey||event.id),old=latest.get(key);if(!old||(old.revision||1)<=(event.revision||1))latest.set(key,event);}
 for(const event of latest.values()){
  const at=new Date(event.occurredAt);if(!Number.isFinite(at.getTime())||at>new Date(now.getTime()+60000)||at<rangeStart||at>=rangeEnd)continue;
  const tokens=Number(event.input)+Number(event.output);if(!Number.isFinite(tokens)||tokens<0)continue;
  const index=Math.floor((at-rangeStart)/3600000);if(index<0||index>=24)continue;values[index]=(values[index]??0)+tokens;
 }
 const date=[y,String(m+1).padStart(2,'0'),String(d).padStart(2,'0')].join('-');
 let timeZone='';try{timeZone=Intl.DateTimeFormat().resolvedOptions().timeZone||'';}catch{}
 return {version:2,mode:'rolling24',date,timeZone,rangeStart:rangeStart.toISOString(),rangeEnd:rangeEnd.toISOString(),points:values.map((tokens,index)=>{const start=new Date(rangeStart.getTime()+index*3600000);return{hour:start.getHours(),start:start.toISOString(),tokens};})};
}
class ConversionService {
 constructor({directory,deviceId,roots,request,localReports,remoteEnabled=()=>true,source=()=>"local",enabled=()=>true,fixture=false}){
  this.ledger=new Ledger(path.join(directory,hash(source())));this.deviceId=deviceId;this.request=request?async(...args)=>{if(source()!==this.sourceID)throw Error('sourceChangedRestartRequired');return request(...args);}:null;this.localReports=localReports;this.enabled=enabled;this.fixture=fixture;this.remoteEnabled=remoteEnabled;this.source=source;this.sourceID=source();
  this.collector=new Collector({ledger:this.ledger,deviceId,roots:roots||[path.join(os.homedir(),'.codex/sessions'),path.join(os.homedir(),'.codex/archived_sessions')]});
  const retry=this.ledger.get("syncRetry",{});this.retryAt=retry.retryAt||0;this.failures=retry.failures||0;this.busy=false;this.error=retry.error||null;this.stopped=false;this.timer=null;
 }
 start(){if(this.fixture)return;void this.tick();this.timer=setInterval(()=>void this.tick(),60000);this.timer.unref();}
 async syncKind(endpoint,kind,arrayKey='records'){
  const key='cursor:'+endpoint,checkpoint=this.ledger.get(key,{});let upper=checkpoint.scanUpper||null,cursor=checkpoint.cursor||null;
  for(let page=0;page<1000;page++){
   const params=new URLSearchParams({limit:'200'});if(upper)params.set('to',upper);if(cursor)params.set('cursor',cursor);else if(checkpoint.through)params.set('from',checkpoint.through);
   const result=await this.request(endpoint+'?'+params);if(result.schemaVersion!==1||!Array.isArray(result[arrayKey]))throw Error('historyProtocolInvalid');
   const rows=result[arrayKey];upper=upper||iso(result.snapshotThrough)||rows.map(r=>iso(r.receivedAt)).filter(Boolean).sort().at(-1)||checkpoint.through||null;
   if(result.nextCursor===cursor&&cursor)throw Error('cursorNotAdvancing');
   this.ledger.page(kind,rows,key,result.nextCursor?{through:checkpoint.through,scanUpper:upper,cursor:result.nextCursor}:{through:upper});
   if(!result.nextCursor)return;cursor=result.nextCursor;
  }throw Error('historyPageLimit');
 }
 async tick(){if(this.busy||this.stopped||!this.enabled())return;this.busy=true;try{
  if(this.source()!==this.sourceID)throw Error('sourceChangedRestartRequired');
  await this.collector.scan();
  const pricing=this.ledger.get('pricingStatus',{});const config=this.ledger.get('config',{automaticPrices:true});
  if(!pricing.checkedAt||(config.automaticPrices!==false&&Date.now()-Date.parse(pricing.checkedAt)>=21600000))await refreshPricing(this.ledger);
  const reports=this.localReports?.()||[];
  for(const p of reports){if(p.provider!=='codex')continue;const observation={provider:p.provider,status:p.status,sourceDeviceId:this.deviceId,accountId:accountId(p.accountKey),planLabel:p.planLabel||'',sourceObservedAt:iso(p.updatedAt),receivedAt:new Date().toISOString(),sourceTimeKnown:!!iso(p.updatedAt),windows:p.windows||[]};observation.id=hash({...observation,receivedAt:undefined});this.ledger.put('observations',observation);}
  if(this.request&&this.remoteEnabled()){
   if(Date.now()<this.retryAt)return;
   const health=await this.request('api/health');
   const registry=await this.request('api/devices');
   if(!Array.isArray(registry.devices)||registry.devices.some(d=>typeof d.deviceId!=='string'||!d.deviceId))throw Error('historyProtocolInvalid');
   this.ledger.set('deviceRegistry',[...new Set(registry.devices.map(d=>d.deviceId))]);
   this.ledger.set('aggregateDevices',registry.devices.map(aggregateDevice));
   if(health.usageEventsVersion===1){
    for(const kind of ['events','coverage']){
     for(let n=0;n<100;n++){const rows=this.ledger.pending(kind);if(!rows.length)break;const response=await this.request('api/usage/'+kind,{schemaVersion:1,records:rows});if(!Array.isArray(response.accepted)||rows.some(r=>!response.accepted.includes(r.id)))throw Error('uploadNotAcknowledged');this.ledger.ack(kind,rows);}
     await this.syncKind('api/usage/'+kind,kind);
    }
   }else this.error='hubUpgradeRequired';
   if(health.quotaHistoryVersion===1)await this.syncKind('api/quota/history','observations','observations');
  }
  this.failures=0;this.retryAt=0;if(this.error!=='hubUpgradeRequired')this.error=null;
 }catch(e){this.failures++;this.retryAt=Date.now()+Math.min(3600000,60000*2**Math.min(this.failures-1,6));this.error=['historyProtocolInvalid','cursorNotAdvancing','historyPageLimit','uploadNotAcknowledged','sourceChangedRestartRequired'].includes(e.message)?e.message:'conversionSyncFailed';}finally{this.busy=false;this.ledger.set("syncRetry",{retryAt:this.retryAt,failures:this.failures,error:this.error});this.rebuildStatus();}}
 rebuildStatus(){
  const observations=this.ledger.rows('observations').filter(o=>o.provider==='codex').sort((a,b)=>(b.sourceObservedAt||'').localeCompare(a.sourceObservedAt||''));
  const choices=[];const seen=new Set();
  for(const o of observations){for(let i=0;i<o.windows.length;i++){const w=o.windows[i];const key=[o.accountId||o.sourceDeviceId,w.kind,w.limitId||''].join(':');if(seen.has(key))continue;seen.add(key);const seconds=w.windowSeconds??(w.windowMinutes==null?null:w.windowMinutes*60);const label=Number.isFinite(seconds)&&seconds>0?(seconds%86400===0?seconds/86400+'d':seconds%3600===0?seconds/3600+'h':seconds%60===0?seconds/60+'m':seconds+'s'):'—';choices.push({id:hash(key),title:label,kind:w.kind,label:w.limitId||w.label||null,limitId:w.limitId||null,additional:w.additional===true,windowMinutes:seconds/60,accountId:o.accountId||null,sourceDeviceId:o.sourceDeviceId||null,observationId:o.id,windowIndex:i});}}
  const config=this.ledger.get('config',{});const usable=c=>{const o=observations.find(o=>o.id===c.observationId);return currentWindow(o,o.windows[c.windowIndex]);};const choice=choices.find(c=>c.id===config.choiceId)||choices.find(c=>{const r=usable(c);return !r.reason&&r.used>=5&&r.remaining>0;})||choices.find(c=>!usable(c).reason)||choices[0];
  const selected=choice&&observations.find(o=>o.id===choice.observationId);const versions=this.ledger.rows('prices'),events=this.ledger.rows('events');
  const result=selected?calculate({observation:selected,window:selected.windows[choice.windowIndex],events,coverage:this.ledger.rows('coverage'),bindings:this.ledger.rows('bindings'),versions,scope:config.scope,previous:observations}):calculate({observation:{provider:'codex',status:'unknown'},window:{},events,versions});
  const deviceIds=this.request&&this.remoteEnabled()?this.ledger.get('deviceRegistry',[]):[this.deviceId];
  if(selected)result.approximation=approximate({observation:selected,window:selected.windows[choice.windowIndex],events:this.ledger.rows('events'),bindings:this.ledger.rows('bindings'),versions,deviceIds,aggregateDevices:this.ledger.get('aggregateDevices',[])});
  const latestCoverage=new Map();for(const c of this.ledger.rows('coverage'))if(!latestCoverage.has(c.deviceId)||latestCoverage.get(c.deviceId).to<=c.to)latestCoverage.set(c.deviceId,c);
  const currentAvailable=result.attributionAvailable===true||result.approximation?.attributionAvailable===true;
  const historyKey=choice?'lastSuccessful:'+choice.id:null;
  if(currentAvailable&&historyKey)this.ledger.set(historyKey,{capturedAt:new Date().toISOString(),choiceId:choice.id,result});
  const lastSuccessful=historyKey?this.ledger.get(historyKey):null;
  const response={schemaVersion:1,deviceIds,coverage:[...latestCoverage.values()],deviceId:this.deviceId,busy:this.busy,error:this.error,choices,choiceId:choice?.id||'',accountId:selected?.accountId||null,scan:this.ledger.get('scan'),pricing:this.ledger.get('pricingStatus'),prices:versions.at(-1)||null,config:{...config,target:null},result,displayMode:currentAvailable?'current':lastSuccessful?'historical':'recorded',lastSuccessful:currentAvailable?null:lastSuccessful,trend:{hourly:hourlyTrend(events)}};
  this.ledger.set('cachedStatus',response);return response;
 }
 status(){const cached=this.ledger.get('cachedStatus');return cached?.trend?.hourly?.version===2?{...cached,busy:this.busy,error:this.error}:this.rebuildStatus();
 }
 async command(body){
  if(body.action==='cached')return this.status();
  if(body.action==='refreshPrices'){await refreshPricing(this.ledger);return this.rebuildStatus();}
  if(body.action==='refresh'){await this.tick();return this.status();}
  if(body.action==='configure'){
   const old=this.ledger.get('config',{});const next={...old};
   if(typeof body.approximateEstimates==='boolean')next.approximateEstimates=body.approximateEstimates;
   if(typeof body.automaticPrices==='boolean')next.automaticPrices=body.automaticPrices;
   if(typeof body.choiceId==='string'&&body.choiceId.length<200)next.choiceId=body.choiceId;
   next.target=null; // Legacy prediction input is accepted but no longer used.
   this.ledger.set('config',next);return this.rebuildStatus();
  }
  if(body.action==='bind'){
   const status=this.status();const account=body.accountId;
   if(!/^[a-f0-9]{64}$/.test(account||'')||!iso(body.from)||!Array.isArray(body.deviceIds)||!body.deviceIds.length||body.deviceIds.length>100||body.deviceIds.some(s=>typeof s!=='string'||!s||s.length>128)||body.confirmed!==true)throw Error('invalid_binding');
   const from=iso(body.from),to=body.to?iso(body.to):null;if(body.to&&!to||to&&to<from)throw Error('invalid_binding');
   this.ledger.transaction(()=>{for(const deviceId of body.deviceIds){const b={schemaVersion:1,deviceId,accountId:account,from,to,evidence:'userConfirmed'};b.id=hash(b);this.ledger.put('bindings',b);}
    const config=this.ledger.get('config',{});config.scope={accountId:account,deviceIds:[...new Set(body.deviceIds)],from,to,confirmed:true};this.ledger.set('config',config);
    if(body.confirmLocalLogs===true&&body.deviceIds.includes(this.deviceId))this.ledger.set('coverageAttestation',{from,confirmed:true});
   });await this.collector.scan();return this.rebuildStatus();
  }
  throw Error('invalid_action');
 }
 async close(){this.stopped=true;if(this.timer)clearInterval(this.timer);while(this.busy)await new Promise(r=>setTimeout(r,20));this.ledger.close();}
}
module.exports={ConversionService,hourlyTrend};
