'use strict';
const {DatabaseSync}=require('node:sqlite');
const fs=require('node:fs');const path=require('node:path');const {hash}=require('./core.cjs');
class Ledger {
 constructor(directory){fs.mkdirSync(directory,{recursive:true,mode:0o700});this.lock=path.join(directory,'collector.lock');
 const acquire=()=>{const fd=fs.openSync(this.lock,'wx',0o600);try{fs.writeFileSync(fd,JSON.stringify({pid:process.pid}));}finally{fs.closeSync(fd);}};
 try{acquire();}catch(e){if(e.code!=='EEXIST')throw e;let owner;try{owner=JSON.parse(fs.readFileSync(this.lock,'utf8'));}catch{throw Error('collectorLockInvalid');}if(!Number.isInteger(owner.pid)||owner.pid<1)throw Error('collectorLockInvalid');try{process.kill(owner.pid,0);throw Error('collectorAlreadyRunning');}catch(error){if(error.code!=='ESRCH')throw error;}fs.unlinkSync(this.lock);acquire();}
 const file=path.join(directory,'conversion.sqlite');this.db=new DatabaseSync(file);fs.chmodSync(file,0o600);this.db.exec('PRAGMA journal_mode=WAL; PRAGMA busy_timeout=5000; CREATE TABLE IF NOT EXISTS records(kind TEXT NOT NULL,id TEXT NOT NULL,data TEXT NOT NULL,pending INTEGER NOT NULL DEFAULT 0,PRIMARY KEY(kind,id)); CREATE TABLE IF NOT EXISTS metadata(id TEXT PRIMARY KEY,data TEXT NOT NULL)');}
 transaction(fn){this.db.exec('BEGIN IMMEDIATE');try{const r=fn();this.db.exec('COMMIT');return r;}catch(e){this.db.exec('ROLLBACK');throw e;}}
 put(kind,row,pending=false){const id=row.id||hash(row);this.db.prepare('INSERT INTO records VALUES(?,?,?,?) ON CONFLICT(kind,id) DO UPDATE SET data=excluded.data,pending=max(records.pending,excluded.pending)').run(kind,id,JSON.stringify({...row,id}),pending?1:0);return id;}
 rows(kind){return this.db.prepare('SELECT data FROM records WHERE kind=? ORDER BY rowid').all(kind).map(r=>JSON.parse(r.data));}
 pending(kind,limit=200){return this.db.prepare('SELECT data FROM records WHERE kind=? AND pending=1 ORDER BY rowid LIMIT ?').all(kind,limit).map(r=>JSON.parse(r.data));}
 ack(kind,rows){this.transaction(()=>{for(const r of rows)this.db.prepare('UPDATE records SET pending=0 WHERE kind=? AND id=?').run(kind,r.id);});}
 get(key,fallback=null){const r=this.db.prepare('SELECT data FROM metadata WHERE id=?').get(key);return r?JSON.parse(r.data):fallback;}
 set(key,value){this.db.prepare('INSERT INTO metadata VALUES(?,?) ON CONFLICT(id) DO UPDATE SET data=excluded.data').run(key,JSON.stringify(value));}
 page(kind,rows,key,checkpoint){this.transaction(()=>{for(const r of rows)this.put(kind,r);this.set(key,checkpoint);});}
 close(){this.db.close();try{if(JSON.parse(fs.readFileSync(this.lock,'utf8')).pid===process.pid)fs.unlinkSync(this.lock);}catch{}}
}
module.exports={Ledger};
