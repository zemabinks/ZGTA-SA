#!/usr/bin/env node
'use strict';
// Actual backend state/command handlers, synthetic transports, no archive or
// listening service. No original game assets/catalog data are included.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-jetpack-drop-'));
let game,restored;
try {
 fs.mkdirSync(path.join(temporary,'local-only/selfhost'),{recursive:true});
 for(const name of ['selfhost_backend.js','player_placement.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js'])fs.copyFileSync(path.join(__dirname,name),path.join(temporary,name));
 game=require(path.join(temporary,'selfhost_backend.js'));
 function peer(owner=game,id=null){
  const account=owner.ensurePlayer({headers:{cookie:id?'zgta_local='+id:''}},{setHeader(){}}),packets=[];
  const value={id:account.id,player:account.player,ready:true,lastSeen:Date.now(),state:{walking:true,driving:false,air:false,act:60,x:1480,y:-1738,z:13},send:p=>packets.push(structuredClone(p)),packets};
  owner.peers.add(value);owner.onMessage(value,{t:'hi',nativeInventory:true});return value;
 }
 const a=peer(),b=peer();game.say(a,'/parachute');game.say(a,'/jetpack');
 assert.deepEqual(a.player.flightGear,{parachute:true,jetpack:true});
 assert.deepEqual(b.player.flightGear,{parachute:false,jetpack:false});
 const otherPackets=b.packets.length;
 for(const [label,change]of[
  ['air',{air:true}],['numeric air',{air:1}],['fractional air',{air:0.5}],['driving',{driving:true}],['not walking',{walking:false}],
  ['hover action61',{act:61}],['thrust action62',{act:62}],['burn-bit flight',{act:62|64}],
  ['parachute',{act:55}],['swimming',{act:14}],['stale position',{lastSeen:Date.now()-11000}],['dead',{health:0}],
 ]){
  a.state={walking:true,driving:false,air:false,act:60,x:1480,y:-1738,z:13};a.player.health=100;a.lastSeen=Date.now();
  if(change.health!==undefined)a.player.health=change.health;
  else if(change.lastSeen!==undefined)a.lastSeen=change.lastSeen;
  else Object.assign(a.state,change);
  const before=a.packets.length;game.say(a,'/dropjetpack');
  assert.deepEqual(a.player.flightGear,{parachute:true,jetpack:true},label+' allowed removing flight gear');
  assert(!a.packets.slice(before).some(p=>p.t==='staff'||p.t==='flightgear'),label+' published a false removal');
 }
 a.player.health=100;a.lastSeen=Date.now();a.state={walking:true,driving:false,air:false,act:60,x:1480,y:-1738,z:13};
 const before=a.packets.length;game.say(a,'/dropjetpack');
 assert.deepEqual(a.player.flightGear,{parachute:true,jetpack:false});
 assert(a.packets.slice(before).some(p=>p.t==='staff'&&p.jetpack===false),'Browser did not receive original false jetpack control');
 assert(a.packets.slice(before).some(p=>p.t==='flightgear'&&p.jetpack===false&&p.parachute===true),'Native gear update lost the parachute');
 assert.equal(b.packets.length,otherPackets,'Self-only drop sent another peer a grant/removal');
 assert.deepEqual(b.player.flightGear,{parachute:false,jetpack:false});
 game.say(a,'/dropjetpack');assert.deepEqual(a.player.flightGear,{parachute:true,jetpack:false},'Repeated removal was not idempotent');
 game.flushSync();
 const saved=JSON.parse(fs.readFileSync(path.join(temporary,'local-only/selfhost/players.json')));
 assert.deepEqual(saved.players[a.id].flightGear,{parachute:true,jetpack:false});
 clearInterval(game.tick);clearInterval(game.projectileTimer);
 restored=new game.constructor();const joined=peer(restored,a.id);
 assert.deepEqual(joined.player.flightGear,{parachute:true,jetpack:false},'Rejoining restored the dropped jetpack');
 assert(joined.packets.some(p=>p.t==='flightgear'&&p.jetpack===false&&p.parachute===true));
 assert(!joined.packets.some(p=>p.t==='staff'&&p.jetpack===true));
 game.say(b,'/jetpack');assert.deepEqual(b.player.flightGear,{parachute:false,jetpack:true});
 assert.deepEqual(a.player.flightGear,{parachute:true,jetpack:false},'Another peer equip changed the dropped state');
 console.log('PASS: self-only equip/drop, airborne/driving/flight/dead/stale rejection, browser/native removal packets, parachute preservation, idempotence and rejoin persistence (no archive)');
} finally {
 for(const item of [game,restored])if(item){clearInterval(item.tick);clearInterval(item.projectileTimer);}
 fs.rmSync(temporary,{recursive:true,force:true});
}
