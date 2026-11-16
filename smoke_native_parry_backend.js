#!/usr/bin/env node
'use strict';
const http=require('node:http'),path=require('node:path'),fs=require('node:fs'),{spawn}=require('node:child_process');
const game=require(path.join(process.argv[2],'selfhost_backend.js'));
clearInterval(game.tick);clearInterval(game.projectileTimer);
let checks=0,child,observer,native,attacker,index=0,hitPackets=0,complete=false,stopping=false;
const sockets=new Set(),original=game.onMessage.bind(game);
function check(ok,message){checks++;if(!ok)throw Error(message)}
function stop(){if(stopping)return;stopping=true;observer?.close();server.close();for(const socket of sockets)socket.destroy();game.flushSync()}
function fail(error){console.error(error);process.exitCode=1;child?.kill();stop()}
const server=http.createServer((req,res)=>Promise.resolve(game.http(req,res)).catch(fail));
server.on('upgrade',(req,socket,head)=>{sockets.add(socket);socket.once('close',()=>sockets.delete(socket));game.upgrade(req,socket,head)});
const specs=[{parried:true},{parried:true},{heading:Math.PI},{act:36},{weapon:9},{parried:true},{parried:true},{parried:true}];
function punch(){
 const spec=specs[index-1];
 observer.send(JSON.stringify({t:'me',walking:true,skin:7,x:1570,y:-2460,z:13.6,heading:0,weapon:spec.weapon||0}));
 observer.send(JSON.stringify({t:'hit',to:String(native.player.number)}));
}
game.onMessage=(peer,message)=>{
 try{
  original(peer,message);
  if(message.t==='hi'&&message.nativeInventory===true){
   if(hitPackets===7)check(peer.inventoryConnection!==native.inventoryConnection,'Reconnect reused old hit connection');
   native=peer;check(peer.ready&&peer.healthAckEnabled,'Native health ownership missing');
   peer.player.armour=hitPackets===7?34:80;peer.send({t:'vitals'});
   const send=peer.send.bind(peer);peer.send=packet=>{
    if(packet.t!=='hit')return send(packet);
    hitPackets++;const spec=specs[hitPackets-1];
    check(packet.parried===(spec.parried===true),'Authority chose wrong parry decision '+hitPackets);
    check(packet.hitAck?.connection===peer.inventoryConnection&&packet.hitAck.sequence===(hitPackets===8?1:hitPackets),'Event identity not assigned once by authority');
    check(packet.beforeHealth===100,'A block or armour absorption incorrectly lost health');
    if(spec.parried)check(peer.player.armour===(hitPackets<=2?80:34),'Parry consumed armour');
    send({t:'vitals'});
    // Rejected event identities cannot steal/replay a later accepted sequence.
    for(const ack of [{connection:'obsolete-connection',sequence:hitPackets+100},
       {connection:peer.inventoryConnection,sequence:true},{connection:peer.inventoryConnection,sequence:0}])
      send({...packet,hitAck:ack});
    send(packet);send(packet);
    send({...packet,hitAck:undefined}); // no downgrade to old health-revision delivery
    send({t:'note',text:'PARRY CASE '+hitPackets});
    if(hitPackets===8)observer.send(JSON.stringify({t:'me',walking:true,skin:7,x:1570,y:-2460,z:13.6,heading:Math.PI,weapon:0,act:28}));
   };
  }
  if(peer===native&&message.t==='me'&&message.walking===true){
   index++;check(index<=specs.length,'Unexpected native position');
   const spec=specs[index-1];
   check((message.act&63)===(spec.act||28),'Native action did not reach authority');
   check(Math.abs(message.heading-(spec.heading||0))<1e-5,'Wire heading convention changed');
   setTimeout(()=>{try{punch()}catch(error){fail(error)}},index===1?20:325);
  }
  if(peer!==native&&message.t==='hi')attacker=peer;
  if(peer===attacker&&message.t==='me'&&message.act===28&&hitPackets===8){attacker.player.armour=25;native.send({t:'note',text:'LEGACY READY'});}
 }catch(error){fail(error)}
};
server.listen(0,'127.0.0.1',()=>{
 const base='http://127.0.0.1:'+server.address().port;
 observer=new WebSocket(base.replace('http:','ws:')+'/api/world/live');
 observer.addEventListener('error',event=>{if(!stopping)fail(event.error||Error('Legacy socket error'))});
 observer.addEventListener('open',()=>observer.send(JSON.stringify({t:'hi'})));
 observer.addEventListener('message',event=>{
  try{
   const message=JSON.parse(event.data);
   if(message.t==='all'&&!child){
    child=spawn(process.argv[3],[base],{stdio:'inherit'});child.on('error',fail);child.on('exit',code=>{
     if(stopping)return;try{
      check(code===0&&complete&&index===specs.length&&hitPackets===specs.length,'Native parry scenarios incomplete: '+JSON.stringify({code,index,hitPackets,complete}));
      check(native.player.health===100&&native.player.armour===34,'Blocked/damaging health ownership changed');stop();

     }catch(error){fail(error)}
    });return;
   }
   if(message.t==='me'&&hitPackets===8){observer.send(JSON.stringify(message));return}
   if(message.t==='hit'&&index===specs.length){
    check(JSON.stringify(Object.keys(message).sort())===JSON.stringify(['d','from','t','w']),'Legacy hit envelope changed');
    check(message.d>0&&attacker.player.health===100&&attacker.player.armour===25,'Legacy front block damaged health/armour');
    native.send({t:'note',text:'LEGACY BLOCK COMPLETE'});
    complete=true;fs.writeFileSync(process.argv[4],JSON.stringify({status:'PASS',checks,hitPackets,health:native.player.health,armour:native.player.armour},null,2)+'\n');
    console.log(`PASS native/legacy parry authority: ${checks} checks, ${hitPackets} native events plus legacy front block`);
   }
  }catch(error){fail(error)}
 });
});
setTimeout(()=>{if(!complete&&!stopping)fail(Error('Parry backend timed out: case'+index+' hits'+hitPackets))},25000).unref();
