#!/usr/bin/env node
// Isolated exterior parking, capacity and restart checks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-property-garage-'));
try {
  const local = path.join(temporary, 'local-only', 'selfhost');
  fs.mkdirSync(local, {recursive: true});
  for (const file of ['selfhost_backend.js','player_placement.js', 'optional_discord.js', 'weapon_inventory.js', 'world_collision.js', 'local_projectiles.js'])
    fs.copyFileSync(path.join(__dirname, file), path.join(temporary, file));
  fs.copyFileSync(path.join(__dirname, 'local-only', 'selfhost', 'client-catalog.json'),
    path.join(local, 'client-catalog.json'));
  const catalog = require(path.join(local, 'client-catalog.json'));
  const home = catalog.homes.find(item => item.key === 'willowfield');
  const backend = path.join(temporary, 'selfhost_backend.js');
  let game = require(backend);
  const {id, player} = game.ensurePlayer({headers: {cookie: ''}}, {setHeader() {}});
  player.homes.push(home.key);
  const state = {walking: true, x: home.out[0], y: home.out[1], z: home.out[2]};
  const peer = {player, ready: true, lastSeen: Date.now(), state, send() {}};
  game.peers.add(peer);
  player.cars.push(410, 400, 560);
  player.garage.push(...player.cars.map(() => ({health: 1000, damage: '',
    active: false, position: null, paint: null, parkedHome: null})));
  player.garage[0].health = 750;
  for (let slot = 0; slot < 3; slot++) game.action(player, 'car.spawn', {slot});
  assert.equal(game.gameplayState(player).homeParking.occupied, 0);
  assert.match(game.action(player, 'car.parkhome', {slot: 0}).message, /parked at/);
  assert.match(game.action(player, 'car.parkhome', {slot: 1}).message, /parked at/);
  assert.equal(game.gameplayState(player).homeParking.occupied, 2);
  assert.throws(() => game.action(player, 'car.parkhome', {slot: 2}), /two parked vehicles/);
  assert.equal(player.garage[2].active, true, 'failed parking leaves car outside');
  game.flushSync(); clearInterval(game.tick);
  fs.unlinkSync(path.join(temporary, 'local-only', 'selfhost', 'players.json.lock'));
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  const resumed = game.players.get(id);
  assert.deepEqual(resumed.garage.slice(0, 2).map(entry => entry.parkedHome),
    ['willowfield', 'willowfield']);
  assert.equal(resumed.garage[0].health, 750);
  assert.equal(game.gameplayState(resumed).garage[0].active, false);
  peer.player = resumed;
  game.peers.add(peer);
  state.x = 1480; state.y = -1738; state.z = 13;
  assert.throws(() => game.action(resumed, 'car.spawn', {slot: 0}), /retrieve this parked vehicle/);
  assert.equal(resumed.garage[0].parkedHome, 'willowfield');
  state.x = home.out[0]; state.y = home.out[1]; state.z = home.out[2];
  assert.match(game.action(resumed, 'car.spawn', {slot: 0}).message, /retrieved/);
  assert.equal(resumed.garage[0].parkedHome, null);
  assert.equal(resumed.garage[0].health, 750);
  assert.equal(game.gameplayState(resumed).homeParking.occupied, 1);
  clearInterval(game.tick);
  console.log('PASS: property parking capacity, saved condition, restart and local retrieval');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
