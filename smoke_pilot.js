#!/usr/bin/env node
// Isolated airport flight, marked aircraft, landing hold, payout, and restart check.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-pilot-'));
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
  const other = game.ensurePlayer({headers: {cookie: ''}}, {setHeader() {}}).player;
  let sent = [], otherSent = [];
  let peer = {player, ready: true, lastSeen: Date.now(),
    state: {walking: true, x: 1480, y: -1738, z: 13},
    send: packet => sent.push(packet)};
  const otherPeer = {player: other, ready: true, lastSeen: Date.now(),
    state: {walking: true, x: 1480, y: -1738, z: 13},
    send: packet => otherSent.push(packet)};
  game.peers.add(peer); game.peers.add(otherPeer);

  const begun = game.action(player, 'job.start', {job: 'pilot'});
  assert.equal(begun.state.job.mode, 'flight');
  assert.equal(begun.state.job.stage, 'takeoff');
  assert.equal(player.job.from, 'ls');
  assert.equal(player.job.to, 'sf');
  assert(begun.state.job.secondsLeft > 0 && begun.state.job.secondsLeft <= 600);
  const planeId = player.job.vehicleId;
  assert.equal(game.vehicles.get(planeId).row[2], '593.1.1.0.');
  assert(sent.some(packet => packet.t === 'tp' && packet.x === airport('ls').stand[0]));
  assert(sent.some(packet => packet.t === 'spawned' && packet.v[0] === planeId));
  assert(otherSent.some(packet => packet.t === 'spawned' && packet.v[0] === planeId));
  game.onMessage(otherPeer, {t: 'enter', v: planeId});
  assert(otherSent.some(packet => packet.t === 'enter' && packet.v === planeId && !packet.ok));
  player.job.started = Date.now() - 3100;
  assert.throws(() => game.action(player, 'job.complete', {}), /Take off/);
  const from = airport('ls').stand;
  game.onMessage(peer, {t: 'me', driving: true, car: '593.1.1.0.', vehicle: 'wrong',
    x: from[0], y: from[1], z: from[2] + 45, speed: 20});
  assert.equal(player.job.stage, 'takeoff', 'another aircraft cannot count as takeoff');
  game.onMessage(peer, {t: 'me', driving: true, car: '593.1.1.0.', vehicle: planeId,
    x: from[0], y: from[1], z: from[2] + 45, speed: 20});
  assert.equal(player.job.stage, 'landing');
  assert(sent.some(packet => packet.t === 'note' && /Airborne/.test(packet.text)));
  game.flushSync(); clearInterval(game.tick);
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  const resumed = game.players.get(id);
  assert.equal(resumed.job.stage, 'landing');
  assert.equal(resumed.job.landingSince, null);
  assert.equal(game.vehicles.get(planeId).row[2], '593.1.1.0.');
  sent = [];
  peer = {player: resumed, ready: true, lastSeen: Date.now(),
    state: {driving: true, car: '593.1.1.0.', vehicle: planeId,
      x: from[0], y: from[1], z: from[2] + 45, speed: 20},
    send: packet => sent.push(packet)};
  game.peers.add(peer);
  assert.throws(() => game.action(resumed, 'job.complete', {}), /destination apron/);
  const to = airport('sf').stand;
  game.onMessage(peer, {t: 'me', driving: true, car: '593.1.1.0.', vehicle: planeId,
    x: to[0], y: to[1], z: to[2] + 2, speed: 0});
  assert(resumed.job.landingSince);
  assert.throws(() => game.action(resumed, 'job.complete', {}), /two seconds/);
  resumed.job.landingSince -= 2100;
  peer.state.vehicle = 'wrong';
  assert.throws(() => game.action(resumed, 'job.complete', {}), /marked Dodo/);
  peer.state.vehicle = planeId;
  const finished = game.action(resumed, 'job.complete', {});
  assert.equal(finished.state.job, null);
  assert.equal(resumed.cash, 700);
  assert.equal(resumed.xp, 140);
  assert.equal(resumed.jobsDone, 1);
  assert.equal(game.vehicles.has(planeId), false);
  assert(sent.some(packet => packet.t === 'vgone' && packet.id === planeId));

  game.action(resumed, 'job.start', {job: 'pilot'});
  const cancelledId = resumed.job.vehicleId;
  game.action(resumed, 'job.cancel', {});
  assert.equal(game.vehicles.has(cancelledId), false);
  game.action(resumed, 'job.start', {job: 'pilot'});
  const expiredId = resumed.job.vehicleId;
  resumed.job.started = Date.now() - 601000;
  game.flushSync(); clearInterval(game.tick);
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  assert.equal(game.players.get(id).job, null);
  assert.equal(game.vehicles.has(expiredId), false);
  clearInterval(game.tick);
  console.log('PASS: pilot aircraft, airborne gate, landing hold, restart, payout and expiry');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
