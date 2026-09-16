'use strict';
const {hash,finite}=require('./core.cjs');
const SOURCE='https://learn.chatgpt.com/docs/pricing.md';
const aliases={'GPT-6 Astra':'gpt-6-astra','GPT-5.6 Sol':'gpt-5.6-sol','GPT-5.6 Terra':'gpt-5.6-terra','GPT-5.6 Luna':'gpt-5.6-luna','GPT-5.5':'gpt-5.5','GPT-5.4':'gpt-5.4','GPT-5.4 mini':'gpt-5.4-mini','GPT-5.3-Codex':'gpt-5.3-codex','GPT-5.2-Codex':'gpt-5.2-codex'};
function parsePricing(text,{fetchedAt=new Date().toISOString(),sourceUrl=SOURCE}={}) {
 const section=text.match(/(?:####|###|##) Token rates([\s\S]*?)(?=\n#{1,4} |$)/i)?.[1];
 if(!section||!/credits per (?:million|1M)/i.test(section))throw Error('priceStructureChanged');
 const rates=[];
 const normalized=section.replace(/<tr[^>]*>([\s\S]*?)<\/tr>/gi,(_,row)=>'\n|'+[...row.matchAll(/<td[^>]*>([\s\S]*?)<\/td>/gi)].map(m=>m[1].replace(/<[^>]*>/g,'').trim()).join('|')+'|\n');
 for(const line of normalized.split('\n')){
  const cells=line.split('|').map(s=>s.replace(/\*|`/g,'').trim()).filter(Boolean);const model=aliases[cells[0]];
  if(!model||cells.length<4)continue;
  const values=cells.slice(1,4).map(s=>Number(s.replace(/credits|,/gi,'').trim()));
  if(!values.every(n=>finite(n)&&n>0&&n<1000000))throw Error('priceInvalid');
  rates.push({model,tier:'standard',input:values[0],cached:values[1],output:values[2]});
 }
 if(rates.length<3)throw Error('priceStructureChanged');
 // Only the explicitly documented model/multiplier is mapped; unknown Fast tiers stay unknown.
 if(/Fast mode applies a 2\.5x multiplier to Astra/i.test(section)){
  const row=rates.find(r=>r.model==='gpt-6-astra');if(row)rates.push({...row,tier:'fast',input:row.input*2.5,cached:row.cached*2.5,output:row.output*2.5});
 }
 const contentHash=hash(rates);return {schemaVersion:1,id:hash([contentHash,fetchedAt]),contentHash,sourceUrl,fetchedAt,publishedAt:null,effectiveFrom:null,unit:'credits',rates};
}
async function refreshPricing(ledger,fetchImpl=fetch){
 const checkedAt=new Date().toISOString();const old=ledger.get('pricingStatus',{});
 try{
  const response=await fetchImpl(SOURCE,{redirect:'error',signal:AbortSignal.timeout(20000),headers:{Accept:'text/markdown,text/plain'}});
  if(!response.ok)throw Error('priceUnavailable');const text=await response.text();if(text.length>3000000)throw Error('priceTooLarge');
  const next=parsePricing(text,{fetchedAt:checkedAt});const versions=ledger.rows('prices'),current=versions.at(-1);
  if(current&&current.contentHash!==next.contentHash){
   for(const row of current.rates){const replacement=next.rates.find(r=>r.model===row.model&&r.tier===row.tier);if(!replacement)throw Error('priceModelsMissing');for(const k of ['input','cached','output'])if(replacement[k]/row[k]>10||replacement[k]/row[k]<0.1)throw Error('priceChangeReviewRequired');}
   next.previousCheckedAt=old.successAt||current.fetchedAt;
  }
  if(!current||current.contentHash!==next.contentHash)ledger.put('prices',next);
  else next.id=current.id;
  const status={checkedAt,successAt:checkedAt,error:null,currentId:next.id};ledger.set('pricingStatus',status);return status;
 }catch(e){const status={...old,checkedAt,error:['priceStructureChanged','priceInvalid','priceTooLarge','priceModelsMissing','priceChangeReviewRequired'].includes(e.message)?e.message:'priceUnavailable'};ledger.set('pricingStatus',status);return status;}
}
module.exports={SOURCE,parsePricing,refreshPricing};
