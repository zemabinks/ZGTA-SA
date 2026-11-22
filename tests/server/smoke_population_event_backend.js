// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Actual backend with actual current population tasks. Authored positions,
// straight graph, flat/clear geometry, inert transport and deterministic clock.
// Optional old backend isolates its stale spatial-query requirement failure.
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const root=path.resolve(__dirname,'../..'),backend=path.resolve(process.argv[2]||root);
const {Pedestrians}=require(path.join(root,'server/population/pedestrians'));
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-npc-event-backend-')),originalNow=Date.now;
let game,now=1700000000000,checks=0;const check=(value,text)=>{assert(value,text);checks++;};
try{
 Date.now=()=>now;
 for(const name of ['selfhost_backend.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js','player_placement.js'])fs.copyFileSync(path.join(backend,name),path.join(temporary,name));
 const local=path.join(temporary,'local-only/selfhost');fs.mkdirSync(local,{recursive:true});fs.writeFileSync(path.join(local,'client-catalog.json'),JSON.stringify({vehicles:[],homes:[]}));fs.writeFileSync(path.join(local,'weapon-catalog.json'),JSON.stringify({items:[],shops:[]}));
 game=require(path.join(temporary,'selfhost_backend'));
 let queried=[];const collision=require(path.join(temporary,'world_collision'));collision.lineOfSight=(_,to)=>{queried.push(to.slice());return true;};
 const account=game.ensurePlayer({headers:{cookie:''}},{setHeader(){}}),packets=[],binary=[];
 const peer={id:account.id,player:account.player,ready:false,lastSeen:now,closed:false,state:{walking:true,skin:7,x:1570,y:-2460,z:13.6,weapon:0},send:p=>packets.push(structuredClone(p)),sendBinary:p=>binary.push(Buffer.from(p))};
 game.peers.add(peer);
 peer.player.inventory={selected:0,weapons:{},lastShotAt:now-1000};
 for(const initial of [1573.99,1573.8]){
  now+=1000;peer.lastSeen=now;peer.lastHitAt=0;queried=[];binary.length=0;
  const epoch=now,points=[[initial,-2460,13.6],[initial+100,-2460,13.6]],graph={crc32:'00000000',point:id=>points[id].slice(),nearest:()=>({id:0,distance:0}),neighbors:id=>[{id:id^1,kind:0}]};
  game.population=new Pedestrians({graph,models:[7],random:()=>0,ground:()=>13.6,clear:()=>true,maximum:1,perObserver:1});
  if(!peer.ready)game.onMessage(peer,{t:'hi',nativeInventory:true,inventoryAck:1,npcProtocol:38});
  check(peer.ready&&peer.inventoryEnabled&&peer.populationEnabled,'Actual melee/population peer did not negotiate');
  game.publishPopulation(now,true);
  const actor=[...game.population.actors.values()][0];actor.speed=1.1;now=epoch+37;
  game.onMessage(peer,{t:'hit',w:0,c:peer.inventoryConnection,to:'p'+actor.id});
  const expected=initial+1.1*.037,inside=expected-1570<=4;
  check(inside?actor.health<100:actor.health===100,'Melee used an expired actor position at range boundary');
  check(Math.abs(actor.position[0]-expected)<1e-8,'Actual handler failed to settle movement at the hit clock');
  check(queried.some(p=>Math.abs(p[0]-expected)<1e-8),'Spatial clearance did not query the settled actor');
  check(actor.hitCounter===(inside?1:0),'Rejected hit mutated the task reaction counter');
  now=epoch+100;game.publishPopulation(now,true);
  const wanted=inside?initial+1.1*.1+2*.063*.063:initial+1.1*.1;
  check(Math.abs(actor.position[0]-wanted)<1e-8,'Handler event and following tick consumed contradictory intervals');
  const free=binary.filter(p=>p[0]===10).at(-1),at=(free[1]&128?3:2)+4;
  check(Math.abs(free.readInt32BE(at+5)/1000-wanted)<=.000501,'Actual backend published a stale or double-advanced position');
 }
 console.log('PASS backend NPC event boundaries '+checks+' checks; actual melee/task/packet owner with authored clock/geometry and inert transport; no sockets/rendering/retail claim');
}finally{
 Date.now=originalNow;
 if(game){clearInterval(game.tick);clearInterval(game.projectileTimer);clearTimeout(game.saveTimer);}
 fs.rmSync(temporary,{recursive:true,force:true});
}
