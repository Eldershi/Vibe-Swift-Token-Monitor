'use strict';
// App-owned, one-shot adapter for an older resident backend. No totals collector,
// background registration, credential mutation, or long-lived competing uploader.
const fs=require('node:fs');const path=require('node:path');const {DatabaseSync}=require('node:sqlite');
const {ConversionService,hourlyTrend}=require('./service.cjs');const {hash}=require('./core.cjs');const {HubCredentialStore}=require('../hub-credential.cjs');
function privateJSON(file){const fd=fs.openSync(file,fs.constants.O_RDONLY|fs.constants.O_NOFOLLOW);try{const s=fs.fstatSync(fd);if(!s.isFile()||s.uid!==process.getuid()||(s.mode&0o777)!==0o600||s.size>65536)throw Error('privateConfigurationRequired');return JSON.parse(fs.readFileSync(fd,'utf8'));}finally{fs.closeSync(fd);}}
async function run(directory,body,fetchImpl=fetch,Service=ConversionService){
 const endpoint=privateJSON(path.join(directory,'endpoint.json'));const local=new URL(endpoint.address);
 if(local.protocol!=='http:'||!['127.0.0.1','localhost','[::1]'].includes(local.hostname)||local.username||local.password)throw Error('invalidLocalEndpoint');
 const getLocal=async route=>{const r=await fetchImpl(new URL(route,local),{redirect:'error',signal:AbortSignal.timeout(10000),headers:{Authorization:'Bearer '+endpoint.secret}});if(!r.ok)throw Error('localBackendUnavailable');return r.json();};
 const status=await getLocal('/api/beta/status');if(status.pid!==endpoint.pid||status.session!==endpoint.session)throw Error('localBackendChanged');
 if(status.paused)throw Error('collectionPaused');
 let config={};try{config=privateJSON(path.join(directory,'hub-sync.json'));}catch(e){if(e.code!=='ENOENT')throw e;}
 const device=config.deviceId||privateJSON(path.join(directory,'backend-config.json')).deviceId;
 const reports=(await getLocal('/local/api/stats')).limits?.providers||[];
 if(body?.action==='rollingTrend'){
  const file=path.join(directory,'conversion',hash(config.address||'local'),'conversion.sqlite');
  const db=new DatabaseSync(file,{readOnly:true});try{const events=db.prepare("SELECT data FROM records WHERE kind='events' ORDER BY rowid").all().map(row=>JSON.parse(row.data));return{trend:{hourly:hourlyTrend(events)}};}finally{db.close();}
 }
 let request;
 if(config.enabled){const base=new URL(config.address);if(base.protocol!=='https:'&&!(base.protocol==='http:'&&['127.0.0.1','localhost','[::1]'].includes(base.hostname)))throw Error('invalidHub');if(base.username||base.password||base.search||base.hash)throw Error('invalidHub');const secret=new HubCredentialStore(directory).read(config.address);if(!secret)throw Error('credentialUnavailable');
  request=async(route,data)=>{const r=await fetchImpl(new URL(route,config.address.replace(/\/?$/,'/')),{method:data?'POST':'GET',redirect:'error',signal:AbortSignal.timeout(45000),headers:{Authorization:'Bearer '+secret,'Content-Type':'application/json'},...(data?{body:JSON.stringify(data)}:{})});if(!r.ok)throw Error('hubUnavailable');return r.json();};
 }
 const service=new Service({directory:path.join(directory,'conversion'),deviceId:device,request,remoteEnabled:()=>config.enabled===true,source:()=>config.address||'local',localReports:()=>reports});
 try{
  if(body?.action==='cached')return service.status();
  if(body?.action==='refresh')return service.command(body);
  await service.tick();return body?await service.command(body):service.status();
 }finally{await service.close();}
}
if(require.main===module){const deadline=setTimeout(()=>process.exit(1),120000);deadline.unref();let text='';process.stdin.setEncoding('utf8');process.stdin.on('data',chunk=>{text+=chunk;if(text.length>65536)process.exit(1);});process.stdin.on('end',async()=>{try{const result=await run(process.argv[2],text.trim()?JSON.parse(text):null);process.stdout.write(JSON.stringify(result));}catch(e){process.stdout.write(JSON.stringify({bridgeError:['collectionPaused','collectorAlreadyRunning','credentialUnavailable','localBackendChanged'].includes(e.message)?e.message:'conversionBridgeUnavailable'}));process.exitCode=1;}});}
module.exports={run};
