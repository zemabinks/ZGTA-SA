#!/usr/bin/env node
// Isolated catalog, hangar access, aircraft spawn and persistence checks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-aircraft-'));
try {
  const local = path.join(temporary, 'local-only', 'selfhost');
  fs.mkdirSync(local, {recursive: true});
  for (const file of ['selfhost_backend.js', 'optional_discord.js'])
    fs.copyFileSync(path.join(__dirname, file), path.join(temporary, file));
  const catalog = require(path.join(__dirname, 'local-only', 'selfhost', 'client-catalog.json'));
  fs.copyFileSync(path.join(__dirname, 'local-only', 'selfhost', 'client-catalog.json'),
    path.join(local, 'client-catalog.json'));
  const airport = id => catalog.dealers.find(item => item.air === id);
  const backend = path.join(temporary, 'selfhost_backend.js');
  let game = require(backend);
  const {id, player} = game.ensurePlayer({headers: {cookie: ''}}, {setHeader() {}});
  player.cash = 7000000;
  const sent = [];
  const peer = {player, ready: true, lastSeen: Date.now(),
    state: {walking: true, x: 1480, y: -1738, z: 13},
    send: packet => sent.push(packet)};
  game.peers.add(peer);
  assert(game.gameplayState(player).catalog.cars.some(car => car.model === 593));
  assert(game.gameplayState(player).catalog.cars.some(car => car.model === 577));
  assert.throws(() => game.action(player, 'car.buy', {model: 593}), /airport hangar/);
  assert.equal(player.cash, 7000000);
  peer.state.x = airport('vm').stand[0];
  peer.state.y = airport('vm').stand[1];
  peer.state.z = airport('vm').stand[2];
  assert.equal(game.gameplayState(player).hangar.id, 'vm');
  const available = game.gameplayState(player).catalog.cars;
  assert(!available.find(car => car.model === 577).airports.includes('vm'));
  assert(available.find(car => car.model === 593).airports.includes('vm'));
  assert.throws(() => game.action(player, 'car.buy', {model: 577}), /sells this aircraft/);
  assert.equal(player.cash, 7000000);
  const bought = game.action(player, 'car.buy', {model: 593});
  assert.match(bought.message, /Dodo bought/);
  assert.equal(player.cash, 6650000);
  assert.deepEqual(player.cars, [593]);
  const spawned = game.action(player, 'car.spawn', {slot: 0});
  assert.match(spawned.message, /Verdant Meadows Hangar/);
  assert.equal(player.garage[0].active, true);
  const plane = [...game.vehicles.values()].find(vehicle => vehicle.owner === player);
  assert.equal(plane.row[2].split('.')[0], '593');
  assert.equal(plane.row[3], airport('vm').stand[0] + 4);
  assert(sent.some(packet => packet.t === 'spawned' && packet.v[0] === plane.id));
  peer.state.x = 1480; peer.state.y = -1738;
  assert.throws(() => game.action(player, 'car.spawn', {slot: 0}), /airport hangar/);
  assert(game.vehicles.has(plane.id), 'failed recall leaves the aircraft in world');
  game.flushSync(); clearInterval(game.tick);
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  const resumed = game.players.get(id);
  assert.deepEqual(resumed.cars, [593]);
  assert.equal(resumed.cash, 6650000);
  assert.equal(resumed.garage[0].active, true);
  assert([...game.vehicles.values()].some(vehicle => vehicle.owner === resumed &&
    vehicle.row[2].split('.')[0] === '593'));
  clearInterval(game.tick);
  console.log('PASS: hangar restrictions, aircraft purchase, spawn, recall and restart');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
