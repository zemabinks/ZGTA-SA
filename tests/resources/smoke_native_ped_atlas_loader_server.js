#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Disposable authored resource peer. No game backend, accounts or original files.
const fs=require('node:fs'),path=require('node:path'),http=require('node:http');
const root=path.resolve(process.argv[2]),rows=JSON.parse(fs.readFileSync(path.join(root,'fixtures.json'))),allowed=new Map(),metadata=new Set(),atlases=new Set();
for(const row of rows){allowed.set('/'+row.path,path.join(root,row.path));metadata.add('/'+row.path);for(const [role,r]of Object.entries(row.manifest.resources)){allowed.set('/'+r.path,path.join(root,r.path));if(role==='atlas')atlases.add('/'+r.path)}}
let mode='ok',aborted=0,activeMembers=0;const records=[];
const server=http.createServer((req,res)=>{
 if(req.url==='/control'){
  if(req.method==='GET'){res.setHeader('Content-Type','application/json');res.end(JSON.stringify({mode,aborted,activeMembers,records}));return}
  if(req.method!=='POST'){res.writeHead(405).end();return}
  let body='';req.on('data',b=>{body+=b;if(body.length>1024)req.destroy()});req.on('end',()=>{try{const v=JSON.parse(body);if(!['ok','delay','corrupt','oversize'].includes(v.mode))throw Error();mode=v.mode;res.end('{}')}catch{res.writeHead(400).end()}});return
 }
 if(req.method!=='GET'||!allowed.has(req.url)){res.writeHead(404).end();return}
 const member=!metadata.has(req.url),record={path:req.url,aborted:false,finished:false};records.push(record);if(records.length>4096){res.writeHead(429).end();return}
 if(member)activeMembers++;
 let timer;res.once('close',()=>{clearTimeout(timer);if(member)activeMembers--;if(!res.writableEnded){record.aborted=true;aborted++}else{record.finished=true}});
 const selected=mode;
 function send(){
  if(res.destroyed)return;let data=fs.readFileSync(allowed.get(req.url));
  if(atlases.has(req.url)&&selected==='corrupt'){data=Buffer.from(data);data[0]^=1}
  if(atlases.has(req.url)&&selected==='oversize')data=Buffer.concat([data,Buffer.from([1])]);
  res.writeHead(200,{'Content-Length':data.length,'Content-Type':req.url.endsWith('.json')?'application/json':'application/octet-stream'});res.end(data)
 }
 if(member&&selected==='delay')timer=setTimeout(send,4000);else send();
});
server.listen(0,'127.0.0.1',()=>console.log(JSON.stringify({port:server.address().port})));
process.on('SIGTERM',()=>server.close(()=>process.exit(0)));
