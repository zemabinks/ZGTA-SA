#!/usr/bin/env node
// Isolated police patrol route, loaner car, payout, and restart check.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-patrol-'));
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
  let sent = [];
  let peer = {player, ready: true, lastSeen: Date.now(),
    state: {walking: true, x: 1480, y: -1738, z: 13},
    send: packet => sent.push(packet)};
  game.peers.add(peer);
  assert.throws(() => game.action(player, 'job.start', {job: 'patrol'}), /police duty/);
  game.action(player, 'police.duty', {});
  const begun = game.action(player, 'job.start', {job: 'patrol'});
  assert.equal(begun.state.job.mode, 'checkpoints');
  assert.equal(begun.state.job.total, 3);
  const carId = player.job.vehicleId;
  const loaner = game.vehicles.get(carId);
  assert.equal(loaner.row[2], '596.0.1.0.');
  assert(sent.some(packet => packet.t === 'spawned' && packet.v[0] === carId));
  assert.throws(() => game.action(player, 'police.duty', {}), /Finish or cancel/);
  const first = begun.state.job.target;
  peer.state.x = first.x; peer.state.y = first.y;
  assert.throws(() => game.action(player, 'job.checkpoint', {}), /Drive into/);
  peer.state = {walking: false, driving: true, x: first.x, y: first.y, z: 13,
    car: '400.52.39.0.', vehicle: 'wrong'};
  assert.throws(() => game.action(player, 'job.checkpoint', {}), /marked police car/);
  peer.state.car = loaner.row[2]; peer.state.vehicle = carId;
  game.action(player, 'job.checkpoint', {});
  assert.equal(player.job.index, 1);
  game.flushSync();
  clearInterval(game.tick);
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  const resumed = game.players.get(id);
  assert.equal(resumed.job.id, 'patrol');
  assert.equal(resumed.job.index, 1);
  assert.equal(resumed.policeDuty, true);
  assert.equal(game.vehicles.get(carId).row[2], '596.0.1.0.');
  sent = [];
  peer = {player: resumed, ready: true, lastSeen: Date.now(),
    state: {walking: false, driving: true, x: first.x, y: first.y, z: 13,
      car: '596.0.1.0.', vehicle: carId}, send: packet => sent.push(packet)};
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
  assert.equal(game.vehicles.has(carId), false);
  assert(sent.some(packet => packet.t === 'vgone' && packet.id === carId));
  game.action(resumed, 'police.duty', {});
  assert.equal(resumed.policeDuty, false);
  game.flushSync();
  const saved = JSON.parse(fs.readFileSync(path.join(local, 'players.json'))).players[id];
  assert.equal(saved.cash, 400);
  assert.equal(saved.job, null);
  clearInterval(game.tick);
  console.log('PASS: patrol duty gate, marked police car, ordered checkpoints, restart recovery, payout and cleanup');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
