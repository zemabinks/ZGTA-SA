#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Actual independent backend handlers and public snapshots. All accounts,
// geometry and vehicles are authored; no original resources or listening app.
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const ROOT=path.resolve(__dirname,'../..'),SOURCE=process.argv[2]?path.resolve(process.argv[2]):ROOT;
const fixture=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-condition-'));
let game,checks=0;
const equal=(a,b,why)=>{checks++;assert.deepEqual(a,b,why);};
try{
 for(const name of ['selfhost_backend.js','player_placement.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js'])
  fs.copyFileSync(path.join(SOURCE,name),path.join(fixture,name));
 const local=path.join(fixture,'local-only');fs.mkdirSync(path.join(local,'selfhost'),{recursive:true});
 fs.mkdirSync(path.join(local,'site/game/world'),{recursive:true});
 fs.writeFileSync(path.join(local,'selfhost/client-catalog.json'),'{"vehicles":[],"homes":[]}');
 fs.writeFileSync(path.join(local,'selfhost/weapon-catalog.json'),'{"items":[],"shops":[]}');
 fs.writeFileSync(path.join(local,'site/game/world/index.json'),'{"water":[],"tiles":[]}');
 game=require(path.join(fixture,'selfhost_backend.js'));clearInterval(game.tick);clearInterval(game.projectileTimer);
 function actor(native){
  const {player}=game.ensurePlayer({headers:{cookie:''}},{setHeader(){}}),packets=[];
  const peer={player,ready:false,lastSeen:Date.now(),state:null,send:p=>packets.push(structuredClone(p))};
  game.peers.add(peer);game.onMessage(peer,{t:'hi',...(native?{nativeInventory:true,inventoryAck:1}:{})});
  game.onMessage(peer,foot());return{peer,packets};
 }
 function foot(extra={}){return{t:'me',walking:true,skin:7,x:100,y:100,z:20,health:100,armour:0,...extra};}
 function makeCar(id){const car={id,row:[id,'Authored','420.4.5.0.',100,100,20,0,0,0,1000,'',null]};game.vehicles.set(id,car);return car;}
 function drive(car,extra={}){return{t:'me',driving:true,skin:7,car:car.row[2],vehicle:car.id,x:100,y:100,z:20,health:1000,life:100,...extra};}
 const observer=actor(false),damage='3434012122110101201';
 for(const native of [false,true]){
  const a=actor(native),car=makeCar('condition-'+native);
  game.onMessage(a.peer,{t:'enter',v:car.id});
  equal(a.packets.filter(p=>p.t==='enter').at(-1)?.ok,true,'Normal nearby entry was denied');
  game.onMessage(a.peer,drive(car,{health:645,damage}));
  equal(car.row.slice(9,11),[645,damage],'Initial accepted damage was lost');
  game.onMessage(a.peer,drive(car,{health:900,damage:''}));
  equal(car.row.slice(9,11),[645,damage],'A stale report repaired the registered hull');
  equal(game.row(a.peer).slice(18,20),[645,damage],'Driving publication contradicts authoritative registered condition');
  const all=game.fullState(observer.peer);
  equal(all.cars.find(row=>row[0]===String(a.peer.player.number)).slice(18,20),[645,damage],'Late baseline resurrected stale driving condition');
  equal(all.vehicles.find(row=>row[0]===car.id).slice(9,11),[645,damage],'Late baseline registry disagrees with driving actor');
  for(const hp of [-1,1001,Infinity,NaN,'500',null]){
   game.onMessage(a.peer,drive(car,{health:hp}));
   equal(car.row[9],645,'An invalid condition changed registered health');
   equal(game.row(a.peer)[18],645,'Invalid condition leaked into driving publication');
  }
  // Explicit exit fixes the body snapshot while a final drive frame can still
  // arrive. It must not revive either the driving appearance or final stand-in.
  game.onMessage(a.peer,{t:'exit',v:car.id,x:101,y:100,z:20,h:0,p:0,r:0,hp:600,d:damage});
  game.onMessage(a.peer,drive(car,{health:999,damage:''}));
  equal(game.row(a.peer).slice(18,20),[645,damage],'Queued drive frame bypassed the committed condition');
  game.onMessage(a.peer,foot({vehicle:car.id,car:car.row[2],parked:{x:101,y:100,z:20,heading:0,health:900,damage:''}}));
  equal(car.row.slice(9,11),[645,damage],'Stale parked report repaired registry');
  equal(game.row(a.peer)[33].slice(7,9),[645,damage],'Parked stand-in contradicts its authoritative hull');
  equal(game.row(a.peer)[35],car.id,'Authorized parked identity disappeared');
  const laterDamage='0000000000000000001';
  game.onMessage(observer.peer,{t:'vmove',v:car.id,x:102,y:100,z:20,h:0,p:0,r:0,hp:500,d:laterDamage});
  equal(car.row.slice(9,11),[500,laterDamage],'Genuine later unattended damage was not accepted');
  equal(game.row(a.peer)[33].slice(7,9),[500,laterDamage],'A retained parked report resurrects an older vehicle condition');
  equal(game.row(a.peer)[33].slice(1,4),[102,100,20],'A retained parked report resurrects an older body position');
  game.onMessage(a.peer,foot());equal(game.row(a.peer)[33],null,'Ordinary foot reports retained a parked stand-in');
  game.onMessage(a.peer,{t:'vmove',v:car.id,x:102,y:100,z:20,h:0,p:0,r:0,hp:900,d:''});
  equal(car.row.slice(9,11),[500,laterDamage],'Unattended motion cleared accepted vehicle damage');
  equal(car.row[3],102,'Valid unattended body motion was blocked by condition reconciliation');
  // A denied outsider must not acquire publication rights from the car ID.
  game.onMessage(observer.peer,foot({vehicle:car.id,car:car.row[2],parked:{x:100,y:100,z:20,health:1000,damage:''}}));
  equal(game.row(observer.peer)[33],null,'Denied explicit-ID report emitted a parked hull');
  equal(game.row(observer.peer)[35],null,'Denied explicit-ID report emitted a vehicle attachment');
  const long='x'.repeat(600),other=makeCar('bounded-'+native);
  game.onMessage(a.peer,foot());game.onMessage(a.peer,{t:'enter',v:other.id});
  equal(a.packets.filter(p=>p.t==='enter'&&p.v===other.id).at(-1)?.ok,true,'Normal entry for bounded condition denied');
  game.onMessage(a.peer,drive(other,{health:550,damage:long}));
  equal(other.row.slice(9,11),[1000,''],'Malformed drive report changed registered condition');
  equal(a.peer.state.walking,true,'Malformed drive report became the current actor state');
  const bounded=long.slice(0,512);other.row[9]=550;other.row[10]=bounded;
  game.onMessage(a.peer,foot({vehicle:other.id,car:other.row[2],parked:{x:100,y:100,z:20,heading:0,health:900,damage:''}}));
  equal(game.row(a.peer)[33].slice(7,9),[550,bounded],'Pending get-in stand-in bypassed authoritative condition');
  if(native){
   equal(game.vehicleClaim(other),null,'Native pending get-in cancellation retained its reservation');
   game.onMessage(a.peer,{t:'enter',v:other.id});
  }else equal(game.vehicleClaim(other)?.driving,false,'Browser stand-in incorrectly cancelled its get-in reservation');
  game.onMessage(a.peer,drive(other,{health:550,damage:bounded}));
  equal(other.row[10],bounded,'Valid bounded condition was lost');
  equal(game.row(a.peer).slice(18,20),[550,long.slice(0,512)],'Bounded condition differs between registry and actor');
  game.onMessage(a.peer,foot({vehicle:other.id,car:other.row[2],parked:{x:100,y:100,z:20,health:550,damage:bounded}}));
  equal(game.row(a.peer)[33].slice(7,9),[550,long.slice(0,512)],'Bounded parked condition differs from registry');
  game.onMessage(observer.peer,{t:'enter',v:other.id});game.onMessage(observer.peer,drive(other,{health:550,damage:bounded}));
  equal(game.vehicleDriver(other),observer.peer,'Following driver was not admitted');
  equal(game.row(a.peer)[33],null,'Following driver retained an older parked stand-in');
  equal(game.row(a.peer)[35],null,'Following driver retained an older parked attachment');
  game.onMessage(observer.peer,foot({vehicle:other.id,car:other.row[2],parked:{x:100,y:100,z:20,health:550,damage:bounded}}));
  equal(game.row(a.peer)[33],null,'Following driver exit resurrected an older parked stand-in');
  const replacement={id:other.id,row:[...other.row]};replacement.row[9]=1000;replacement.row[10]='new';game.vehicles.set(other.id,replacement);
  equal(game.row(a.peer)[33],null,'Reused wire ID retained a previous-lifetime parked stand-in');
  equal(game.row(a.peer)[35],null,'Reused wire ID retained a previous-lifetime parked attachment');
 }
 // Legacy freeplay omits a registered ID. Its owner-local condition has no
 // authoritative registry and must retain the original wire semantics.
 const free=actor(false);
 game.onMessage(free.peer,drive(makeCar('unused'),{vehicle:undefined,health:777,damage:'free'}));
 equal(game.row(free.peer).slice(18,20),[777,'free'],'Unbound freeplay condition was replaced');
 game.onMessage(free.peer,foot({car:'420',parked:{x:100,y:100,z:20,heading:0,health:700,damage:'local'}}));
 equal(game.row(free.peer)[33].slice(7,9),[700,'local'],'Unbound freeplay parked semantics changed');
 // The condition-retention rule must not block the real paid repair owner.
 const owner=actor(false),account=owner.peer.player;account.cash=10000;account.cars=[410];
 account.garage=[{health:550,damage,position:[100,100,20,0],active:true,work:0}];
 const beforeRepair=game.addOwnedVehicle(account,0),cash=account.cash;
 game.action(account,'car.repair',{slot:0});const repaired=game.ownedVehicle(account,0);
 equal(account.cash<cash,true,'Actual paid repair did not charge its owner');
 equal(repaired.id!==beforeRepair.id,true,'Actual repair reused the previous vehicle lifetime');
 equal(repaired.row.slice(9,11),[1000,''],'Actual authorized repair failed to reset condition');
 equal([account.garage[0].health,account.garage[0].damage],[1000,''],'Authorized repair lost saved condition');
 game.onMessage(owner.peer,{t:'vmove',v:beforeRepair.id,x:100,y:100,z:20,h:0,p:0,r:0,hp:500,d:damage});
 equal(repaired.row.slice(9,11),[1000,''],'Old unoccupied lifetime modified repaired replacement');
 console.log(`PASS ${checks} actual backend condition-publication checks: registry/driver/parked/baseline agreement, malformed health, bounded damage, queued exit, native/legacy and unbound freeplay`);
}finally{
 if(game){clearInterval(game.tick);clearInterval(game.projectileTimer);clearTimeout(game.saveTimer);}
 fs.rmSync(fixture,{recursive:true,force:true});
}
