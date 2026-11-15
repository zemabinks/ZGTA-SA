#!/usr/bin/env node
'use strict';
// A separate backend process owns only the temporary directory supplied by the
// Python runner. The control listener never replaces production/QA services.
const http=require('node:http'),path=require('node:path'),assert=require('node:assert/strict');
const {fork,spawn}=require('node:child_process');
const workerMode=process.argv[2]==='--worker';
const json=(res,status,body)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(body));};

if(workerMode){
 const game=require(path.join(process.argv[3],'selfhost_backend.js'));
 let rules=[],next=0,initial=new Set(JSON.parse(process.argv[5]||'[]')),victim;
 const held=new Map(),baseline=[],sockets=new Set(),requests=[];
 const event=value=>process.send?.({event:value});
 const original=game.onMessage.bind(game);
 game.onMessage=(peer,message)=>{
  if(!peer.fixtureSend){
   const send=peer.send.bind(peer);peer.fixtureSend=send;
   peer.send=packet=>{
    if(initial.has(packet.t)){baseline.push({type:packet.t,send:()=>send(packet)});return;}
    send(packet);
   };
  }
  event({kind:'packet',t:message.t,number:peer.player.number,c:message.c||null,s:message.s||null,
         say:message.say||null,weapon:message.w||null});
  original(peer,message);
 };
 const server=http.createServer((req,res)=>{
  res.on('error',()=>{});
  const url=new URL(req.url,'http://fixture');
  const kind=url.pathname==='/api/local/state'?'state':url.pathname==='/api/local/action'?'action':null;
  if(kind){
   const i=rules.findIndex(rule=>rule.kind===kind),rule=i<0?{}:rules.splice(i,1)[0];
   const id=++next,tag=rule.tag||'http-'+id;
   const entry={id,kind,tag,connection:req.headers['x-zgta-inventory-connection']||null};requests.push(entry);
   const end=res.end.bind(res),writeHead=res.writeHead.bind(res);let headers={};
   res.writeHead=(status,fields)=>{res.statusCode=status;headers=fields||{};return res;};
   res.end=(body,...args)=>{
    let bytes=body;
    try{
     const value=JSON.parse(Buffer.isBuffer(body)?body.toString():body);
     if(kind==='state')value.fixtureRequest=tag;else if(value.state)value.state.fixtureRequest=tag;
     bytes=Buffer.from(JSON.stringify(value));
    }catch(error){throw Error('Expected actual backend JSON response: '+error.message);}
    entry.status=res.statusCode;entry.ready=true;event({kind:'http',...entry});
    const deliver=()=>{
     if(res.destroyed)return;
     const fields=Object.fromEntries(Object.entries(headers).filter(([key])=>key.toLowerCase()!=='content-length'));
     fields['Content-Length']=Buffer.byteLength(bytes);writeHead(res.statusCode,fields);end(bytes,...args);
    };
    if(rule.hold){held.set(tag,deliver);return res;}
    deliver();return res;
   };
  }
  Promise.resolve(game.http(req,res)).catch(error=>json(res,500,{error:error.message}));
 });
 server.on('upgrade',(req,socket,head)=>{sockets.add(socket);socket.on('close',()=>sockets.delete(socket));game.upgrade(req,socket,head);});
 const summary=()=>({players:[...game.players].map(([id,p])=>({id,number:p.number,name:p.name,health:p.health,
      selected:p.inventory?.selected,clip:p.inventory?.weapons?.[22]?.clip,rest:p.inventory?.weapons?.[22]?.rest})),
   peers:[...game.peers].filter(p=>p.ready&&!p.closed).map(p=>({number:p.player.number,nonce:p.inventoryConnection,
      position:p.state?{x:p.state.x,y:p.state.y,z:p.state.z}:null})),
   held:[...held.keys()],requests,chatSequence:game.chatSequence,baseline:baseline.map(row=>row.type)});
 process.on('message',async request=>{
  try{
   let result={};const a=request.args||{};
   switch(request.command){
    case 'report':result=summary();break;
    case 'rules':rules.push(...a.rules);break;
    case 'release':{const done=held.get(a.tag);assert(done,'Missing held HTTP response '+a.tag);held.delete(a.tag);done();break;}
    case 'baseline':initial.delete(a.type);for(let i=baseline.length-1;i>=0;i--)if(baseline[i].type===a.type){const row=baseline.splice(i,1)[0];row.send();}break;
    case 'hold-baseline':initial.add(a.type);break;
    case 'seed':{const p=game.players.get(a.id);assert(p);p.name='Recovery Guest';p.inventory={revision:10,selected:22,weapons:{22:{clip:17,rest:30}}};game.flushSync();for(const peer of game.peers)if(peer.player===p&&peer.ready)game.sendInventory(peer);break;}
    case 'drop':for(const socket of sockets)socket.destroy();break;
    case 'checkpoint':game.flushSync();result=summary();break;
    case 'chat':{const peer=[...game.peers].find(p=>p.ready&&p.player.name==='Recovery Guest');assert(peer);game.chatSequence=a.sequence;game.say(peer,a.text);break;}
    case 'victim':{
     victim=new WebSocket('ws://127.0.0.1:'+server.address().port+'/api/world/live');
     await new Promise((resolve,reject)=>{victim.addEventListener('open',resolve,{once:true});victim.addEventListener('error',reject,{once:true});});
     victim.send(JSON.stringify({t:'hi',nativeInventory:true,inventoryAck:1}));
     victim.send(JSON.stringify({t:'me',walking:true,skin:7,x:1484,y:-1738,z:13,h:0,weapon:0}));break;
    }
    default:throw Error('Unknown worker command '+request.command);
   }
   process.send?.({reply:request.id,result});
  }catch(error){process.send?.({reply:request.id,error:error.stack});}
 });
 server.listen(Number(process.argv[4]),'127.0.0.1',()=>process.send?.({ready:server.address().port}));
}else{
 let child,executable,gamePort=0,epoch=0,requestID=0,finished=false,lastSnapshot={};
 const pending=new Map(),events=[];
 const rpc=(command,args={})=>new Promise((resolve,reject)=>{
  if(!child?.connected)return reject(Error('Backend is offline'));
  const id=++requestID;pending.set(id,{resolve,reject});child.send({id,command,args});
 });
 async function start(hold=[]){
  epoch++;const processEpoch=epoch;
  child=fork(__filename,['--worker',process.argv[2],String(gamePort),JSON.stringify(hold)],{stdio:['ignore','inherit','inherit','ipc']});
  await new Promise((resolve,reject)=>{
   child.on('message',message=>{
    if(message.ready){gamePort=message.ready;resolve();}
    if(message.event)events.push({epoch:processEpoch,...message.event});
    if(message.reply){const p=pending.get(message.reply);if(p){pending.delete(message.reply);message.error?p.reject(Error(message.error)):p.resolve(message.result);}}
   });
   child.once('error',reject);
  });
 }
 const controls=http.createServer(async(req,res)=>{
  try{
   let body='';for await(const part of req)body+=part;
   const request=body?JSON.parse(body):{command:'report'},a=request.args||{};
   if(request.command==='offline'){
    lastSnapshot=await rpc('checkpoint');const old=child;child=null;
    const exited=new Promise(resolve=>old.once('exit',resolve));old.kill('SIGKILL');await exited;
    return json(res,200,{online:false,events,snapshot:lastSnapshot});
   }
   if(request.command==='restart'){assert(!child);await start(a.hold||[]);return json(res,200,{online:true,epoch});}
   if(request.command==='report'){
    if(child)lastSnapshot=await rpc('report');return json(res,200,{online:!!child,epoch,events,snapshot:lastSnapshot});
   }
   json(res,200,await rpc(request.command,a));
  }catch(error){json(res,500,{error:error.stack});}
 });
 (async()=>{
  await new Promise(resolve=>controls.listen(0,'127.0.0.1',resolve));
  await start(['all','inventory']);
  executable=spawn(process.argv[3],['http://127.0.0.1:'+gamePort,'http://127.0.0.1:'+controls.address().port],{stdio:'inherit'});
  const code=await new Promise(resolve=>executable.once('exit',resolve));assert.equal(code,0);
  finished=true;console.log('PASS real independent backend recovery: temporary process restart, fresh peer ACKs and HTTP generation barriers');
 })().catch(error=>{console.error(error);process.exitCode=1;}).finally(async()=>{
  if(executable?.exitCode===null)executable.kill();
  if(child){const exited=new Promise(resolve=>child.once('exit',resolve));child.kill('SIGKILL');await exited;}
  await new Promise(resolve=>controls.close(resolve));
 });
 setTimeout(()=>{if(!finished){executable?.kill();child?.kill('SIGKILL');throw Error('Recovery fixture timed out');}},90000).unref();
}
