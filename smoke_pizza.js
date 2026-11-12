#!/usr/bin/env node
// Isolated pizza route, reserved scooter, payout, and restart check.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-pizza-'));
try {
  const local = path.join(temporary, 'local-only', 'selfhost');
  fs.mkdirSync(local, {recursive: true});
  for (const file of ['selfhost_backend.js', 'optional_discord.js'])
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

  const begun = game.action(player, 'job.start', {job: 'pizza'});
  assert.equal(begun.state.job.mode, 'checkpoints');
  assert.equal(begun.state.job.total, 3);
  assert(begun.state.job.secondsLeft > 0);
  const scooterId = player.job.vehicleId;
  const scooter = game.vehicles.get(scooterId);
  assert.equal(scooter.row[2], '448.1.1.0.');
  assert(sent.some(packet => packet.t === 'spawned' && packet.v[0] === scooterId));
  assert(otherSent.some(packet => packet.t === 'spawned' && packet.v[0] === scooterId));
  game.onMessage(otherPeer, {t: 'enter', v: scooterId});
  assert(otherSent.some(packet => packet.t === 'enter' && packet.v === scooterId && !packet.ok));
  game.onMessage(peer, {t: 'enter', v: scooterId});
  assert(sent.some(packet => packet.t === 'enter' && packet.v === scooterId && packet.ok));
  assert.throws(() => game.action(player, 'job.complete', {}), /started too recently/);
  assert.throws(() => game.action(player, 'job.checkpoint', {}), /Drive into/);
  const first = begun.state.job.target;
  peer.state.x = first.x; peer.state.y = first.y;
  assert.throws(() => game.action(player, 'job.checkpoint', {}), /Drive into/);
  peer.state = {walking: false, driving: true, x: first.x, y: first.y, z: 13,
    car: '448.1.1.0.', vehicle: 'wrong'};
  assert.throws(() => game.action(player, 'job.checkpoint', {}), /marked Pizzaboy/);
  peer.state.vehicle = scooterId;
  game.action(player, 'job.checkpoint', {});
  assert.equal(player.job.index, 1);
  game.flushSync();
  clearInterval(game.tick);
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  const resumed = game.players.get(id);
  assert.equal(resumed.job.id, 'pizza');
  assert.equal(resumed.job.index, 1);
  assert.equal(game.vehicles.get(scooterId).row[2], '448.1.1.0.');
  sent = [];
  peer = {player: resumed, ready: true, lastSeen: Date.now(),
    state: {walking: false, driving: true, x: first.x, y: first.y, z: 13,
      car: '448.1.1.0.', vehicle: scooterId}, send: packet => sent.push(packet)};
  game.peers.add(peer);
  const second = game.gameplayState(resumed).job.target;
  peer.state.x = second.x; peer.state.y = second.y;
  game.action(resumed, 'job.checkpoint', {});
  const last = game.gameplayState(resumed).job.target;
  peer.state.x = last.x; peer.state.y = last.y;
  assert.throws(() => game.action(resumed, 'job.checkpoint', {}), /No intermediate/);
  resumed.job.started = Date.now() - 3100;
  const finished = game.action(resumed, 'job.complete', {});
  assert.equal(finished.state.job, null);
  assert.equal(resumed.cash, 400);
  assert.equal(resumed.xp, 80);
  assert.equal(resumed.jobsDone, 1);
  assert.equal(game.vehicles.has(scooterId), false);
  assert(sent.some(packet => packet.t === 'vgone' && packet.id === scooterId));

  const cancelled = game.action(resumed, 'job.start', {job: 'pizza'});
  const cancelledId = resumed.job.vehicleId;
  assert(cancelled.state.job);
  game.action(resumed, 'job.cancel', {});
  assert.equal(game.vehicles.has(cancelledId), false);
  const expiring = game.action(resumed, 'job.start', {job: 'pizza'});
  const expiredId = resumed.job.vehicleId;
  assert(expiring.state.job);
  resumed.job.started = Date.now() - 361000;
  game.flushSync();
  clearInterval(game.tick);
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  assert.equal(game.players.get(id).job, null, 'expired pizza work is discarded on restart');
  assert.equal(game.vehicles.has(expiredId), false);
  clearInterval(game.tick);
  console.log('PASS: pizza scooter ownership, ordered deliveries, restart recovery, payout, cancellation and expiry');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
