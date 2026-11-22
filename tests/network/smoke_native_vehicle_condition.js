#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Real HTTP/WebSocket/Peer/backend and an actual native receiving client.
// The driver uses explicit in-memory transport and normal admission handlers.
const http=require('node:http'),path=require('node:path'),assert=require('node:assert/strict'),{spawn}=require('node:child_process');
const game=require(path.join(process.argv[2],'selfhost_backend.js')),sockets=new Set(),original=game.onMessage.bind(game);
clearInterval(game.tick);clearInterval(game.projectileTimer);
const {player}=game.ensurePlayer({headers:{cookie:''}},{setHeader(){}}),driver={player,ready:false,lastSeen:Date.now(),closed:false,state:null,send(){}};
const damage='3434012122110101201',car={id:'authored-condition',row:['authored-condition','Authored','420.4.5.0.',100,100,20,0,0,0,1000,'',null]};
const foot={t:'me',walking:true,skin:7,x:100,y:100,z:20,health:100,armour:0};
const drive=health=>({t:'me',driving:true,skin:7,vehicle:car.id,car:car.row[2],x:100,y:100,z:20,health,life:100,damage:''});
game.peers.add(driver);original(driver,{t:'hi'});original(driver,foot);game.vehicles.set(car.id,car);
original(driver,{t:'enter',v:car.id});original(driver,{...drive(645),damage});original(driver,drive(900));
assert.equal(game.vehicleDriver(car),driver);assert.deepEqual(car.row.slice(9,11),[645,damage]);
let child,finished=false,joins=0,phase=0;
game.onMessage=(peer,message)=>{
 if(message.t==='hi'){
  assert.equal(++joins,1);assert.equal(message.inventoryAck,1);
  // This receiver test explicitly declines unrelated physical placement ACKs.
  original(peer,{...message,positionAck:0});
  setTimeout(()=>peer.send({t:'note',text:'CORE184_BASELINE'}),50);return;
 }
 original(peer,message);
 if(message.t!=='me'||!message.say)return;
 if(message.say==='CORE184_BASELINE_OK'){
  assert.equal(phase++,0);assert.equal(game.row(driver)[18],645);
  original(driver,{t:'exit',v:car.id,x:100,y:100,z:20,h:0,p:0,r:0,hp:600,d:damage});
  original(driver,drive(999));game.publishPlayerRows();peer.send({t:'note',text:'CORE184_QUEUED'});
 }else if(message.say==='CORE184_QUEUED_OK'){
  assert.equal(phase++,1);
  original(driver,{...foot,vehicle:car.id,car:car.row[2],parked:{x:100,y:100,z:20,heading:0,health:900,damage:''}});
  assert.equal(game.vehicleClaim(car),null);assert.deepEqual(game.row(driver)[33].slice(7,9),[645,damage]);
  peer.send({t:'note',text:'CORE184_PARKED'});
 }else if(message.say==='CORE184_PARKED_OK'){
  assert.equal(phase++,2);
  original(driver,{t:'vmove',v:car.id,x:100,y:100,z:20,h:0,p:0,r:0,hp:900,d:''});
  assert.deepEqual(car.row.slice(9,11),[645,damage]);peer.send({t:'note',text:'CORE184_UNATTENDED'});
 }else if(message.say==='CORE184_UNATTENDED_OK'){
  assert.equal(phase++,3);
  original(driver,{t:'vmove',v:car.id,x:101,y:100,z:20,h:0,p:0,r:0,hp:500,d:'0000000000000000001'});
  // Repeat the original accepted foot report after a genuine later hull
  // update. It must describe that current body rather than undo its motion.
  game.publishPlayerRows();peer.send({t:'note',text:'CORE184_BUMPED'});
 }else if(message.say==='CORE184_BUMPED_OK'){
  assert.equal(phase++,4);
  const replacement={id:car.id,row:[...car.row]};replacement.row[3]=103;replacement.row[9]=1000;replacement.row[10]='fresh';
  game.vehicles.set(car.id,replacement);game.publishVehicle(replacement);game.publishPlayerRows();
  assert.equal(game.row(driver)[33],null);assert.equal(game.row(driver)[35],null);peer.send({t:'note',text:'CORE184_REPLACED'});
 }else if(message.say==='CORE184_REPLACED_OK'){
  assert.equal(phase++,5);peer.send({t:'note',text:'CORE184_DONE'});
 }
};
const server=http.createServer((req,res)=>Promise.resolve(game.http(req,res)).catch(error=>{console.error(error);res.writeHead(500);res.end();}));
server.on('upgrade',(req,socket,head)=>{sockets.add(socket);socket.on('close',()=>sockets.delete(socket));game.upgrade(req,socket,head);});
function stop(){for(const socket of sockets)socket.destroy();server.close();clearInterval(game.tick);clearInterval(game.projectileTimer);clearTimeout(game.saveTimer);}
server.listen(0,'127.0.0.1',()=>{
 child=spawn(process.argv[3],['http://127.0.0.1:'+server.address().port],{stdio:'inherit'});
 child.on('exit',code=>{try{assert.equal(code,0);assert.equal(joins,1);assert.equal(phase,6);finished=true;console.log('PASS actual backend/native receiver: one join and received baseline/queued-drive/parked/unattended/later-bump/replacement over real WebSockets')}catch(error){console.error(error);process.exitCode=1}finally{stop()}});
});
setTimeout(()=>{if(!finished){child?.kill();stop();console.error('FAIL native condition wire timeout');process.exitCode=1}},30000).unref();
