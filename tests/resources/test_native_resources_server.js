#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Ephemeral synthetic-resource fixture. Production resource serving is imported
// unchanged; only fault timing/control/counting belongs to this test process.
'use strict';
const fs=require('node:fs'),path=require('node:path'),http=require('node:http');
const config=JSON.parse(fs.readFileSync(process.argv[2],'utf8'));
const create=require(path.resolve(config.module)).create;
if(config.probeLocalOnly){
 const provider=create({localOnly:config.probeLocalOnly}),connections=new Set();
 const server=http.createServer((req,res)=>{const p=new URL(req.url,'http://fixture').pathname;if(provider.matches(p))return provider.handle(req,res,p);res.writeHead(404);res.end()});
 server.on('connection',socket=>{connections.add(socket);socket.on('close',()=>connections.delete(socket))});
 const close=()=>{for(const socket of connections)socket.destroy();server.close()};process.on('SIGTERM',close);process.on('SIGINT',close);
 server.listen(0,'127.0.0.1',()=>fs.writeFileSync(config.readyFile,JSON.stringify({port:server.address().port,pid:process.pid})));
}else{
const catalog=path.join(config.localOnly,'resources-v1/catalog.json');
const payload=path.join(config.localOnly,'site/game/native/test-payload.bin');
const counts={a:{manifest:0,blobs:0,static:0,api:0},b:{manifest:0,blobs:0,static:0,api:0}},events=[];
let phase='A',closedA=false;const sockets=new Set();
function activate(name){
 const key=name.endsWith('C')?'C':name;
 if(!['A','B','C'].includes(key))throw Error('Bad fixture phase');
 fs.writeFileSync(payload,fs.readFileSync(config.phases[key].payload));
 if(name==='corruptC') {const value=fs.readFileSync(payload);value[0]^=255;fs.writeFileSync(payload,value);}
 fs.copyFileSync(config.phases[key].catalog,catalog+'.pending');fs.renameSync(catalog+'.pending',catalog);phase=name;
}
function json(res,value,status=200){const b=Buffer.from(JSON.stringify(value));res.writeHead(status,{'Content-Type':'application/json','Content-Length':b.length});res.end(b);}
const make=label=>{
 const resources=create({localOnly:config.localOnly});
 return http.createServer(async(req,res)=>{
  try{
   const u=new URL(req.url,'http://fixture'),p=u.pathname;
   if(label==='b'&&p==='/__qa'){
    if(req.method!=='POST')return json(res,{error:'POST only'},405);
    let size=0,data=[];for await(const part of req){size+=part.length;if(size>8192)throw Error('Bounded control body');data.push(part)}
    const input=JSON.parse(Buffer.concat(data));
    if(input.action==='phase')activate(input.phase);
    else if(input.action==='stopA'&&!closedA){closedA=true;a.close();}
    else if(input.action!=='stats')throw Error('Unknown private fixture control');
    return json(res,{phase,closedA,counts,events});
   }
   if(p==='/game/native/resource-manifest.json')counts[label].manifest++;
   else if(p.startsWith('/game/native/resource-blobs/'))counts[label].blobs++;
   else if(p.startsWith('/api/'))counts[label].api++;
   else counts[label].static++;
   const event={at:Date.now()/1000,label,method:req.method,path:p};events.push(event);if(events.length>4096)throw Error('Fixture event bound');
   res.once('finish',()=>{event.status=res.statusCode});
   if(resources.matches(p)) {
    if(phase==='delayC'&&p.endsWith(config.phases.C.digest))return setTimeout(()=>{if(!res.destroyed)resources.handle(req,res,p)},3000);
    return resources.handle(req,res,p);
   }
   if(p==='/api/local/status')return json(res,{fixture:true,network:true});
   const logical=p.replace(/^\//,'');
   if(!config.allowedPaths.includes(logical))return json(res,{error:'Synthetic resource not found'},404);
   const file=path.join(config.localOnly,'site',logical),bytes=fs.readFileSync(file);
   res.writeHead(200,{'Content-Type':'application/octet-stream','Content-Length':bytes.length});res.end(req.method==='HEAD'?undefined:bytes);
  }catch(error){json(res,{error:error.message},400)}
 });
};
const a=make('a'),b=make('b');
for(const server of [a,b])server.on('connection',s=>{sockets.add(s);s.on('close',()=>sockets.delete(s))});
function stop(){for(const s of sockets)s.destroy();a.close();b.close();setTimeout(()=>process.exit(),50).unref();}
process.on('SIGTERM',stop);process.on('SIGINT',stop);
(async()=>{activate('A');await new Promise(r=>a.listen(0,'127.0.0.1',r));await new Promise(r=>b.listen(0,'127.0.0.1',r));const result={a:'http://127.0.0.1:'+a.address().port,b:'http://127.0.0.1:'+b.address().port,pid:process.pid};fs.writeFileSync(config.readyFile,JSON.stringify(result));console.log('SYNTHETIC_RESOURCE_FIXTURE_READY');})().catch(e=>{console.error(e.message);stop();process.exitCode=1});

}
