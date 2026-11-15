#!/usr/bin/env node
'use strict';
// Actual backend/Peer/HTTP/WebSocket, isolated synthetic account and listeners.
const http=require('node:http'),path=require('node:path'),assert=require('node:assert/strict'),{spawn}=require('node:child_process');
const game=require(path.join(process.argv[2],'selfhost_backend.js'));
let child,stale,firstPlayer,firstNonce,joins=0,requests=0,complete=false;
const sockets=new Set(),original=game.onMessage.bind(game);
const server=http.createServer((req,res)=>{
 if(req.url==='/fixture/stale') {res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(stale));return;}
 Promise.resolve(game.http(req,res)).catch(error=>{res.writeHead(500);res.end(JSON.stringify({error:error.message}));});
});
server.on('upgrade',(req,socket,head)=>{sockets.add(socket);socket.on('close',()=>sockets.delete(socket));game.upgrade(req,socket,head);});
game.onMessage=(peer,message)=>{
 if(message.t==='hi') {
  joins++;
  if(joins===1){firstPlayer=peer.player;peer.player.armour=25;}
  else {assert.equal(peer.player,firstPlayer,'Reconnect lost saved guest identity');assert.equal(peer.player.health,70);}
  original(peer,message);
  if(joins===1) firstNonce=peer.inventoryConnection;
  else {assert.notEqual(peer.inventoryConnection,firstNonce);peer.send({t:'note',text:'HEALTH REJOINED'});}
  return;
 }
 if(message.t==='selfHealth') {
  requests++;
  if(message.s===1) {
   assert.equal(message.kind,'hurt');assert.equal(message.damage,40);
   // An earlier server-owned loss arrives after local prediction, then HTTP
   // later delivers that same old snapshot after two newer WS revisions.
   peer.player.health=90;
   stale=game.healthState(peer);peer.send({t:'vitals',...stale});
   const hello={t:'hello',inventoryAck:1,inventoryConnection:peer.inventoryConnection};
   peer.send({...hello,life:[90,25],...stale});
   peer.send({...hello,life:[100,25],healthAck:{...stale.healthAck,revision:0}});
   peer.send({...hello,life:[100,25]});
   original(peer,message);assert.equal(peer.player.health,50);assert.equal(peer.player.armour,25);
   peer.player.health=43;peer.player.armour=0;
   peer.send({t:'hit',from:'fixture',w:22,d:32});
   peer.send({t:'note',text:'HEALTH PHASE ONE'});
  } else if(message.s===2) {
   assert.equal(message.kind,'hurt');assert.equal(message.damage,43);
   original(peer,message);assert.equal(peer.player.health,0);
   peer.send({t:'note',text:'FATAL ACK'});
  } else if(message.s===3) {
   assert.equal(message.kind,'respawn');original(peer,message);assert.equal(peer.player.health,0);
   peer.player.lastDeath=Date.now()-3000;
   peer.send({t:'note',text:'TRY RESPAWN'});
  } else if(message.s===4) {
   assert.equal(message.kind,'respawn');original(peer,message);assert.equal(peer.player.health,100);
   peer.send({t:'note',text:'RESPAWNED'});
  } else if(message.s===5) {
   assert.equal(message.kind,'hurt');assert.equal(message.damage,30);
   const send=peer.send.bind(peer);
   peer.send=packet=>{if(packet.t!=='vitals')send(packet);};
   original(peer,message);assert.equal(peer.player.health,70);
   game.flushSync();peer.socket.destroy();
  } else throw Error('Uncertain health loss replayed or extra request emitted');
  return;
 }
 original(peer,message);
};
function stop(){for(const socket of sockets)socket.destroy();server.close();clearInterval(game.tick);clearInterval(game.projectileTimer);game.flushSync();}
server.listen(0,'127.0.0.1',()=>{
 child=spawn(process.argv[3],['http://127.0.0.1:'+server.address().port],{stdio:'inherit'});
 child.on('exit',code=>{
  try {assert.equal(code,0);assert.equal(joins,2);assert.equal(requests,5);assert.equal(firstPlayer.health,70);complete=true;
   console.log('PASS actual native health HTTP/WS: predicted40 + earlier server10 =50, hit43, stale HTTP suppressed, fatal/validated respawn, accepted30 with lost ACK reconnects at70 without replay');
  } catch(error){console.error(error);process.exitCode=1;} finally {stop();}
 });
});
const timer=setTimeout(()=>{if(!complete){child?.kill();stop();console.error('Health wire timed out');process.exitCode=1;}},60000);timer.unref();
