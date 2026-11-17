#!/usr/bin/env node
'use strict';
// Actual independent message/row handlers with synthetic browser/native peers.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-armour-sync-'));let game,checks=0;
function check(value,message){checks++;assert(value,message)}
try{
 const data=path.join(temporary,'local-only/selfhost');fs.mkdirSync(data,{recursive:true});
 for(const n of ['selfhost_backend.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js'])fs.copyFileSync(path.join(__dirname,n),path.join(temporary,n));
 fs.writeFileSync(path.join(data,'client-catalog.json'),JSON.stringify({vehicles:[],homes:[]}));
 fs.writeFileSync(path.join(data,'weapon-catalog.json'),JSON.stringify({items:[],shops:[]}));
 game=require(path.join(temporary,'selfhost_backend'));
 function peer(native){
  const {player}=game.ensurePlayer({headers:{cookie:''}},{setHeader(){}});player.armour=50;
  const peer={player,ready:false,state:null,lastSeen:Date.now(),send(){}};game.peers.add(peer);
  game.onMessage(peer,{t:'hi',...(native?{nativeInventory:true,inventoryAck:1,healthAck:1}:{})});return peer;
 }
 function move(peer,armour,extra={}){game.onMessage(peer,{t:'me',walking:true,skin:7,x:1570,y:-2460,z:13.6,health:peer.player.health,armour,...extra})}
 const browser=peer(false),native=peer(true);
 move(browser,35);check(browser.player.health===100&&browser.player.armour===35,'Browser environmental loss was ignored');
 move(browser,50);check(browser.player.armour===35,'Stale browser frame restored consumed armour');
 for(const bad of [true,false,null,'0',NaN,Infinity,-1,101]){move(browser,bad);check(browser.player.armour===35,'Malformed browser armour changed authority')}
 const car={id:'armour-fixture',row:['armour-fixture','Synthetic','420',1570,-2460,13.6,0,0,0,1000,'',null]};game.vehicles.set(car.id,car);
 game.onMessage(browser,{t:'enter',v:car.id});check(game.vehicleClaim(car)?.peer===browser,'Driving armour fixture did not use normal entry');
 move(browser,20,{walking:false,driving:true,vehicle:car.id,car:'420',life:90});check(browser.player.armour===20&&browser.player.health===90,'Driving armour/health namespaces mixed');
 move(browser,35);check(game.row(browser)[30]===20,'Observer row used stale reported armour');
 move(native,0,{health:0});check(native.player.health===100&&native.player.armour===50,'Native frame bypassed acknowledged vitals');
 check(game.row(native)[30]===50,'Native observer row used unaccepted predicted/spoofed armour');
 game.onMessage(native,{t:'selfHealth',c:native.inventoryConnection,s:1,kind:'impact',damage:20});
 check(native.player.health===100&&native.player.armour===30,'Native crash did not own armour loss');
 move(native,0);check(native.player.armour===30&&game.row(native)[30]===30,'Native position reapplied an acknowledged armour loss');
 move(browser,0,{health:0});check(browser.player.armour===0&&browser.player.health===0&&browser.player.deaths===1,'Browser fatal environment state was lost');
 move(browser,0,{health:0});check(browser.player.deaths===1,'Browser fatal replay repeated death');
 console.log(`PASS browser/native armour ownership: ${checks} actual handler checks; legacy decrease-only, native ACK ownership and authoritative observer rows`);
}finally{if(game){clearInterval(game.tick);clearInterval(game.projectileTimer);game.flushSync()}fs.rmSync(temporary,{recursive:true,force:true})}
