#!/usr/bin/env node
'use strict';
// Actual independent-server handlers and SCL2 visibility with synthetic data.
// No archived assets, original scripts, production saves or server are used.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-melee-server-'));
const originalNow=Date.now;let game,now=1700000000000;
try {
  Date.now=()=>now;
  const local=path.join(temporary,'local-only'),worldPath=path.join(local,'site/game/world');
  fs.mkdirSync(path.join(local,'selfhost'),{recursive:true});fs.mkdirSync(worldPath,{recursive:true});
  for(const file of ['selfhost_backend.js','player_placement.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js'])
    fs.copyFileSync(path.join(__dirname,file),path.join(temporary,file));
  fs.writeFileSync(path.join(local,'selfhost/client-catalog.json'),JSON.stringify({vehicles:[],homes:[]}));
  fs.mkdirSync(path.join(local,'native'),{recursive:true});
  fs.writeFileSync(path.join(local,'native/melee.json'),JSON.stringify({weapons:[{id:0,blocks:true},{id:2,blocks:true},{id:9,blocks:false}]}));
  fs.writeFileSync(path.join(local,'selfhost/weapon-catalog.json'),JSON.stringify({items:[{
    id:2,name:'Synthetic owned melee',ammo:1,capacity:1,price:0,slot:1},{id:22,name:'Synthetic gun',ammo:1,capacity:1,price:0,slot:2}],shops:[]}));
  fs.writeFileSync(path.join(worldPath,'index.json'),JSON.stringify({detail:{size:375,grid:16,origin:-3000,cells:[{cell:28}]},inside:{cells:[]}}));
  function mesh(wall) {
    const vertices=[[1500,-2625,0],[1875,-2625,0],[1875,-2250,0],[1500,-2250,0]];
    const indices=[0,1,2,0,2,3];
    if(wall) {vertices.push([1571,-2470,0],[1571,-2450,0],[1571,-2450,20],[1571,-2470,20]);indices.push(4,5,6,4,6,7);}
    const bytes=Buffer.alloc(16+vertices.length*12+indices.length*4);
    [0x324c4353,vertices.length,indices.length/3,0].forEach((n,i)=>bytes.writeUInt32LE(n,i*4));
    vertices.forEach((v,i)=>v.forEach((n,j)=>bytes.writeFloatLE(n,16+i*12+j*4)));
    indices.forEach((n,i)=>bytes.writeUInt32LE(n,16+vertices.length*12+i*4));
    fs.writeFileSync(path.join(worldPath,'c28.col.bin'),bytes);
  }
  mesh(false);
  const collision=require(path.join(temporary,'world_collision.js'));
  let world=new collision.WorldCollision();collision.lineOfSight=(a,b)=>world.lineOfSight(a,b);
  game=require(path.join(temporary,'selfhost_backend.js'));
  function peer(native) {
    const {player}=game.ensurePlayer({headers:{cookie:''}},{setHeader(){}}),packets=[];
    const p={player,ready:false,lastSeen:now,state:{walking:true,x:1570,y:-2460,z:13.6},send:m=>packets.push(m),packets};
    game.peers.add(p);game.onMessage(p,{t:'hi',nativeInventory:native,...(native?{inventoryAck:1}:{})});return p;
  }
  const a=peer(true),b=peer(true),browser=peer(false);b.state.x=1572;browser.state.x=1570;
  function hit(from,extra={}) {
    now+=400;from.lastSeen=b.lastSeen=now;
    game.onMessage(from,{t:'hit',to:String(b.player.number),w:0,c:from.inventoryConnection,...extra});
  }
  function geometry(kind) {
    if(kind==='missing')fs.rmSync(path.join(worldPath,'c28.col.bin'));else mesh(kind==='wall');
    world=new collision.WorldCollision();
  }
  for(const attacker of [a,browser]) {
    b.player.health=100;b.player.armour=0;
    geometry('wall');hit(attacker);assert.equal(b.player.health,100,'Fist damage crossed a real SCL2 wall');
    geometry('missing');hit(attacker);assert.equal(b.player.health,100,'Missing geometry authorized fist damage');
    geometry('clear');hit(attacker);assert.equal(b.player.health,92,'Clear synthetic melee did not retain the server damage policy');
    const health=b.player.health;
    game.onMessage(attacker,{t:'hit',to:String(b.player.number),w:0,c:attacker.inventoryConnection});
    assert.equal(b.player.health,health,'Repeated melee ignored existing server cadence');
    b.state.x=1575;hit(attacker);assert.equal(b.player.health,health,'Out-of-policy range fist hit accepted');b.state.x=1572;
    b.player.passive=true;hit(attacker);assert.equal(b.player.health,health);b.player.passive=false;
    b.player.insideHome='synthetic-home';hit(attacker);assert.equal(b.player.health,health);b.player.insideHome=null;
    attacker.player.health=0;hit(attacker);assert.equal(b.player.health,health);attacker.player.health=100;
  }
  b.player.health=100;hit(a,{c:'foreign-connection'});assert.equal(b.player.health,100,'Foreign inventory connection authorized melee');
  a.player.inventory={selected:2,weapons:{2:{clip:0,rest:0}}};a.lastWeapon=22;
  hit(a,{w:2});assert.equal(b.player.health,86,'Owned nonzero melee wrongly required a previous ammunition shot');
  assert.equal(a.player.inventory.weapons[2].clip,0,'Melee consumed ammunition');
  hit(a,{w:3});assert.equal(b.player.health,86,'Unowned melee bypassed selected-weapon authority');
  hit(a,{w:22});assert.equal(b.player.health,86,'Melee path authorized a gun without an accepted shot');
  assert.equal(a.processedShotSequence || 0,0,'Melee consumed an ammunition sequence');
  // Current server-owned equipment wins over a delayed walking weapon tag.
  b.player.health=100;b.player.armour=50;b.state.heading=Math.PI/2;b.state.act=28;b.state.weapon=0;
  hit(a,{w:2});assert.equal(b.player.health,100);assert.equal(b.player.armour,50,'Front block consumed armour');
  b.player.inventory={selected:22,weapons:{22:{clip:1,rest:0}}};
  hit(a,{w:2});assert.equal(b.player.armour,36,'Old melee wire tag blocked with a server-selected gun');
  b.player.inventory.selected=0;b.state.weapon=22;
  hit(a,{w:2});assert.equal(b.player.armour,36,'Old gun wire tag disabled server-selected melee block');
  b.state.heading=-Math.PI/2;hit(a,{w:2});assert.equal(b.player.armour,22,'Rear hit was parried');
  b.state.heading=Math.PI/2;b.state.act=36;hit(a,{w:2});assert.equal(b.player.armour,8,'Idle guard stance parried a hit');
  b.state.act=28;browser.state.weapon=9;hit(browser);
  assert.equal(b.player.armour,0);assert.equal(b.player.health,78,'Chainsaw incorrectly entered the block path');
  console.log('PASS: actual native/browser melee handler, clear/wall/missing SCL2 geometry, cadence/range, passive/dead/interior/connection boundaries, no ammunition sequence');
} finally {
  Date.now=originalNow;if(game){clearInterval(game.tick);clearInterval(game.projectileTimer);}
  fs.rmSync(temporary,{recursive:true,force:true});
}
