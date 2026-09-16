'use strict';
const fs=require('node:fs/promises');const path=require('node:path');const {hash,iso,finite}=require('./core.cjs');
async function filesUnder(root){const files=[];async function walk(dir){for(const entry of await fs.readdir(dir,{withFileTypes:true})){const file=path.join(dir,entry.name);if(entry.isSymbolicLink())continue;if(entry.isDirectory())await walk(file);else if(entry.isFile()&&file.endsWith('.jsonl'))files.push(file);}}await walk(root);return files.sort();}
function parseLog(text,deviceId){
 const lines=text.split('\n');const events=[];let session=null,model=null,tier=null,previous=null,epoch=0,index=0,forked=false,errors=0,earliest=null;
 for(let lineIndex=0;lineIndex<lines.length;lineIndex++){
  const line=lines[lineIndex];if(!line.trim())continue;let row;try{row=JSON.parse(line);}catch{errors++;continue;}
  const p=row.payload||{},timestamp=iso(row.timestamp);
  if(row.type==='session_meta'){session=typeof p.id==='string'?p.id:null;forked=!!(p.forked_from_id||p.forkedFromId||p.parent_thread_id||p.parent_session_id);}
  if(timestamp&&(!earliest||timestamp<earliest))earliest=timestamp;
  if(row.type==='turn_context'){
   model=typeof p.model==='string'?p.model:null;
   tier=p.service_tier==='priority'||p.service_tier==='fast'?'fast':p.service_tier==='default'||p.service_tier==='standard'?'standard':null;
  }
  if(row.type!=='event_msg'||p.type!=='token_count')continue;
  const total=p.info?.total_token_usage,last=p.info?.last_token_usage;
  if(!total)continue;
  const current={input:total.input_tokens,cached:total.cached_input_tokens,output:total.output_tokens};
  if(!Object.values(current).every(n=>Number.isSafeInteger(n)&&n>=0)||current.cached>current.input||!session||!model||!/^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$/.test(model)||!timestamp){errors++;continue;}
  const cumulativeHash=hash(current);
  if(previous&&Object.keys(current).every(k=>current[k]===previous[k]))continue;
  let delta;
  if(previous&&Object.keys(current).some(k=>current[k]<previous[k])){epoch++;delta=null;errors++;}
  else if(previous)delta=Object.fromEntries(Object.keys(current).map(k=>[k,current[k]-previous[k]]));
  else if(forked){
   delta=null;
   errors++; // Inheritance boundary is not reliable enough to attest complete coverage.
  }else delta=current;
  previous=current;
  if(!delta||!Object.values(delta).every(finite)||delta.cached>delta.input){errors++;continue;}
  const eventKey=hash([session,epoch,timestamp,cumulativeHash]);
  const event={schemaVersion:1,eventKey,revision:1,deviceId,provider:'codex',occurredAt:timestamp,model,serviceTier:tier||'unknown',...delta,accountId:null,accountEvidence:'unknown'};
  event.id=hash(event);events.push(event);index++;
 }
 return {events,errors,earliest};
}
class Collector{
 constructor({ledger,deviceId,roots}){this.ledger=ledger;this.deviceId=deviceId;this.roots=roots;this.busy=false;}
 async scan(){if(this.busy)return;this.busy=true;try{
  const latest=new Map();for(const e of this.ledger.rows('events'))if(e.deviceId===this.deviceId&&(!latest.has(e.eventKey)||latest.get(e.eventKey).revision<e.revision))latest.set(e.eventKey,e);
  const now=new Date().toISOString();let errors=0,earliest=null,known=0;const seen=[],presentEvents=new Set();
  for(const root of this.roots){let files;try{files=await filesUnder(root);}catch(e){if(e.code!=='ENOENT')errors++;else if(root===this.roots[0])errors++;continue;}
   for(const file of files){
    try{
     const stat=await fs.stat(file);const key='file:'+hash(file),cached=this.ledger.get(key);
     const marker=[stat.size,stat.mtimeMs,stat.ino].join(':');
     if(cached?.marker===marker){errors+=cached.errors;known+=cached.count;for(const id of cached.eventIds||[])presentEvents.add(id);if(cached.earliest&&(!earliest||cached.earliest<earliest))earliest=cached.earliest;seen.push(key);continue;}
     if(stat.size>128*1024*1024){errors++;continue;}
     const result=parseLog(await fs.readFile(file,'utf8'),this.deviceId);for(const e of result.events)presentEvents.add(e.id);if(cached?.size>stat.size)result.errors++;errors+=result.errors;known+=result.events.length;
     if(result.earliest&&(!earliest||result.earliest<earliest))earliest=result.earliest;
     this.ledger.transaction(()=>{for(const event of result.events){
       const matches=(latest.get(event.eventKey)?[latest.get(event.eventKey)]:[]);const old=matches[0];
       const canonical=e=>hash({...e,id:undefined,revision:undefined,receivedAt:undefined});
       if(old&&canonical(old)===canonical(event))continue;
       if(old){event.revision=old.revision+1;event.id=hash({...event,id:undefined});}
       this.ledger.put('events',event,true);latest.set(event.eventKey,event);
      }this.ledger.set(key,{marker,size:stat.size,eventIds:result.events.map(e=>e.id),errors:result.errors,count:result.events.length,earliest:result.earliest});});seen.push(key);
    }catch{errors++;}
   }
  }
  const previous=this.ledger.get('scan',{});const removed=(previous.files||[]).filter(k=>!seen.includes(k));
  // Files may rotate to archived_sessions; event IDs keep them idempotent, but absent files are not proof of zero usage.
  const missing=[...new Set([...(previous.missing||[]),...removed])].filter(k=>!seen.includes(k)&&!(this.ledger.get(k)?.eventIds?.length&&this.ledger.get(k).eventIds.every(id=>presentEvents.has(id))));
  if(missing.length)errors+=missing.length;
  const status={at:now,earliest,errors,events:known,files:seen,missing};this.ledger.set('scan',status);
  const proof=this.ledger.get('coverageAttestation');
  const from=proof?.from||previous.coverageFrom||now;
  this.ledger.set('scan',{...status,coverageFrom:errors?now:from});
  const coverage={schemaVersion:1,deviceId:this.deviceId,from,to:now,complete:errors===0&&proof?.confirmed===true,gaps:errors?[{from:previous.at||from,to:now}]:[],basis:proof?.confirmed?'userConfirmedLogs':'unconfirmed'};
  coverage.id=hash(coverage);this.ledger.put('coverage',coverage,true);return status;
 }finally{this.busy=false;}}
}
module.exports={parseLog,Collector,filesUnder};
