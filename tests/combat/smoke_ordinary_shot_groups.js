#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Actual independent backend handlers; authored catalog/geometry and explicit
// in-memory transports. No listening service, App or original assets.
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-shot-groups-')),originalNow=Date.now;
let game,now=1700000000000;
try {
 Date.now=()=>now;
 const root=path.resolve(__dirname,'../..'),local=path.join(temporary,'local-only');
 fs.mkdirSync(path.join(local,'selfhost'),{recursive:true});
 for(const name of ['selfhost_backend.js','player_placement.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js'])fs.copyFileSync(path.join(root,name),path.join(temporary,name));
 fs.writeFileSync(path.join(local,'selfhost/client-catalog.json'),JSON.stringify({vehicles:[],homes:[]}));
 fs.writeFileSync(path.join(local,'selfhost/weapon-catalog.json'),JSON.stringify({items:[
  {id:25,name:'Authored six-ray shotgun',ammo:20,capacity:5,price:0,slot:3,fire:'INSTANT_HIT',stats:{range:40,pellets:6,damage:4,loop:[0,9,0]}},
  {id:22,name:'Authored single-ray pistol',ammo:20,capacity:17,price:0,slot:2,fire:'INSTANT_HIT',stats:{range:40,pellets:1,damage:7,loop:[0,9,0]}},
  {id:34,name:'Authored scoped fixture',ammo:20,capacity:5,price:0,slot:6,fire:'INSTANT_HIT',stats:{range:300,pellets:1,damage:80,loop:[0,9,0]}}
 ],shops:[]}));
 const world=path.join(local,'site/game/world');fs.mkdirSync(world,{recursive:true});
 fs.writeFileSync(path.join(world,'index.json'),JSON.stringify({detail:{size:375,grid:16,origin:-3000,cells:[{cell:28},{cell:29},{cell:30}]},inside:{cells:[]}}));
 const vertices=[[1500,-2625,0],[1875,-2625,0],[1875,-2250,0],[1500,-2250,0]],indices=[0,1,2,0,2,3],mesh=Buffer.alloc(16+48+24);
 [0x324c4353,4,2,0].forEach((n,i)=>mesh.writeUInt32LE(n,i*4));vertices.forEach((p,i)=>p.forEach((n,j)=>mesh.writeFloatLE(n,16+i*12+j*4)));indices.forEach((n,i)=>mesh.writeUInt32LE(n,64+i*4));fs.writeFileSync(path.join(world,'c28.col.bin'),mesh);
 for(const offset of [1,2]){
  const next=Buffer.from(mesh);vertices.forEach((p,i)=>next.writeFloatLE(p[0]+375*offset,16+i*12));fs.writeFileSync(path.join(world,`c${28+offset}.col.bin`),next);
 }
 game=require(path.join(temporary,'selfhost_backend.js'));
 function peer(x,y=-2460,negotiate=true){
  const account=game.ensurePlayer({headers:{cookie:''}},{setHeader(){}}),packets=[];
  const p={id:account.id,player:account.player,ready:false,lastSeen:now,closed:false,state:{walking:true,x,y,z:13.6},packets,send:m=>packets.push(structuredClone(m))};
  game.peers.add(p);game.onMessage(p,{t:'hi',nativeInventory:true,inventoryAck:1,...(negotiate?{ordinaryShots:1}:{})});return p;
 }
 const a=peer(1570),b=peer(1574),c=peer(1574,-2458),legacy=peer(1571,-2465,false);
 assert.equal(a.packets.find(p=>p.t==='hello').ordinaryShots,1,'Backend did not negotiate one-emission grouped ordinary shots');
 assert.equal(legacy.packets.find(p=>p.t==='hello').ordinaryShots,undefined,'Old clients received unrequested grouped authority');
 a.player.inventory={selected:25,weapons:{25:{clip:5,rest:20},22:{clip:17,rest:0},34:{clip:5,rest:0}},lastShotAt:now-300};
 const origin=[1570,-2460,14.95],group=(p,n=1)=>({o:origin,h:[p.state.x,p.state.y,14.7],ht:1,id:String(p.player.number),n,bp:3});
 const inventory=p=>p.packets.filter(m=>m.t==='inventory').at(-1);
 let sequence=0;
 function shoot(rays,extra={}) {
  now+=500;for(const p of [a,b,c,legacy])p.lastSeen=now;
  game.onMessage(a,{t:'shot',w:25,c:a.inventoryConnection,s:++sequence,o:origin,h:group(b).h,rays,...extra});return inventory(a);
 }
 const healthB=b.player.health,healthC=c.player.health,revision=a.player.inventory.revision||0;
 let result=shoot([group(b,3),group(c,2),{o:origin,h:[1576,-2460,14.7],ht:0,n:1}]);
 assert.equal(result.result.accepted,true);assert.equal(a.player.inventory.weapons[25].clip,4,'Pellets spent more than one cartridge');
 assert.equal(b.player.health,healthB-12);assert.equal(c.player.health,healthC-8,'Second independently hit target received no pellet damage');
 assert.equal(b.packets.filter(p=>p.t==='hit').length,1,'One target was damaged more than once per marker');
 assert.equal(c.packets.filter(p=>p.t==='hit').length,1);
 assert.deepEqual(a.packets.filter(p=>p.t==='struck').map(p=>[p.id,p.bp,p.s,p.c]),[
  [String(b.player.number),3,1,a.inventoryConnection],[String(c.player.number),3,1,a.inventoryConnection]],'Shooter lacked accepted per-target strike receipts');
 const after=[b.player.health,c.player.health];
 game.onMessage(a,{t:'hit',w:25,c:a.inventoryConnection,s:sequence,to:String(b.player.number)});
 game.onMessage(a,{t:'hit',w:25,c:a.inventoryConnection,s:sequence,to:String(c.player.number)});
 assert.deepEqual([b.player.health,c.player.health],after,'A later hit reused a batch authority receipt');
 game.onMessage(a,{t:'shot',w:25,c:a.inventoryConnection,s:sequence,o:origin,h:group(b).h,rays:[group(b,6)]});
 assert.equal(a.player.inventory.weapons[25].clip,4,'Replay spent ammunition');assert.deepEqual([b.player.health,c.player.health],after,'Replay changed health');
 for(const bad of [[group(b,7)],[group(b,3),group(b,2)],[group(b,0)],[group(b,1.5)],[{...group(b),o:[5000,0,0]}],[{...group(b),h:[Infinity,0,0]}],[],Array.from({length:101},()=>group(b))]) {
  const clip=a.player.inventory.weapons[25].clip;result=shoot(bad);assert.equal(result.result.accepted,false);assert.equal(a.player.inventory.weapons[25].clip,clip,'Malformed batch spent ammunition');assert.deepEqual([b.player.health,c.player.health],after,'Malformed batch applied partial damage');
 }
 result=shoot([group(b,2)],{w:22});assert.equal(result.result.accepted,false,'Pistol borrowed a shotgun pellet budget');
 // Claims are settled at the event. A protected/different-world target must
 // not turn into a fresh hit after its state changes later in the same2s.
 b.player.passive=true;result=shoot([group(b),group(c)]);assert.equal(result.result.accepted,true);
 const protectedHealth=b.player.health;assert.equal(protectedHealth,after[0]);b.player.passive=false;
 game.onMessage(a,{t:'hit',w:25,c:a.inventoryConnection,s:sequence,to:String(b.player.number)});
 assert.equal(b.player.health,protectedHealth,'Protected claim became a delayed hit');
 c.player.insideHome='authored-other-world';const otherWorldHealth=c.player.health;
 result=shoot([group(b),group(c)]);assert.equal(result.result.accepted,true);assert.equal(c.player.health,otherWorldHealth);
 c.player.insideHome=null;game.onMessage(a,{t:'hit',w:25,c:a.inventoryConnection,s:sequence,to:String(c.player.number)});
 assert.equal(c.player.health,otherWorldHealth,'Other-world claim became a delayed hit');
 c.player.armour=4;result=shoot([group(c)]);assert.equal(result.result.accepted,true);
 assert.equal(c.player.armour,0);assert.equal(c.player.health,otherWorldHealth,'Armour-only loss changed health');
 const priorNonce=a.inventoryConnection;game.onMessage(a,{t:'hi',nativeInventory:false,inventoryAck:0,ordinaryShots:0});assert.equal(a.inventoryConnection,priorNonce);assert.equal(a.ordinaryShotGroupsEnabled,true,'Duplicate hello downgraded negotiated authority');
 legacy.player.inventory={selected:25,weapons:{25:{clip:5,rest:0}}};
 game.onMessage(legacy,{t:'shot',w:25,c:legacy.inventoryConnection,s:1,o:[1571,-2465,14.95],h:group(b).h,rays:[group(b,2)]});
 assert.equal(inventory(legacy).result.accepted,false,'Unnegotiated extension silently changed a legacy shot');assert.equal(legacy.player.inventory.weapons[25].clip,5);
 assert.equal(a.packets.filter(p=>p.t==='inventory'&&p.result?.accepted===true).length,4,'A single emission emitted multiple successful inventory settlements');
 assert.equal(a.packets.filter(p=>p.t==='struck').length,5,'Protected/rejected claim fabricated feedback or armour loss lacked it');
 a.player.inventory.selected=34;
 const scoped={o:origin,h:[2370,-2460,14.95],ht:0,n:1};
 result=shoot([scoped],{w:34,h:scoped.h});assert.equal(result.result.accepted,true,'Native800m scoped emission was rejected by the ordinary server range policy');
 assert.equal(a.player.inventory.weapons[34].clip,4,'A valid scoped miss did not spend exactly one cartridge');
 b.state.x=2370;const distantHealth=b.player.health;
 result=shoot([group(b)],{w:34,h:group(b).h});assert.equal(result.result.accepted,true);assert.equal(b.player.health,distantHealth-80,'Scoped hit did not reach an800m target over complete authored collision cells');
 a.player.inventory.selected=22;const pistolClip=a.player.inventory.weapons[22].clip;
 result=shoot([scoped],{w:22,h:scoped.h});assert.equal(result.result.accepted,false);assert.equal(a.player.inventory.weapons[22].clip,pistolClip,'Pistol borrowed scoped presentation range');
 b.state.x=1620;const shortRangeHealth=b.player.health,feedback=a.packets.filter(p=>p.t==='struck').length;
 result=shoot([group(b)],{w:22,h:group(b).h});assert.equal(result.result.accepted,true,'Camera-compensated presentation was rejected');
 assert.equal(b.player.health,shortRangeHealth,'Presentation margin granted an out-of-range damaging hit');
 assert.equal(a.packets.filter(p=>p.t==='struck').length,feedback,'Out-of-range presentation fabricated accepted strike feedback');
 b.state.x=1570;b.state.z=63.6;
 const vertical={...group(b),h:[1570,-2460,64.7]},beforeVertical=b.player.health;
 result=shoot([vertical],{w:22,h:vertical.h});assert.equal(result.result.accepted,true);
 assert.equal(b.player.health,beforeVertical,'Vertical camera-compensated trace bypassed the ordinary3D damage distance');
 assert.equal(a.packets.filter(p=>p.t==='struck').length,feedback,'Out-of-range vertical trace fabricated accepted strike feedback');
 console.log('PASS actual grouped-shot backend: one cartridge/ACK, independent targets, per-pellet catalog damage, scoped range, separately bounded presentation/damage, replay/overbudget/invalid atomicity and opt-in compatibility; no App, hardware or retail claim');
} finally {
 Date.now=originalNow;
 if(game){clearInterval(game.tick);clearInterval(game.projectileTimer);clearTimeout(game.saveTimer);}
 fs.rmSync(temporary,{recursive:true,force:true});
}
