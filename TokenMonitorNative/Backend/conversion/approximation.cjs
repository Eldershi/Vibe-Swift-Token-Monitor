'use strict';
const {summaryEstimate}=require('./summary-estimate.cjs');
const {currentWindow,priceFor,weight,bindingFor,finite}=require('./core.cjs');
// An explicit, separate approximation: never upgrades coverage or rewrites raw events.
function approximate({observation,window,events=[],versions=[],bindings=[],deviceIds=[],aggregateDevices=[],now=new Date().toISOString()}) {
 const range=currentWindow(observation,window,now);
 const result={range,remainingTokens:null,totalWeight:0,tokens:0,excludedTokens:0,assumedTierTokens:0,assumedAccountTokens:0,devices:[],models:[],missingDevices:[],priceVersionIds:[],reasons:[],basis:'currentPricesRecordedMix'};
 if(range.reason){result.reasons=[range.reason];return result;}
 if(!observation.accountId||!deviceIds.length){result.reasons=['accountScopeUnconfirmed'];return result;}
 const latest=new Map();for(const e of events){const key=e.deviceId+':'+(e.eventKey||e.id),old=latest.get(key);if(!old||(old.revision||1)<=(e.revision||1))latest.set(key,e);}
 const rows=new Map(),models=new Map(),projections=new Map();
 for(const id of deviceIds){
  const hasEvents=[...latest.values()].some(e=>e.deviceId===id&&e.occurredAt>=range.start&&e.occurredAt<=range.observedAt&&(!bindingFor(e,bindings)||bindingFor(e,bindings)===observation.accountId));
  if(hasEvents)continue;
  const device=aggregateDevices.find(d=>d.deviceId===id),projection=device&&summaryEstimate(device,range);
  if(projection){projections.set(id,projection);for(const e of projection.events)latest.set(e.id,e);}
 }
 for(const e of latest.values()){
  if(!deviceIds.includes(e.deviceId)||e.occurredAt<range.start||e.occurredAt>range.observedAt)continue;
  const bound=bindingFor(e,bindings);if(bound&&bound!==observation.accountId)continue;
  const tokens=e.input+e.output;if(!finite(tokens))continue;
  const row=rows.get(e.deviceId)||{id:e.deviceId,tokens:0,weight:0,quota:null,basis:projections.has(e.deviceId)?'dailyRateProjection':'events',...(projections.has(e.deviceId)?{sampleFrom:projections.get(e.deviceId).sampleFrom,sampleTo:projections.get(e.deviceId).sampleTo,sourceUpdatedAt:projections.get(e.deviceId).sourceUpdatedAt}:{})};rows.set(e.deviceId,row);
  const normalized={...e,serviceTier:e.serviceTier==='unknown'?'standard':e.serviceTier};
  const priced=priceFor(normalized,versions,true),amount=weight(normalized,priced);
  if(amount==null){result.excludedTokens+=tokens;continue;}
  if(e.serviceTier==='unknown')result.assumedTierTokens+=tokens;
  if(!bound)result.assumedAccountTokens+=tokens;
  result.tokens+=tokens;result.totalWeight+=amount;row.tokens+=tokens;row.weight+=amount;result.priceVersionIds.push(priced.version.id);
  const model=models.get(e.model)||{id:e.model,tokens:0,weight:0,quota:null};model.tokens+=tokens;model.weight+=amount;models.set(e.model,model);
 }
 result.devices=[...rows.values()];result.models=[...models.values()];result.missingDevices=deviceIds.filter(id=>!rows.has(id));result.priceVersionIds=[...new Set(result.priceVersionIds)];
 if(!finite(result.totalWeight)||!finite(result.tokens)||!result.totalWeight){result.reasons=['noPricedUsage'];return result;}
 result.attributionAvailable=true;
 for(const row of [...result.devices,...result.models]){row.share=row.weight/result.totalWeight;row.quota=range.used*row.share;}
 return result;
}
module.exports={approximate};
