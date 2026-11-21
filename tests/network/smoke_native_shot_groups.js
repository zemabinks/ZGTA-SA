#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Actual backend HTTP/Peer/WebSocket with two authored in-memory victims.
// This test server declines unrelated position-ACK negotiation explicitly.
const http=require('node:http'),path=require('node:path'),assert=require('node:assert/strict'),{spawn}=require('node:child_process');
const game=require(path.join(process.argv[2],'selfhost_backend.js')),sockets=new Set(),original=game.onMessage.bind(game);
let child,finished=false,joins=0,shots=0,hits=0,counter=false,settlement;
function victim(x,y) {
 const account=game.ensurePlayer({headers:{cookie:''}},{setHeader(){}}),packets=[];
 const peer={id:account.id,player:account.player,ready:true,lastSeen:Date.now(),closed:false,state:{walking:true,x,y,z:13.6},packets,send:m=>packets.push(structuredClone(m))};
 game.peers.add(peer);return peer;
}
const b=victim(1574,-2460),c=victim(1574,-2458);
game.onMessage=(peer,message)=>{
 if(message.t==='hi') {
  assert.equal(++joins,1);assert.equal(message.ordinaryShots,1);assert.equal(message.inventoryAck,1);
  const send=peer.send.bind(peer);peer.send=packet=>{if(packet.t==='inventory'&&packet.result)settlement=packet.result;send(packet);};
  peer.player.inventory={selected:25,weapons:{25:{clip:5,rest:20}}};
  original(peer,{...message,positionAck:0});
  setTimeout(()=>{
   peer.send({t:'hello',inventoryAck:1,inventoryConnection:peer.inventoryConnection,life:[100,0]});
   peer.send({t:'note',text:`GROUP_TARGETS ${b.player.number} ${c.player.number}`});
  },50);return;
 }
 if(message.t==='me'&&shots===0){
  original(peer,message);assert.equal(game.position(peer.player)?.x,1570,'Normal native position was not admitted');
  peer.send({t:'note',text:'GROUP_POSE'});return;
 }
 if(message.t==='shot') {
  assert.equal(++shots,1);assert.equal(message.w,25);assert.equal(message.s,1);assert.equal(message.c,peer.inventoryConnection);
  assert.equal(message.rays.length,3);assert.deepEqual(message.rays.map(r=>r.n||1),[3,2,1]);
  const stale={t:'struck',from:String(peer.player.number),w:25,ht:1,id:String(b.player.number),o:message.o,h:message.h,bp:3};
  peer.send({...stale,c:'foreign-connection',s:1});
  peer.send({...stale,c:peer.inventoryConnection,s:0});
  peer.send({...stale,c:peer.inventoryConnection,s:1.5});
  original(peer,message);assert.equal(settlement?.accepted,true,'Actual server rejected the authored marker: '+JSON.stringify(settlement));assert.equal(peer.player.inventory.weapons[25].clip,4);assert.equal(b.player.health,88);assert.equal(c.player.health,92);
  assert.equal(b.packets.filter(m=>m.t==='hit').length,1);assert.equal(c.packets.filter(m=>m.t==='hit').length,1);
  peer.send({t:'note',text:'GROUP_SETTLED'});return;
 }
 if(message.t==='hit')hits++;
 if(message.t==='me'&&shots===1){assert.equal(message.shots,1,'Several target groups changed the firing counter');counter=true;peer.send({t:'note',text:'GROUP_COUNTER'});}
 original(peer,message);
};
const server=http.createServer((req,res)=>Promise.resolve(game.http(req,res)).catch(error=>{console.error(error);res.writeHead(500);res.end();}));
server.on('upgrade',(req,socket,head)=>{sockets.add(socket);socket.on('close',()=>sockets.delete(socket));game.upgrade(req,socket,head);});
function stop(){for(const socket of sockets)socket.destroy();server.close();clearInterval(game.tick);clearInterval(game.projectileTimer);game.flushSync();}
server.listen(0,'127.0.0.1',()=>{
 child=spawn(process.argv[3],['http://127.0.0.1:'+server.address().port],{stdio:'inherit'});
 child.on('exit',code=>{try{assert.equal(code,0);assert.equal(joins,1);assert.equal(shots,1);assert.equal(hits,0,'Native sent redundant hit requests after atomic authority');assert(counter);finished=true;console.log('PASS actual backend/native grouped-shot socket: one join, one emission/round/counter, two independently damaged victims and zero redundant hit packets')}catch(error){console.error(error);process.exitCode=1}finally{stop()}});
});
setTimeout(()=>{if(!finished){child?.kill();stop();console.error('FAIL grouped-shot backend timeout');process.exitCode=1}},30000).unref();
