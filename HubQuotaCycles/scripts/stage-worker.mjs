// Copy only source and synthetic tests. Never copy deployment secrets/configuration.
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { createHash } from 'node:crypto';
const [source, destination] = process.argv.slice(2);
if (!source || !destination) throw new Error('Usage: node scripts/stage-worker.mjs source-project new-experiment-directory');
try { await fs.access(destination); throw new Error('destination_must_not_exist'); }
catch (error) { if(error.code !== 'ENOENT') throw error; }
const here=path.dirname(fileURLToPath(import.meta.url));
await fs.mkdir(destination,{recursive:true,mode:0o700});
await fs.cp(path.join(source,'worker/src'),path.join(destination,'worker/src'),{recursive:true});
await fs.cp(path.join(source,'tests/worker'),path.join(destination,'tests/worker'),{recursive:true});
await fs.writeFile(path.join(destination,'package.json'),JSON.stringify({private:true,type:'commonjs'}));
await fs.writeFile(path.join(destination,'worker/package.json'),JSON.stringify({private:true,type:'module'}));
const anchors=[];
async function amend(relative, replacements){
 const file=path.join(destination,relative);let text=await fs.readFile(file,'utf8');
 anchors.push({path:relative,sha256:createHash('sha256').update(text).digest('hex')});
 for(const [before,after]of replacements){
  if(text.split(before).length!==2)throw new Error('integration_anchor_mismatch:'+relative);
  text=text.replace(before,after);
 }
 await fs.writeFile(file,text);
}
await amend('worker/src/quotaHistory.js',[
 ["const PREFIX = 'quota:v1:observation:';","import { appendCycleObservation } from './quotaCycles.js';\nconst PREFIX = 'quota:v1:observation:';"],
 ['export async function appendObservations(tx, rows) {','export async function appendObservations(tx, rows, { cycleRecords = false } = {}) {'],
 ['await tx.put(key,row);await tx.put(dedup,key);','await tx.put(key,row);await tx.put(dedup,key);\n  if(cycleRecords)await appendCycleObservation(tx,row);'],
]);
await amend('worker/src/index.js',[
 ['    this.encoder = new TextEncoder();', `    this.encoder = new TextEncoder();
    this.cyclesReady = false;
    this.cycleSerial = Promise.resolve();`],
 ['  async fetch(request) {\n    const url = new URL(request.url);', `  // Serialize migration with requests, including requests already awaiting I/O.
  // A process restart always catches up the durable cursor before advertising capability.
  exclusive(operation) {
    const next = this.cycleSerial.then(operation);
    this.cycleSerial = next.catch(() => {});
    return next;
  }

  async catchUpCycles() {
    if (this.env.QUOTA_CYCLES_ENABLED !== 'true' || this.cyclesReady) return;
    const progress = await backfillCycleHistory(this.state.storage,
      { through: new Date().toISOString(), limit: 100 });
    this.cyclesReady = progress.complete;
    if (!progress.complete && this.state.storage.setAlarm) {
      await this.state.storage.setAlarm(Date.now() + 1000);
    }
  }

  async alarm() {
    return this.exclusive(() => this.catchUpCycles());
  }

  async fetch(request) {
    return this.exclusive(async () => {
      await this.catchUpCycles();
      return this.handleRequest(request);
    });
  }

  async handleRequest(request) {
    const url = new URL(request.url);`],

 ["import { observations, appendObservations, readHistory } from './quotaHistory.js';","import { observations, appendObservations, readHistory } from './quotaHistory.js';\nimport { readCycleHistory, backfillCycleHistory } from './quotaCycles.js';"],
 ['quotaHistoryVersion: 1,',"quotaHistoryVersion: 1,\n        quotaCycleVersion: this.cyclesReady ? 1 : 0,"],
 ["    if (request.method === 'GET' && url.pathname === '/api/quota/history') {", "    if (request.method === 'GET' && url.pathname === '/api/quota/cycles') {\n      if(!this.cyclesReady)return jsonResponse(404,{error:'capability_disabled'});\n      const result = await readCycleHistory(this.state.storage, url);\n      return jsonResponse(result.error ? 400 : 200, result);\n    }\n    if (request.method === 'GET' && url.pathname === '/api/quota/history') {"],
 ['await appendObservations(tx, rows);',"await appendObservations(tx, rows, { cycleRecords: this.cyclesReady });"],
]);
for(const file of['quotaCycles.js','quotaCycleReducer.js'])await fs.copyFile(path.join(here,'../src',file),path.join(destination,'worker/src',file));
await fs.copyFile(path.join(here,'../tests/workerIntegration.cjs'),path.join(destination,'tests/worker/quotaCycles.test.js'));
await fs.writeFile(path.join(destination,'integration-base.json'),JSON.stringify(anchors,null,2));
console.log('Created isolated Worker source/tests with guarded integration anchors. No deployment files copied.');
