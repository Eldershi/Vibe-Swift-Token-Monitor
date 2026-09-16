#!/usr/bin/env node
'use strict';
const fs=require('node:fs');const path=require('node:path');const {ConversionService}=require('./service.cjs');
async function main(){
 const args=process.argv.slice(2);const value=k=>{const i=args.indexOf(k);return i<0?null:args[i+1];};
 if(args.includes('--help')||!value('--directory')||!value('--device-id')){console.log('node conversion/cli.cjs --directory <private-data-dir> --device-id <existing-device-id> [--logs <codex-dir>] [--hub <https-url> --secret-file <private-file>] [--once] [--command <private-json-file>]');return;}
 const directory=path.resolve(value('--directory')),deviceId=value('--device-id'),hub=value('--hub');let request;
 if(hub){const url=new URL(hub);if(!['https:','http:'].includes(url.protocol)||url.username||url.password||url.search||url.hash)throw Error('invalid_hub');if(url.protocol==='http:'&&!['127.0.0.1','localhost','[::1]'].includes(url.hostname))throw Error('https_required');
  const secretFile=path.resolve(value('--secret-file')||'');const stat=fs.lstatSync(secretFile);if(!stat.isFile()||stat.isSymbolicLink()||(process.platform!=='win32'&&(stat.mode&0o077)))throw Error('private_secret_file_required');
  const secret=fs.readFileSync(secretFile,'utf8').trim();if(!secret||/[\r\n]/.test(secret))throw Error('invalid_secret');
  request=async(endpoint,body)=>{const response=await fetch(new URL(endpoint,hub.replace(/\/?$/,'/')),{method:body?'POST':'GET',redirect:'error',signal:AbortSignal.timeout(45000),headers:{Authorization:'Bearer '+secret,'Content-Type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});if(!response.ok)throw Error('hub_request_failed');return response.json();};
 }
 const logs=value('--logs');const service=new ConversionService({directory,deviceId,request,source:()=>hub||'local',roots:logs?[path.join(path.resolve(logs),'sessions'),path.join(path.resolve(logs),'archived_sessions')]:undefined});
 let closing=false;const close=async()=>{if(closing)return;closing=true;await service.close();process.exit(0);};process.on('SIGINT',close);process.on('SIGTERM',close);
 if(value('--command')){const body=JSON.parse(fs.readFileSync(path.resolve(value('--command')),'utf8'));await service.command(body);}
 await service.tick();console.log(JSON.stringify(service.status()));
 if(args.includes('--once'))await service.close();else {service.start();setInterval(()=>{},3600000);}
}
if(require.main===module)main().catch(()=>{console.error('Conversion collector failed; check configuration, private file permissions and connectivity.');process.exitCode=1;});
module.exports={main};
