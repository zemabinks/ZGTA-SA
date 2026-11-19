#!/usr/bin/env node
'use strict';
// Actual HTTP/WS/health/hit authority, controlled synthetic floor and one
// deliberately duplicated outgoing event. No production users/assets/state.
const http=require('node:http'),path=require('node:path'),fs=require('node:fs'),{spawn}=require('node:child_process');
const game=require(path.join(process.argv[2],'selfhost_backend.js'));
clearInterval(game.tick);clearInterval(game.projectileTimer);
let checks=0,child,observer,native,stage=0,shots=0,hitPackets=0,complete=false,stopping=false;
const sockets=new Set(),original=game.onMessage.bind(game);
function check(ok,message){checks++;if(!ok)throw Error(message)}
function stop(){if(stopping)return;stopping=true;observer?.close();server.close();for(const socket of sockets)socket.destroy();game.flushSync()}
function fail(error){console.error(error);process.exitCode=1;child?.kill();stop()}
const server=http.createServer((req,res)=>Promise.resolve(game.http(req,res)).catch(fail));
server.on('upgrade',(req,socket,head)=>{sockets.add(socket);socket.once('close',()=>sockets.delete(socket));game.upgrade(req,socket,head)});
function punch(){shots++;observer.send(JSON.stringify({t:'hit',to:String(native.player.number)}))}
game.onMessage=(peer,message)=>{
 try{
  original(peer,message);
  if(message.t==='hi'&&message.nativeInventory===true){
   native=peer;check(peer.ready&&peer.healthAckEnabled,'Native did not negotiate actual health ownership');
   const send=peer.send.bind(peer);peer.send=packet=>{
    if(packet.t!=='hit')return send(packet);
    hitPackets++;check(packet.beforeHealth>0&&packet.fromAt[0]===1570&&packet.fromAt[1]===-2460,'Authority omitted event context');
    // A status snapshot wins the race, then the actual hit is delivered
    // twice. Health/animation authority must each remain single-owned.
    send({t:'vitals'});send(packet);send(packet);
    send({t:'note',text:hitPackets===1?'FIRST HIT COMPLETE':'FATAL HIT COMPLETE'});
   };
  }
  if(peer===native&&message.t==='me'&&message.walking===true){
   if(stage===0){stage=1;punch()}
   else if(stage===1&&message.down===2){check(game.row(peer)[38]===2,'Authority dropped knock tag');stage=2;observer.send(JSON.stringify({t:'hi'}))}
   else if(stage===3&&message.down===0){check(game.row(peer)[38]===0,'Authority retained knock tag');stage=4;observer.send(JSON.stringify({t:'hi'}))}
  }
 }catch(error){fail(error)}
};
server.listen(0,'127.0.0.1',()=>{
 const base='http://127.0.0.1:'+server.address().port;
 observer=new WebSocket(base.replace('http:','ws:')+'/api/world/live');
 observer.addEventListener('error',event=>{if(!stopping)fail(event.error||Error('Legacy peer socket error'))});
 observer.addEventListener('open',()=>observer.send(JSON.stringify({t:'hi'})));
 observer.addEventListener('message',event=>{
  try{
   const message=JSON.parse(event.data);if(message.t!=='all')return;
   if(!child){
    observer.send(JSON.stringify({t:'me',walking:true,skin:7,x:1570,y:-2460,z:13.6,heading:0,weapon:0}));
    child=spawn(process.argv[3],[base],{stdio:'inherit'});child.on('error',fail);child.on('exit',code=>{
     if(stopping)return;try{check(code===0&&stage===5&&shots===2&&hitPackets===2,'Hit/legacy fixture did not complete');complete=true;
      fs.writeFileSync(process.argv[4],JSON.stringify({status:'PASS',checks,shots,hitPackets,stage,finalHealth:native.player.health},null,2)+'\n');
      console.log(`PASS actual hit authority: ${checks} checks; 2 accepted hits, snapshot/event races and duplicate delivery, legacy down/recovery`);
     }catch(error){fail(error)}finally{stop()}
    });return;
   }
   const row=message.cars.find(row=>String(row[0])===String(native.player.number));check(row!=null,'Legacy observer lost native walker');
   if(stage===2){check(row[38]===2,'Legacy did not observe knockdown');stage=3;native.send({t:'note',text:'DOWN OBSERVED'})}
   else if(stage===4){check(row[38]===0,'Legacy did not observe recovery');stage=5;
    setTimeout(()=>{try{native.player.health=5;native.send({t:'vitals'});punch()}catch(error){fail(error)}},350);
   }
  }catch(error){fail(error)}
 });
});
setTimeout(()=>{if(!complete&&!stopping)fail(Error('Hit backend timed out: stage'+stage+' hits'+hitPackets))},25000).unref();
