const { test }=require('node:test');
const assert=require('node:assert/strict');
const http=require('node:http');
const {hubFetch}=require('../hub-http.cjs');
test('dedicated Hub transport carries authenticated JSON and rejects redirect following',async()=>{
 let redirects=0;
 const server=http.createServer((req,res)=>{
  if(req.url==='/redirect'){res.writeHead(302,{Location:'/target'});res.end('{}');return}
  if(req.url==='/target')redirects++;
  let text='';req.on('data',c=>text+=c);req.on('end',()=>{res.setHeader('Content-Type','application/json');res.end(JSON.stringify({authenticated:req.headers.authorization==='Bearer test',data:text?JSON.parse(text):null}))});
 });
 await new Promise(r=>server.listen(0,'127.0.0.1',r));
 const base=`http://127.0.0.1:${server.address().port}`;
 try{
  const response=await hubFetch(new URL(base),{method:'POST',headers:{Authorization:'Bearer test'},body:JSON.stringify({tokens:0})});
  assert.deepEqual(await response.json(),{authenticated:true,data:{tokens:0}});
  const redirected=await hubFetch(new URL(base+'/redirect'));assert.equal(redirected.ok,false);assert.equal(redirected.status,302);assert.equal(redirects,0);
 }finally{await new Promise(r=>server.close(r))}
});
test('aborted Hub request rejects without leaving its socket open',async()=>{
 const server=http.createServer(()=>{});await new Promise(r=>server.listen(0,'127.0.0.1',r));
 try{await assert.rejects(hubFetch(new URL(`http://127.0.0.1:${server.address().port}`),{signal:AbortSignal.timeout(20)}));}
 finally{server.closeAllConnections();await new Promise(r=>server.close(r))}
});
