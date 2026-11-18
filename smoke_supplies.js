#!/usr/bin/env node
// Isolated workshop purchase, use, nearby transfer and restart checks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-supplies-'));
try {
  const local = path.join(temporary, 'local-only', 'selfhost');
  fs.mkdirSync(local, {recursive: true});
  for (const file of ['selfhost_backend.js','player_placement.js', 'optional_discord.js', 'weapon_inventory.js', 'world_collision.js', 'local_projectiles.js'])
    fs.copyFileSync(path.join(__dirname, file), path.join(temporary, file));
  fs.copyFileSync(path.join(__dirname, 'local-only', 'selfhost', 'client-catalog.json'),
    path.join(local, 'client-catalog.json'));
  const dealer = require(path.join(local, 'client-catalog.json')).dealers
    .find(item => item.key === 'coutt');
  const backend = path.join(temporary, 'selfhost_backend.js');
  let game = require(backend);
  const first = game.ensurePlayer({headers: {cookie: ''}}, {setHeader() {}});
  const second = game.ensurePlayer({headers: {cookie: ''}}, {setHeader() {}});
  first.player.cash = 1000;
  first.player.cars.push(410);
  first.player.garage.push({health: 1000, damage: '', active: false,
    position: null, paint: null, parkedHome: null});
  const stateA = {walking: true, x: 1480, y: -1738, z: 13};
  const stateB = {walking: true, x: 1482, y: -1738, z: 13};
  const sent = [];
  const firstPeer = {player: first.player, ready: true, lastSeen: Date.now(),
    state: stateA, send: packet => sent.push(packet)};
  game.peers.add(firstPeer);
  const secondPeer = {player: second.player, ready: true, lastSeen: Date.now(),
    state: stateB, send() {}};
  game.peers.add(secondPeer);
  assert.throws(() => game.action(first.player, 'supply.buy', {item: 'repair_kit'}),
    /ground dealership/);
  assert.equal(first.player.cash, 1000);
  stateA.x = dealer.stand[0]; stateA.y = dealer.stand[1]; stateA.z = dealer.stand[2];
  stateB.x = stateA.x + 2; stateB.y = stateA.y; stateB.z = stateA.z;
  assert.equal(game.gameplayState(first.player).dealer.id, 'coutt');
  assert.match(game.action(first.player, 'supply.buy', {item: 'repair_kit'}).message,
    /Repair kit bought/);
  game.action(first.player, 'supply.buy', {item: 'paint_can'});
  game.action(first.player, 'supply.buy', {item: 'paint_can'});
  assert.equal(first.player.cash, 675);
  assert.equal(first.player.supplies.paint_can, 2);
  game.say(firstPeer, '/supplies');
  assert(sent.some(packet => packet.t === 'note' && packet.text.includes('Paint can 2/5')));
  first.player.supplies.paint_can = 5;
  assert.throws(() => game.action(first.player, 'supply.buy', {item: 'paint_can'}),
    /carry only 5/);
  assert.equal(first.player.cash, 675);
  first.player.supplies.paint_can = 2;
  game.action(first.player, 'car.spawn', {slot: 0});
  const before = game.ownedVehicle(first.player, 0);
  first.player.garage[0].health = 600;
  first.player.garage[0].damage = 'bent';
  game.onMessage(secondPeer,{t:'enter',v:before.id});
  game.onMessage(secondPeer,{t:'me',walking:false,driving:true,skin:7,
    vehicle:before.id,car:before.row[2],x:before.row[3],y:before.row[4],z:before.row[5],
    health:600,damage:'bent'});
  assert.equal(game.vehicleDriver(before),secondPeer,'Workshop fixture must establish actual driver authority');
  assert.throws(() => game.action(first.player, 'supply.use',
    {item: 'repair_kit', slot: 0}), /until everyone leaves/);
  assert.throws(() => game.action(first.player, 'car.spawn', {slot: 0}),
    /until everyone leaves/);
  assert.equal(first.player.supplies.repair_kit, 1);
  assert.equal(game.ownedVehicle(first.player, 0).id, before.id);
  game.onMessage(secondPeer,{t:'me',...stateB,skin:7});
  assert.equal(game.vehicleClaim(before),null,'Workshop exit must release actual driver authority');
  secondPeer.state=stateB;
  assert.match(game.action(first.player, 'supply.use', {item: 'repair_kit', slot: 0}).message,
    /used on Manana/);
  assert.equal(first.player.garage[0].health, 1000);
  assert.equal(first.player.garage[0].damage, '');
  assert.equal(first.player.supplies.repair_kit, 0);
  assert(sent.some(packet => packet.t === 'vgone' && packet.id === before.id));
  assert.throws(() => game.action(first.player, 'supply.use',
    {item: 'repair_kit', slot: 0}), /do not have/);
  const oldCode = game.ownedVehicle(first.player, 0).row[2];
  game.action(first.player, 'supply.use', {item: 'paint_can', slot: 0});
  assert.notEqual(game.ownedVehicle(first.player, 0).row[2], oldCode);
  assert.equal(first.player.supplies.paint_can, 1);
  stateB.x += 20;
  assert.throws(() => game.action(first.player, 'supply.give',
    {item: 'paint_can', number: second.player.number}), /within 8 m/);
  assert.equal(first.player.supplies.paint_can, 1);
  stateB.x = stateA.x + 2;
  second.player.supplies.paint_can = 5;
  assert.throws(() => game.action(first.player, 'supply.give',
    {item: 'paint_can', number: second.player.number}), /cannot carry/);
  second.player.supplies.paint_can = 0;
  assert.match(game.action(first.player, 'supply.give',
    {item: 'paint_can', number: second.player.number}).message, /Gave a paint can/);
  assert.equal(first.player.supplies.paint_can, 0);
  assert.equal(second.player.supplies.paint_can, 1);
  game.flushSync(); clearInterval(game.tick);
  fs.unlinkSync(path.join(temporary, 'local-only', 'selfhost', 'players.json.lock'));
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  assert.equal(game.players.get(first.id).cash, 675);
  assert.equal(game.players.get(first.id).supplies.paint_can, 0);
  assert.equal(game.players.get(second.id).supplies.paint_can, 1);
  assert.equal(game.players.get(first.id).garage[0].health, 1000);
  assert.deepEqual(game.players.get(first.id).garage[0].paint.length, 2);
  clearInterval(game.tick);
  console.log('PASS: dealership supplies, repair, paint, transfer limits and restart');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
