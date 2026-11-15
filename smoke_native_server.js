#!/usr/bin/env node
const assert = require('node:assert/strict'), fs = require('node:fs'), os = require('node:os'), path = require('node:path');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(),'zgta-native-server-'));
try {
  const local = path.join(temporary,'local-only'); fs.mkdirSync(path.join(local,'selfhost'),{recursive:true});
  fs.symlinkSync(path.join(__dirname,'local-only/site'),path.join(local,'site'));
  for (const name of ['selfhost_backend.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js']) fs.copyFileSync(path.join(__dirname,name),path.join(temporary,name));
  for (const name of ['client-catalog.json','weapon-catalog.json']) fs.copyFileSync(path.join(__dirname,'local-only/selfhost',name),path.join(local,'selfhost',name));
  const game = require(path.join(temporary,'selfhost_backend.js'));
  const catalog = require('./local-only/selfhost/weapon-catalog.json');
  const create = () => {
    const {player} = game.ensurePlayer({headers:{cookie:''}},{setHeader(){}});
    const packets = []; const peer = {player,ready:true,lastSeen:Date.now(),state:{walking:true,x:1480,y:-1738,z:13},send:p=>packets.push(p)};
    game.peers.add(peer); game.onMessage(peer,{t:'hi',nativeInventory:true});
    return {player,peer,packets};
  };
  const a=create(),b=create(),interior=create(); a.player.cash=1000000;
  interior.player.insideHome='elcorona';
  assert.equal(a.packets.find(p=>p.t==='inventory').state.selected,0);
  const door=catalog.shops[0].door;
  Object.assign(a.peer.state,{x:door[0],y:door[1],z:door[2]});
  game.action(a.player,'weapon.buy',{weapon:16,packs:1});
  assert.equal(game.gameplayState(a.player).weaponInventory.selected,16);
  Object.assign(a.peer.state,{x:1570,y:-2460,z:13.6,walking:true});
  Object.assign(b.peer.state,{x:1574,y:-2460,z:13.6,walking:true});
  const launch={t:'shot',w:16,o:[1570,-2460,14.95],h:[1570,-2460,13.95]};
  game.onMessage(a.peer,launch);
  assert.equal(game.projectiles.size,1);
  assert(a.packets.some(p=>p.t==='projectile' && p.event.type==='launch'));
  assert(!interior.packets.some(p=>p.t==='projectile'),'outside projectiles must not appear in a home');
  assert.equal(a.player.inventory.weapons['16'].clip,0);
  a.peer.lastShotAt-=400; a.player.inventory.lastShotAt-=400;
  game.onMessage(a.peer,launch);
  assert.equal(game.projectiles.size,1,'empty clip cannot launch another grenade');
  game.projectiles.tick(1);game.projectiles.tick(1);game.projectiles.tick(0.05);
  assert.equal(game.projectiles.size,0);
  assert(b.player.health<100,'server grenade blast damages a nearby player through real clear geometry');
  assert(b.packets.some(p=>p.t==='vitals' && p.health<100));
  assert(!interior.packets.some(p=>p.t==='projectile'),'outside blast effects must not appear in a home');
  assert.equal(interior.player.health,100,'outside blast must not damage a player in a home');
  const condition='3434012122110101201';
  const loaner={id:'native-condition-fixture',missionOwner:a.player,
    row:['native-condition-fixture',a.player.name,'420',1570,-2460,13.6,0,0,0,1000,'',null]};
  game.vehicles.set(loaner.id,loaner);
  game.onMessage(b.peer,{t:'me',driving:true,vehicle:loaner.id,car:'420',x:1570,y:-2460,z:13.6,health:1,damage:condition});
  assert.equal(loaner.row[9],1000,'another player cannot alter the mission vehicle condition');
  game.onMessage(a.peer,{t:'me',driving:true,vehicle:loaner.id,car:'420',x:1570,y:-2460,z:13.6,health:645,damage:condition});
  assert.equal(loaner.row[9],645);assert.equal(loaner.row[10],condition);
  game.onMessage(a.peer,{t:'me',walking:true,vehicle:loaner.id,car:'420',x:1572,y:-2460,z:13.6,
    parked:{x:1570,y:-2460,z:13.6,heading:.5,pitch:.1,roll:-.2,health:900,damage:condition}});
  assert.equal(loaner.row[9],645,'parking cannot silently repair a damaged mission car');
  assert.equal(loaner.row[10],condition);assert.equal(loaner.row[7],.1);assert.equal(loaner.row[8],-.2);
  game.flushSync();clearInterval(game.tick);clearInterval(game.projectileTimer);
  const saved=JSON.parse(fs.readFileSync(path.join(local,'selfhost/players.json')));
  assert(Object.values(saved.players).some(p=>p.inventory?.weapons?.['16']?.clip===0));
  console.log('PASS: native inventory, accepted/empty throws, shared blast, home separation, saved ammo and owner-only mission car condition/parking');
} finally {fs.rmSync(temporary,{recursive:true,force:true});}
