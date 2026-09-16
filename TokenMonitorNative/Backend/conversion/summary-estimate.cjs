'use strict';
const {finite}=require('./core.cjs');
// Whitelisted aggregate metadata only. Never retain account labels, credentials or content.
function aggregateDevice(d){
 const count=r=>Object.fromEntries(['tokens','cacheReadTokens','outputTokens','unclassifiedTokens'].filter(k=>finite(r?.[k])).map(k=>[k,r[k]]));
 return {deviceId:d.deviceId,updatedAt:d.updatedAt,timeZone:d.periodWindows?.timeZone,daily:(d.history?.daily||[]).map(r=>({date:r.date,codex:count(r.perClient?.codex),models:Object.fromEntries(Object.entries(r.perModel||{}).map(([k,v])=>[k,count(v)]))}))};
}
function dateInZone(stamp,zone){try{const parts=new Intl.DateTimeFormat('en-CA',{timeZone:zone,year:'numeric',month:'2-digit',day:'2-digit'}).formatToParts(new Date(stamp));return ['year','month','day'].map(k=>parts.find(p=>p.type===k).value).join('-');}catch{return null;}}
// Fit a rate from up to seven recorded complete days; forecast the current interval.
// A day crossing the reset is never split or entered into the event ledger.
function summaryEstimate(device,range){
 const cutoff=[dateInZone(range.observedAt,device.timeZone),dateInZone(device.updatedAt,device.timeZone)].filter(Boolean).sort()[0];
 if(!cutoff)return null;
 const all=device.daily.filter(r=>/^\d{4}-\d{2}-\d{2}$/.test(r.date)&&r.date<cutoff&&finite(r.codex?.tokens)&&r.codex.tokens>0).sort((a,b)=>a.date.localeCompare(b.date));
 const currentDate=dateInZone(range.start,device.timeZone);
 const current=all.filter(r=>r.date>currentDate),sample=(current.length?current:all).slice(-7);if(!sample.length)return null;
 const duration=(Date.parse(range.observedAt)-Date.parse(range.start))/86400000;
 const first=sample[0].date,last=sample.at(-1).date;
 // Recorded-day rate is explicit: absent days are not silently counted as zero.
 const factor=duration/sample.length,events=[];
 for(const day of sample){
  const models=Object.entries(day.models).filter(([m,r])=>finite(r.tokens)&&r.tokens>0);
  // Mixed-provider model totals cannot be attributed to Codex without a mapping.
  if(Math.abs(models.reduce((n,[,r])=>n+r.tokens,0)-day.codex.tokens)>1)continue;
  for(const [model,r] of models){if(!finite(r.outputTokens)||!finite(r.cacheReadTokens)||r.outputTokens+r.cacheReadTokens>r.tokens)continue;
   events.push({id:`summary:${device.deviceId}:${day.date}:${model}`,deviceId:device.deviceId,occurredAt:range.observedAt,model,serviceTier:'unknown',accountId:null,input:(r.tokens-r.outputTokens)*factor,cached:r.cacheReadTokens*factor,output:r.outputTokens*factor});
  }
 }
 return events.length?{events,basis:'dailyRateProjection',sampleFrom:first,sampleTo:last,sampleDays:sample.length,sourceUpdatedAt:device.updatedAt}:null;
}
module.exports={aggregateDevice,summaryEstimate};
