#!/usr/bin/env node
'use strict';
// Actual independent backend + real SCL2 queries, synthetic peer transport and
// explicitly synthetic geometry. No listener, physical input or app is started.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-streams-')),originalNow=Date.now;
let now=1_700_000_000_000,game,sequence=0;
try {
  Date.now=()=>now;
  const local=path.join(temporary,'local-only'),selfhost=path.join(local,'selfhost'),world=path.join(local,'site/game/world'),native=path.join(local,'site/game/native');
  fs.mkdirSync(selfhost,{recursive:true});fs.mkdirSync(world,{recursive:true});fs.mkdirSync(native,{recursive:true});
  for(const name of ['selfhost_backend.js','player_placement.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js'])fs.copyFileSync(path.join(require('node:path').resolve(__dirname, '../..'),name),path.join(temporary,name));
  fs.copyFileSync(path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/game/native/foot-animation.json'),path.join(native,'foot-animation.json'));
  const stats=JSON.parse(fs.readFileSync(path.join(require('node:path').resolve(__dirname, '../..'),'local-only/site/game/native/weapons.json'))).stats;
  fs.writeFileSync(path.join(selfhost,'weapon-catalog.json'),JSON.stringify({items:[37,41,42].map(id=>({id,name:'Stream fixture',ammo:500,capacity:500,price:0,slot:id,fire:'AREA_EFFECT',stats:stats[id]})),shops:[]}));
  fs.writeFileSync(path.join(selfhost,'client-catalog.json'),JSON.stringify({homes:[
    {key:'stream-fire-fixture',name:'Synthetic fire',price:1,out:[60,60,0.1,0]},
    {key:'blocked-fire-fixture',name:'Synthetic blocked fire',price:1,out:[14,20,0.1,0]}]}));
  fs.writeFileSync(path.join(world,'index.json'),JSON.stringify({detail:{grid:1,size:375,origin:0,cells:[{cell:0}]},inside:{cells:[]}}));
  const triangles=[[[0,0,0],[375,0,0],[375,375,0]],[[0,0,0],[375,375,0],[0,375,0]],
    [[12,10,0],[12,30,0],[12,30,5]],[[12,10,0],[12,30,5],[12,10,5]]];
  const vertices=triangles.flat(),mesh=Buffer.alloc(16+vertices.length*12+triangles.length*12);
  [0x324c4353,vertices.length,triangles.length,0].forEach((n,i)=>mesh.writeUInt32LE(n,i*4));
  vertices.forEach((p,i)=>p.forEach((n,axis)=>mesh.writeFloatLE(n,16+i*12+axis*4)));
  for(let i=0;i<vertices.length;i++)mesh.writeUInt32LE(i,16+vertices.length*12+i*4);
  fs.writeFileSync(path.join(world,'c0.col.bin'),mesh);
  game=require(path.join(temporary,'selfhost_backend.js'));
  function peer(){const {player}=game.ensurePlayer({headers:{cookie:''}},{setHeader(){}}),packets=[];
    const p={player,packets,ready:true,inventoryEnabled:true,lastSeen:now,state:{walking:true,x:10,y:40,z:0},send:x=>packets.push(x)};
    game.peers.add(p);return p;}
  const a=peer(),b=peer(),c=peer();
  function reset(weapon=37,{x=10,y=40,tx=14,ty=y,clip=500}={}) {
    now+=1000;
    Object.assign(a.state,{walking:true,x,y,z:0});Object.assign(b.state,{walking:true,x:tx,y:ty,z:0});
    a.player.health=b.player.health=100;a.player.armour=b.player.armour=0;
    a.player.passive=b.player.passive=false;a.player.insideHome=b.player.insideHome=null;a.player.job=null;
    a.player.inventory={selected:weapon,weapons:{[weapon]:{clip,rest:0}}};a.areaDousing=null;
  }
  function shot(weapon=37,{target=null,s=++sequence,legacy=false}={}) {
    for (const p of [a,b,c])p.lastSeen=now;
    const o=[a.state.x,a.state.y,a.state.z+1.35],h=target || [a.state.x+20,a.state.y,a.state.z+1.35];
    game.onMessage(a,{t:'shot',w:weapon,...(legacy?{}:{s}),o,h});return legacy?undefined:s;
  }
  function hit(s,weapon=37,target=b){for(const p of [a,b,c])p.lastSeen=now;game.onMessage(a,{t:'hit',w:weapon,...(s===undefined?{}:{s}),to:String(target.player.number)});}
  reset();let s=shot();hit(s);assert.equal(b.player.health,99);assert.equal(a.player.inventory.weapons[37].clip,499);
  hit(s);assert.equal(b.player.health,99,'Replayed stream event damaged target');assert.equal(a.player.inventory.weapons[37].clip,499,'Stream hit charged extra ammunition');
  now+=20;s=shot();hit(s);assert.equal(b.player.health,99,'300ms stream damage cadence bypassed');
  now+=300;hit(s);assert.equal(b.player.health,99,'Cadence-rejected event replayed later');
  s=shot();hit(s);assert.equal(b.player.health,98);
  reset(41);s=shot(41);hit(s,41);assert.equal(b.player.health,99,'Spray-can policy damage missing');
  for(const [label,setup]of[
    ['wall',()=>reset(37,{y:20})],['range',()=>reset(37,{tx:15.2})],['lateral',()=>reset(37,{ty:41})],
    ['missing geometry',()=>reset(37,{x:400,tx:404})],['target passive',()=>{reset();b.player.passive=true;}],
    ['attacker passive',()=>{reset();a.player.passive=true;}],['attacker dead',()=>{reset();a.player.health=0;}],
    ['different interior',()=>{reset();b.player.insideHome='other';}],['empty clip',()=>reset(37,{clip:0})],
    ['reload',()=>{reset();a.player.inventory.reload={weapon:37,until:now+1000};}],
  ]){setup();const hp=b.player.health;s=shot();hit(s);assert.equal(b.player.health,hp,label+' allowed stream damage');
    if(['wall','range','lateral','missing geometry'].includes(label))assert.equal(a.player.inventory.weapons[37].clip,499,label+' test never reached an inventory-authorized emission');}
  reset();s=shot();now+=351;hit(s);assert.equal(b.player.health,100,'Stale accepted emission damaged target');
  reset();s=shot();a.state.x+=20;hit(s);assert.equal(b.player.health,100,'Teleported shooter reused distant origin');
  reset();s=shot();a.player.inventory.selected=0;hit(s);assert.equal(b.player.health,100,'Switched weapon reused active stream');
  reset();s=shot();hit(s);Object.assign(c.state,{x:14,y:40.4,z:0});c.player.health=100;c.player.passive=false;
  hit(s,37,c);assert.equal(c.player.health,99,'One stream check could not affect a second person');
  reset(41);s=shot(41,{legacy:true});hit(s,41);hit(s,41);assert.equal(b.player.health,99,'Legacy inventory stream replay or compatibility failed');
  reset(42);s=shot(42);hit(s,42);assert.equal(b.player.health,100,'Extinguisher damaged a pedestrian');
  function fire(home='stream-fire-fixture') {a.player.job={id:'fire',mode:'fire',incidentHome:home,index:0,stage:'extinguish',started:now,vehicleId:'fixture'};}
  reset(42,{x:56,y:60,tx:60});fire();const target=[60,60,0.1];
  for(let i=0;i<24;i++){shot(42,{target});now+=20;}
  assert.equal(a.player.job.index,0,'Extinguisher completed before0.5s');shot(42,{target});
  assert.equal(a.player.job.index,1,'Verified spray failed to suppress existing mission fire');
  assert.equal(a.player.inventory.weapons[42].clip,475,'Dousing consumed extra ammunition');
  assert.equal(a.packets.filter(p=>p.t==='note'&&p.text==='Fire 1/3 out. Move to the next fire spot.').length,1);
  reset(42,{x:10,y:20});fire('blocked-fire-fixture');
  for(let i=0;i<30;i++){shot(42,{target:[14,20,0.1]});now+=20;}
  assert.equal(a.player.job.index,0,'Extinguisher suppressed through a wall');
  reset(42,{x:46,y:60});fire();
  for(let i=0;i<30;i++){shot(42,{target});now+=20;}
  assert.equal(a.player.job.index,0,'Extinguisher exceeded10.1m');
  reset(42,{x:56,y:60});fire();
  for(let i=0;i<20;i++)shot(42,{target});
  assert.equal(a.player.job.index,0,'Same-frame burst invented held spray duration');
  now+=1000;shot(42,{target});assert.equal(a.player.job.index,0,'Disconnected trigger banked a second of spray');
  for(const condition of ['passive','empty','spray']){
    const weapon=condition==='spray'?41:42;reset(weapon,{x:56,y:60,clip:condition==='empty'?0:500});fire();
    if(condition==='passive')a.player.passive=true;
    for(let i=0;i<30;i++){shot(weapon,{target});now+=20;}
    assert.equal(a.player.job.index,0,condition+' suppressed fire without a valid extinguisher');
  }
  reset(42,{x:38,y:60});fire();a.player.job.index=2;
  for(let i=0;i<25;i++){shot(42,{target:[42,60,0.1]});now+=20;}
  assert.equal(a.player.job.index,3);assert.equal(a.player.job.stage,'rescue','Final suppression did not enter existing rescue stage');
  reset(42,{x:56,y:60});a.player.job=null;
  const car={id:'burning-fixture',row:['burning-fixture','Fixture','420',60,60,0.1,0,0,0,200,'']};game.vehicles.set(car.id,car);
  for(let i=0;i<30;i++){shot(42,{target});now+=20;}
  assert.equal(car.row[9],200,'Extinguisher repaired a vehicle to fake an untracked engine fire');
  game.flushSync();
  console.log('PASS: actual backend peers, SCL2 wall/clear/missing geometry,37/41 cylinder damage,300ms cadence/replay/350ms evidence, ammo/reload/switch/health/passive/interior guards, legacy inventory compatibility,42 no pedestrian damage and authoritative existing-fire suppression');
} finally {
  Date.now=originalNow;
  if(game){clearInterval(game.tick);clearInterval(game.projectileTimer);game.flushSync();}
  fs.rmSync(temporary,{recursive:true,force:true});
}
