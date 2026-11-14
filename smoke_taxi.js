#!/usr/bin/env node
// Isolated guest cab, fare, bonus, interruption and restart checks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-taxi-'));
try {
  const local = path.join(temporary, 'local-only', 'selfhost');
  fs.mkdirSync(local, {recursive: true});
  for (const file of ['selfhost_backend.js', 'optional_discord.js'])
    fs.copyFileSync(path.join(__dirname, file), path.join(temporary, file));
  fs.copyFileSync(path.join(__dirname, 'local-only', 'selfhost', 'client-catalog.json'),
    path.join(local, 'client-catalog.json'));
  const backend = path.join(temporary, 'selfhost_backend.js');
  let game = require(backend);
  clearInterval(game.tick);
  const {id, player} = game.ensurePlayer({headers: {cookie: ''}}, {setHeader() {}});
  const peer = {player, ready: true, lastSeen: Date.now(),
    state: {walking: true, x: 1480, y: -1738, z: 13}, send() {}};
  game.peers.add(peer);
  const place = (target, cab = null, health = null) => {
    const state = {t: 'me', walking: !cab, driving: !!cab,
      x: target.x, y: target.y, z: 13,
      ...(cab ? {vehicle: cab.id, car: cab.row[2]} : {}),
      ...(health === null ? {} : {health})};
    game.onMessage(peer, state);
  };
  const start = (model = 420) => {
    const result = game.action(peer.player, 'job.start', {job: 'taxi', model});
    assert.equal(result.state.job.stage, 'pickup');
    const cab = game.vehicles.get(peer.player.job.vehicleId);
    assert(cab);
    assert.equal(cab.row[2], {420: '420.6.1.0.', 438: '438.6.1.0.',
      409: '409.1.1.0.'}[model]);
    return cab;
  };
  let cab = start();
  assert.equal(peer.player.cash, 0, 'guest fare needs no car or starting cash');
  const pickup = game.gameplayState(peer.player).job.target;
  place(pickup);
  assert.throws(() => game.action(peer.player, 'job.pickup', {}), /Drive the mission vehicle/);
  place(pickup, {id: 'wrong-car', row: [null, null, cab.row[2]]});
  assert.throws(() => game.action(peer.player, 'job.pickup', {}), /marked cab/);
  place(pickup, cab, 1000);
  game.action(peer.player, 'job.pickup', {});
  assert.equal(game.gameplayState(peer.player).job.stage, 'delivery');
  const drop = game.gameplayState(peer.player).job.target;
  game.flushSync();
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  clearInterval(game.tick);
  peer.player = game.players.get(id);
  game.peers.add(peer);
  cab = game.vehicles.get(peer.player.job.vehicleId);
  assert(cab, 'unfinished loaner cab survives restart');
  assert.equal(peer.player.job.stage, 'delivery');
  assert.equal(peer.player.job.reportedHealth, true);
  peer.player.job.started = Date.now() - 60000;
  peer.player.job.pickedUpAt = Date.now() - 30000;
  place(drop, cab, 1000);
  assert.equal(game.gameplayState(peer.player).job.fare.cleanEligible, true);
  const first = game.action(peer.player, 'job.complete', {});
  assert.match(first.message, /clean ride, quick ride/);
  assert.equal(peer.player.cash, 425);
  assert.equal(peer.player.taxiFares, 1);
  assert.equal(peer.player.taxiStreak, 1);
  assert(!game.vehicles.has(cab.id));
  place(drop);
  cab = start();
  place(game.gameplayState(peer.player).job.target, cab, 700);
  game.action(peer.player, 'job.pickup', {});
  peer.player.job.started = Date.now() - 360000;
  peer.player.job.pickedUpAt = Date.now() - 300000;
  place(game.gameplayState(peer.player).job.target, cab, 700);
  assert.equal(game.gameplayState(peer.player).job.fare.cleanEligible, false);
  const second = game.action(peer.player, 'job.complete', {});
  assert.match(second.message, /fares in a row/);
  assert.doesNotMatch(second.message, /clean ride|quick ride/);
  assert.equal(peer.player.cash, 775);
  assert.equal(peer.player.taxiFares, 2);
  assert.equal(peer.player.taxiStreak, 2);
  game.flushSync();
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  clearInterval(game.tick);
  peer.player = game.players.get(id);
  game.peers.add(peer);
  assert.equal(peer.player.cash, 775);
  assert.equal(peer.player.taxiFares, 2);
  assert.equal(peer.player.taxiStreak, 2);
  place({x: 1480, y: -1738});
  cab = start();
  assert.equal(game.gameplayState(peer.player).job.fare.streakBonus, 100);
  game.action(peer.player, 'job.cancel', {});
  assert.equal(peer.player.taxiStreak, 0);
  assert(!game.vehicles.has(cab.id));
  assert.equal(game.gameplayState(peer.player).taxi.level, 1);
  assert.throws(() => game.action(peer.player, 'job.start', {job: 'taxi', model: 438}),
    /level 8/);
  assert.throws(() => game.action(peer.player, 'job.start', {job: 'taxi', model: 999}),
    /Unknown taxi cab/);
  peer.player.taxiFares = 21;
  assert.equal(game.gameplayState(peer.player).taxi.level, 8);
  cab = start(438);
  assert.equal(game.gameplayState(peer.player).job.fare.cab, 'Cabbie');
  game.action(peer.player, 'job.cancel', {});
  peer.player.taxiFares = 57;
  assert.equal(game.gameplayState(peer.player).taxi.level, 20);
  cab = start(409);
  place(game.gameplayState(peer.player).job.target, cab);
  game.action(peer.player, 'job.pickup', {});
  const limoDrop = game.gameplayState(peer.player).job.target;
  game.flushSync();
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  clearInterval(game.tick);
  peer.player = game.players.get(id);
  game.peers.add(peer);
  cab = game.vehicles.get(peer.player.job.vehicleId);
  assert.equal(cab.row[2], '409.1.1.0.', 'selected limousine survives restart');
  peer.player.job.started = Date.now() - 5000;
  place(limoDrop, cab);
  const premiumFare = game.action(peer.player, 'job.complete', {});
  assert.match(premiumFare.message, /\$200 taxi bonus \(Limousine fare\)/);
  assert.equal(peer.player.cash, 1275);
  console.log('PASS: guest cab, marked fare, bonuses, unlockable cabs, streak and restart');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
