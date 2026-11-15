#!/usr/bin/env node
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const {create}=require('./weapon_inventory');
const document=JSON.parse(fs.readFileSync(path.join(__dirname,'local-only/site/game/native/foot-animation.json'),'utf8'));
const extracted=JSON.parse(fs.readFileSync(path.join(__dirname,'local-only/selfhost/weapon-catalog.json'),'utf8'));
const synthetic=id=>({id,name:'Cadence fixture',ammo:500,capacity:500,price:0,slot:id,fire:'INSTANT_HIT',stats:{loop:[0,3,0]}});
const catalog={items:[22,28,37,41,42].map(synthetic),shops:[]};
const twin=structuredClone(document.weapons.find(row=>row.id===22));twin.twin=true;
const store=create(catalog,{timingDefinitions:[...document.weapons.filter(row=>row.id!==22),twin]});
const player=id=>({health:100,inventory:{selected:id,weapons:{[id]:{clip:500,rest:0}}}});
const start=1_700_000_000_000;
assert.equal(store.cadence(28).intervalMs,document.weapons.find(row=>row.id===28).loop.every*1000);
for(const id of [37,41,42]) {
  assert.equal(store.cadence(id).intervalMs,20);
  const p=player(id);
  const capacity=store.cadence(id).capacity;assert.equal(capacity,5);
  for(let n=0;n<capacity;n++)assert.equal(store.acceptShot(p,id,start,{sequence:n}).ok,true,'Initial bounded stream credit');
  for(let frame=1;frame<101;frame++)assert.equal(store.acceptShot(p,id,start+frame*20,{sequence:capacity+frame-1}).ok,true,'20ms stream emission');
  assert.equal(p.inventory.weapons[id].clip,500-capacity-100);
  assert.equal(store.acceptShot(p,id,start+2000,{sequence:capacity+99}).ok,false,'Duplicate sequence accepted');
  assert.equal(store.acceptShot(p,id,start+2000,{sequence:capacity+100}).ok,false,'No time credit remained');
}
{
  const p=player(22),half=store.cadence(22).intervalMs;
  assert.equal(half,twin.loop.every*500);
  assert(store.acceptShot(p,22,start,{sequence:1}).ok);
  assert(store.acceptShot(p,22,start+half,{sequence:2}).ok,'Twin left round was blocked');
  assert(!store.acceptShot(p,22,start+half,{sequence:2}).ok);
  assert.equal(p.inventory.weapons[22].clip,498);
}
for(const [id,capacity]of[[28,2],[41,5]]) {
  const p=player(id),gap=store.cadence(id).intervalMs;
  assert(store.acceptShot(p,id,start,{sequence:1}).ok);
  for(let n=0;n<capacity;n++)assert(store.acceptShot(p,id,start+gap*10,{sequence:n+2}).ok,'Bounded catch-up rejected');
  assert(!store.acceptShot(p,id,start+gap*10,{sequence:capacity+2}).ok,'Catch-up bound exceeded');
  assert(store.acceptShot(p,id,start+gap*11,{sequence:capacity+2}).ok,'Rejected sequence was prematurely committed');
}
{
  const p=player(28);p.inventory.weapons[22]={clip:10,rest:0};
  assert(store.acceptShot(p,28,start,{sequence:1}).ok);
  p.inventory.selected=22;
  assert(!store.acceptShot(p,22,start,{sequence:2}).ok,'Weapon switch granted free credit');
  assert(!store.acceptShot(p,28,start+1000,{sequence:3}).ok,'Unselected weapon accepted');
  p.inventory.reload={weapon:22,until:start+2000};
  assert(!store.acceptShot(p,22,start+1000,{sequence:4}).ok,'Reload allowed shooting');
  p.inventory.reload=null;p.inventory.weapons[22].clip=0;
  assert(!store.acceptShot(p,22,start+1000,{sequence:5}).ok,'Empty magazine accepted');
}
{
  const p=player(28),oldPeer={},newPeer={};
  assert(store.acceptShot(p,28,start,{sequence:1,sequenceScope:oldPeer}).ok);
  assert(store.acceptShot(p,28,start+120,{sequence:1,sequenceScope:newPeer}).ok,'Reconnect inherited old socket sequence floor');
  assert(!store.acceptShot(p,28,start+240,{sequence:1,sequenceScope:oldPeer}).ok,'Old socket replay accepted');
}
// Exercise actual backend acceptance/hit replay on isolated saved state. The
// collision scene is the owner's real local archive, with no service started.
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-cadence-')),originalNow=Date.now;
let game,now=start;
try {
  Date.now=()=>now;
  const local=path.join(temporary,'local-only');fs.mkdirSync(path.join(local,'selfhost'),{recursive:true});
  fs.symlinkSync(path.join(__dirname,'local-only/site'),path.join(local,'site'));
  for(const name of ['selfhost_backend.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js'])fs.copyFileSync(path.join(__dirname,name),path.join(temporary,name));
  fs.copyFileSync(path.join(__dirname,'local-only/selfhost/client-catalog.json'),path.join(local,'selfhost/client-catalog.json'));
  fs.writeFileSync(path.join(local,'selfhost/weapon-catalog.json'),JSON.stringify(extracted));
  game=require(path.join(temporary,'selfhost_backend.js'));
  function peer(){const {player}=game.ensurePlayer({headers:{cookie:''}},{setHeader(){}}),packets=[];
    const peer={player,ready:true,inventoryEnabled:true,lastSeen:now,state:{walking:true,x:1570,y:-2460,z:13.6},send:p=>packets.push(p)};
    game.peers.add(peer);return peer;}
  const a=peer(),b=peer();b.state.x+=4;b.player.health=1000;
  // Preserve the saved-shot cooldown path here; fresh bursts have their own
  // actual-backend and transport-boundary checks.
  a.player.inventory={selected:28,weapons:{28:{clip:50,rest:0}},lastShotAt:now-document.weapons.find(row=>row.id===28).loop.every*1000};
  const shot=s=>({t:'shot',w:28,s,o:[1570,-2460,14.95],h:[1574,-2460,14.75]});
  const hit=s=>({t:'hit',w:28,s,to:String(b.player.number)});
  game.handleShot(a,shot(1));game.handleHit(a,hit(1));const health=b.player.health;
  assert(health<1000);assert.equal(a.player.inventory.weapons[28].clip,49);
  game.handleHit(a,hit(1));game.handleShot(a,shot(1));
  assert.equal(b.player.health,health);assert.equal(a.player.inventory.weapons[28].clip,49);
  now+=120;game.handleShot(a,shot(2));game.handleHit(a,hit(2));assert(b.player.health<health);
  now+=20;game.handleShot(a,shot(3));game.handleHit(a,hit(3));assert.equal(a.player.inventory.weapons[28].clip,48);
  now+=100;game.handleShot(a,shot(3));game.handleHit(a,hit(3));assert.equal(a.player.inventory.weapons[28].clip,47);
  now+=1200;
  game.handleShot(a,shot(4));game.handleShot(a,shot(5));game.handleShot(a,shot(6));
  assert.equal(a.player.inventory.weapons[28].clip,45,'Backend catch-up credit was unbounded or global70ms dropped it');
  const before=b.player.health;game.handleHit(a,hit(4));game.handleHit(a,hit(5));game.handleHit(a,hit(6));
  assert.equal(before-b.player.health,24,'Per-hit90ms gate dropped a legitimate catch-up shot, or rejected shot gained a hit');
  const armedHealth=b.player.health;
  game.handleHit(a,{t:'hit',w:0,to:String(b.player.number)});
  assert.equal(b.player.health,armedHealth,'Gun holder spoofed an unselected fist attack');
  const fresh=peer();fresh.player.inventory={selected:28,weapons:{28:{clip:50,rest:0}}};
  game.handleShot(fresh,shot(1));game.handleShot(fresh,shot(2));game.handleShot(fresh,shot(3));
  assert.equal(fresh.player.inventory.weapons[28].clip,48,'Actual backend did not enforce the fresh two-event burst');
  game.flushSync();
  console.log('PASS: canonical fast-gun/twin/20ms stream timing, bounded2/5 transport credit, saved cooldown/replay/empty/reload/switch guards, actual server one-hit-per-accepted-sequence');
} finally {
  Date.now=originalNow;
  if(game){clearInterval(game.tick);clearInterval(game.projectileTimer);game.flushSync();}
  fs.rmSync(temporary,{recursive:true,force:true});
}
