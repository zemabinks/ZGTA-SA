#!/usr/bin/env node
// Isolated fire dispatch, marked truck, staged suppression, rescue and restart checks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-fire-'));
try {
  const local = path.join(temporary, 'local-only', 'selfhost');
  fs.mkdirSync(local, {recursive: true});
  for (const file of ['selfhost_backend.js','player_placement.js', 'optional_discord.js', 'weapon_inventory.js', 'world_collision.js', 'local_projectiles.js'])
    fs.copyFileSync(path.join(__dirname, file), path.join(temporary, file));
  fs.copyFileSync(path.join(__dirname, 'local-only', 'selfhost', 'client-catalog.json'),
    path.join(local, 'client-catalog.json'));
  const catalog = require(path.join(__dirname, 'local-only', 'selfhost', 'client-catalog.json'));
  const backend = path.join(temporary, 'selfhost_backend.js');
  let game = require(backend);
  const {id, player} = game.ensurePlayer({headers: {cookie: ''}}, {setHeader() {}});
  const guest = game.ensurePlayer({headers: {cookie: ''}}, {setHeader() {}}).player;
  let sent = [], otherSent = [];
  let peer = {player, ready: true, lastSeen: Date.now(),
    state: {walking: true, x: 1480, y: -1738, z: 13},
    send: packet => sent.push(packet)};
  const otherPeer = {player: guest, ready: true, lastSeen: Date.now(),
    state: {walking: true, x: 1480, y: -1738, z: 13},
    send: packet => otherSent.push(packet)};
  game.peers.add(peer); game.peers.add(otherPeer);

  const started = game.action(player, 'job.start', {job: 'fire'});
  assert.equal(started.state.job.mode, 'fire');
  assert.equal(started.state.job.stage, 'respond');
  assert.equal(started.state.job.secondsLeft, 480);
  const truckId = player.job.vehicleId;
  assert.equal(game.vehicles.get(truckId).row[2], '407.3.1.0.');
  assert(sent.some(packet => packet.t === 'spawned' && packet.v[0] === truckId));
  assert(otherSent.some(packet => packet.t === 'spawned' && packet.v[0] === truckId));
  game.onMessage(otherPeer, {t: 'enter', v: truckId});
  assert(otherSent.some(packet => packet.t === 'enter' && packet.v === truckId && !packet.ok));
  const home = catalog.homes.find(item => item.key === player.job.incidentHome);
  assert(home);
  assert.throws(() => game.action(player, 'job.respond', {}), /marked fire truck/);
  peer.state = {driving: true, car: '407.3.1.0.', vehicle: 'wrong',
    x: home.out[0], y: home.out[1], z: home.out[2]};
  assert.throws(() => game.action(player, 'job.respond', {}), /marked fire truck/);
  peer.state.vehicle = truckId;
  game.action(player, 'job.respond', {});
  assert.equal(player.job.stage, 'extinguish');
  assert.throws(() => game.action(player, 'job.complete', {}), /recently|three fires/);
  peer.state.x = home.out[0] + 80;
  assert.throws(() => game.action(player, 'job.extinguish', {}), /within 23 m/);
  peer.state.x = home.out[0];
  game.action(player, 'job.extinguish', {});
  assert.equal(player.job.index, 1);
  game.flushSync(); clearInterval(game.tick);
  fs.unlinkSync(path.join(temporary, 'local-only', 'selfhost', 'players.json.lock'));
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  const resumed = game.players.get(id);
  assert.equal(resumed.job.stage, 'extinguish');
  assert.equal(resumed.job.index, 1);
  assert.equal(game.vehicles.get(truckId).row[2], '407.3.1.0.');
  sent = [];
  peer = {player: resumed, ready: true, lastSeen: Date.now(),
    state: {driving: true, car: '407.3.1.0.', vehicle: truckId,
      x: home.out[0], y: home.out[1], z: home.out[2]},
    send: packet => sent.push(packet)};
  game.peers.add(peer);
  game.action(resumed, 'job.extinguish', {});
  game.action(resumed, 'job.extinguish', {});
  assert.equal(resumed.job.stage, 'rescue');
  assert.equal(resumed.job.index, 3);
  resumed.job.started = Date.now() - 3500;
  assert.throws(() => game.action(resumed, 'job.complete', {}), /on foot/);
  peer.state = {walking: true, x: home.out[0] + 20, y: home.out[1], z: home.out[2]};
  assert.throws(() => game.action(resumed, 'job.complete', {}), /on foot/);
  peer.state.x = home.out[0];
  const finished = game.action(resumed, 'job.complete', {});
  assert.equal(finished.state.job, null);
  assert.equal(resumed.cash, 650);
  assert.equal(resumed.xp, 130);
  assert.equal(resumed.jobsDone, 1);
  assert(!game.vehicles.has(truckId));
  assert(sent.some(packet => packet.t === 'vgone' && packet.id === truckId));
  game.action(resumed, 'job.start', {job: 'fire'});
  const cancelled = resumed.job.vehicleId;
  game.action(resumed, 'job.cancel', {});
  assert(!game.vehicles.has(cancelled));
  game.action(resumed, 'job.start', {job: 'fire'});
  const expired = resumed.job.vehicleId;
  resumed.job.started = Date.now() - 481000;
  game.flushSync(); clearInterval(game.tick);
  fs.unlinkSync(path.join(temporary, 'local-only', 'selfhost', 'players.json.lock'));
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  assert.equal(game.players.get(id).job, null);
  assert(!game.vehicles.has(expired));
  clearInterval(game.tick);
  console.log('PASS: fire truck ownership, dispatch, suppression, rescue, payout, restart and expiry');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
