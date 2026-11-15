#!/usr/bin/env node
// Isolated freight pickup, marked truck, payout, and restart check.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-trucker-'));
try {
  const local = path.join(temporary, 'local-only', 'selfhost');
  fs.mkdirSync(local, {recursive: true});
  for (const file of ['selfhost_backend.js', 'optional_discord.js', 'weapon_inventory.js', 'world_collision.js', 'local_projectiles.js'])
    fs.copyFileSync(path.join(__dirname, file), path.join(temporary, file));
  fs.copyFileSync(path.join(__dirname, 'local-only', 'selfhost', 'client-catalog.json'),
    path.join(local, 'client-catalog.json'));
  const backend = path.join(temporary, 'selfhost_backend.js');
  let game = require(backend);
  const {id, player} = game.ensurePlayer({headers: {cookie: ''}}, {setHeader() {}});
  const other = game.ensurePlayer({headers: {cookie: ''}}, {setHeader() {}}).player;
  let sent = [], otherSent = [];
  let peer = {player, ready: true, lastSeen: Date.now(),
    state: {walking: true, x: 1480, y: -1738, z: 13},
    send: packet => sent.push(packet)};
  const otherPeer = {player: other, ready: true, lastSeen: Date.now(),
    state: {walking: true, x: 1480, y: -1738, z: 13},
    send: packet => otherSent.push(packet)};
  game.peers.add(peer);
  game.peers.add(otherPeer);

  const begun = game.action(player, 'job.start', {job: 'trucker'});
  assert.equal(begun.state.job.mode, 'route');
  assert.equal(begun.state.job.stage, 'pickup');
  assert(begun.state.job.secondsLeft > 0 && begun.state.job.secondsLeft <= 420);
  const truckId = player.job.vehicleId;
  const truck = game.vehicles.get(truckId);
  assert.equal(truck.row[2], '414.25.1.0.');
  assert(sent.some(packet => packet.t === 'spawned' && packet.v[0] === truckId));
  assert(otherSent.some(packet => packet.t === 'spawned' && packet.v[0] === truckId));
  game.onMessage(otherPeer, {t: 'enter', v: truckId});
  assert(otherSent.some(packet => packet.t === 'enter' && packet.v === truckId && !packet.ok));
  game.onMessage(peer, {t: 'enter', v: truckId});
  assert(sent.some(packet => packet.t === 'enter' && packet.v === truckId && packet.ok));
  assert.throws(() => game.action(player, 'job.pickup', {}), /pickup point/);
  const pickup = begun.state.job.target;
  peer.state.x = pickup.x; peer.state.y = pickup.y;
  assert.throws(() => game.action(player, 'job.pickup', {}), /Drive/);
  peer.state = {walking: false, driving: true, x: pickup.x, y: pickup.y, z: 13,
    car: truck.row[2], vehicle: 'wrong'};
  assert.throws(() => game.action(player, 'job.pickup', {}), /marked Mule/);
  peer.state.vehicle = truckId;
  game.action(player, 'job.pickup', {});
  assert.equal(player.job.stage, 'delivery');
  game.flushSync();
  clearInterval(game.tick);
  fs.unlinkSync(path.join(temporary, 'local-only', 'selfhost', 'players.json.lock'));
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  const resumed = game.players.get(id);
  assert.equal(resumed.job.id, 'trucker');
  assert.equal(resumed.job.stage, 'delivery');
  assert.equal(game.vehicles.get(truckId).row[2], '414.25.1.0.');
  sent = [];
  peer = {player: resumed, ready: true, lastSeen: Date.now(),
    state: {walking: false, driving: true, x: pickup.x, y: pickup.y, z: 13,
      car: truck.row[2], vehicle: truckId}, send: packet => sent.push(packet)};
  game.peers.add(peer);
  resumed.job.started = Date.now() - 3100;
  assert.throws(() => game.action(resumed, 'job.complete', {}), /delivery destination/);
  const drop = game.gameplayState(resumed).job.target;
  peer.state.x = drop.x; peer.state.y = drop.y;
  peer.state.vehicle = 'wrong';
  assert.throws(() => game.action(resumed, 'job.complete', {}), /marked Mule/);
  peer.state.vehicle = truckId;
  const finished = game.action(resumed, 'job.complete', {});
  assert.equal(finished.state.job, null);
  assert.equal(resumed.cash, 500);
  assert.equal(resumed.xp, 100);
  assert.equal(resumed.jobsDone, 1);
  assert.equal(game.vehicles.has(truckId), false);
  assert(sent.some(packet => packet.t === 'vgone' && packet.id === truckId));

  game.action(resumed, 'job.start', {job: 'trucker'});
  const cancelledId = resumed.job.vehicleId;
  game.action(resumed, 'job.cancel', {});
  assert.equal(game.vehicles.has(cancelledId), false);
  game.action(resumed, 'job.start', {job: 'trucker'});
  const expiredId = resumed.job.vehicleId;
  resumed.job.started = Date.now() - 421000;
  game.flushSync();
  clearInterval(game.tick);
  fs.unlinkSync(path.join(temporary, 'local-only', 'selfhost', 'players.json.lock'));
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  assert.equal(game.players.get(id).job, null, 'expired freight work is discarded on restart');
  assert.equal(game.vehicles.has(expiredId), false);
  clearInterval(game.tick);
  console.log('PASS: freight truck ownership, pickup, delivery, restart, payout, cancellation and expiry');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
