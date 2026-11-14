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
  game.onMessage(peer, {t: 'me', driving: true, vehicle: cab.id,
    car: cab.row[2], x: 1486, y: -1735, z: 14.1, heading: 0.6, health: 1000});
  assert.equal(cab.row[3], 1486, 'the mission cab follows its native driver');
  game.onMessage(peer, {t: 'me', walking: true, skin: 7,
    vehicle: cab.id, car: cab.row[2], x: 1488, y: -1735, z: 13,
    parked: {x: 1486, y: -1735, z: 14.1, heading: 0.6, health: 1000}});
  assert.equal(cab.row[3], 1486, 'the cab remains parked where the native driver exits');
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
  fs.unlinkSync(path.join(temporary, 'local-only', 'selfhost', 'players.json.lock'));
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
  assert.match(first.message, /Next passenger/);
  assert(game.vehicles.has(cab.id), 'one cab stays out for the whole shift');
  assert.equal(game.gameplayState(peer.player).job.stage, 'pickup');
  assert.equal(game.gameplayState(peer.player).job.fare.shiftFares, 1);
  assert.throws(() => game.action(peer.player, 'job.start', {job: 'taxi'}),
    /Finish or cancel/);
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
  assert.equal(game.gameplayState(peer.player).job.fare.shiftFares, 2);
  assert(game.vehicles.has(cab.id));
  game.flushSync();
  fs.unlinkSync(path.join(temporary, 'local-only', 'selfhost', 'players.json.lock'));
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  clearInterval(game.tick);
  peer.player = game.players.get(id);
  game.peers.add(peer);
  assert.equal(peer.player.cash, 775);
  assert.equal(peer.player.taxiFares, 2);
  assert.equal(peer.player.taxiStreak, 2);
  cab = game.vehicles.get(peer.player.job.vehicleId);
  assert(cab, 'multi-fare shift and cab survive restart');
  assert.equal(game.gameplayState(peer.player).job.fare.shiftFares, 2);
  assert.equal(game.gameplayState(peer.player).job.fare.streakBonus, 100);
  assert.throws(() => game.action(peer.player, 'job.cancel', {}),
    /Get out of the marked cab/);
  place({x: 1480, y: -1738});
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
  fs.unlinkSync(path.join(temporary, 'local-only', 'selfhost', 'players.json.lock'));
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
  assert.equal(game.gameplayState(peer.player).job.fare.shiftFares, 1);
  assert(game.vehicles.has(cab.id));
  assert.throws(() => game.action(peer.player, 'job.cancel', {}),
    /Get out of the marked cab/);
  place(limoDrop);
  game.action(peer.player, 'job.cancel', {});
  assert(!game.vehicles.has(cab.id));
  console.log('PASS: guest cab, multi-fare shift, bonuses, unlockable cabs, streak and restart');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
