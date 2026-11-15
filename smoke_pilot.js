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
  for (const file of ['selfhost_backend.js', 'optional_discord.js', 'weapon_inventory.js', 'world_collision.js', 'local_projectiles.js'])
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
  assert.throws(() => game.action(player, 'job.start', {job: 'pilot', model: 511}),
    /level 4/);
  assert.equal(game.gameplayState(player).pilot.level, 1);
  assert.equal(game.gameplayState(player).pilot.aircraft.find(item => item.model === 511).unlocked, false);

  const begun = game.action(player, 'job.start', {job: 'pilot'});
  assert.equal(begun.state.job.mode, 'flight');
  assert.equal(begun.state.job.stage, 'takeoff');
  assert.equal(player.job.from, 'ls');
  assert.equal(player.job.to, 'sf');
  assert(begun.state.job.secondsLeft > 0 && begun.state.job.secondsLeft <= 600);
  const planeId = player.job.vehicleId;
  assert.equal(game.vehicles.get(planeId).row[2], '593.1.1.0.');
  const spawn = game.vehicles.get(planeId).row;
  assert(sent.some(packet => packet.t === 'tp' &&
    Math.hypot(packet.x - spawn[3], packet.y - spawn[4]) <= 8));
  assert(Math.abs(spawn[6] - Math.PI / 2) < 0.01,
    'the loaner faces the Los Santos runway');
  assert(sent.some(packet => packet.t === 'spawned' && packet.v[0] === planeId));
  assert(otherSent.some(packet => packet.t === 'spawned' && packet.v[0] === planeId));
  game.onMessage(otherPeer, {t: 'enter', v: planeId});
  assert(otherSent.some(packet => packet.t === 'enter' && packet.v === planeId && !packet.ok));
  player.job.started = Date.now() - 3100;
  assert.throws(() => game.action(player, 'job.complete', {}), /Take off/);
  const from = [spawn[3], spawn[4], spawn[5] - 1.1];
  game.onMessage(peer, {t: 'me', driving: true, car: '593.1.1.0.', vehicle: 'wrong',
    x: from[0], y: from[1], z: from[2] + 45, speed: 20});
  assert.equal(player.job.stage, 'takeoff', 'another aircraft cannot count as takeoff');
  game.onMessage(peer, {t: 'me', driving: true, car: '593.1.1.0.', vehicle: planeId,
    x: from[0], y: from[1], z: from[2] + 45, speed: 20, health: 1000});
  assert.equal(player.job.stage, 'landing');
  assert.equal(player.job.reportedHealth, true);
  assert.equal(player.job.minHealth, 1000);
  assert(sent.some(packet => packet.t === 'note' && /Airborne/.test(packet.text)));
  game.flushSync(); clearInterval(game.tick);
  fs.unlinkSync(path.join(local, 'players.json.lock'));
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  const resumed = game.players.get(id);
  assert.equal(resumed.job.stage, 'landing');
  assert.equal(resumed.job.landingSince, null);
  assert.equal(resumed.job.reportedHealth, true);
  assert.equal(game.vehicles.get(planeId).row[2], '593.1.1.0.');
  sent = [];
  peer = {player: resumed, ready: true, lastSeen: Date.now(),
    state: {driving: true, car: '593.1.1.0.', vehicle: planeId,
      x: from[0], y: from[1], z: from[2] + 45, speed: 20},
    send: packet => sent.push(packet)};
  game.peers.add(peer);
  assert.throws(() => game.action(resumed, 'job.complete', {}), /destination apron/);
  const to = [begun.state.job.target.x, begun.state.job.target.y, airport('sf').stand[2]];
  game.onMessage(peer, {t: 'me', driving: true, car: '593.1.1.0.', vehicle: planeId,
    x: to[0], y: to[1], z: to[2] + 2, speed: 0});
  assert(resumed.job.landingSince);
  assert.throws(() => game.action(resumed, 'job.complete', {}), /two seconds/);
  resumed.job.landingSince -= 2100;
  peer.state.vehicle = 'wrong';
  assert.throws(() => game.action(resumed, 'job.complete', {}), /marked Dodo/);
  peer.state.vehicle = planeId;
  resumed.pilotStreak = 4;
  resumed.pilotFlights = 4;
  const finished = game.action(resumed, 'job.complete', {});
  assert.equal(finished.state.job, null);
  assert.equal(resumed.cash, 1450);
  assert.equal(resumed.xp, 290);
  assert.equal(resumed.pilotFlights, 5);
  assert.equal(resumed.pilotStreak, 5);
  assert.match(finished.message, /smooth flight, early landing, fifth flight/);
  assert.equal(resumed.jobsDone, 1);
  assert.equal(game.vehicles.has(planeId), false);
  assert(sent.some(packet => packet.t === 'vgone' && packet.id === planeId));

  game.action(resumed, 'job.start', {job: 'pilot'});
  const damagedId = resumed.job.vehicleId;
  const nextSpawn = game.vehicles.get(damagedId).row;
  const nextFrom = [nextSpawn[3], nextSpawn[4], nextSpawn[5] - 1.1];
  const nextTarget = game.gameplayState(resumed).job.target;
  const nextTo = [nextTarget.x, nextTarget.y, airport(resumed.job.to).stand[2]];
  resumed.job.started = Date.now() - 540000;
  game.onMessage(peer, {t: 'me', driving: true, car: '593.1.1.0.', vehicle: damagedId,
    x: nextFrom[0], y: nextFrom[1], z: nextFrom[2] + 40, speed: 20, health: 700});
  assert.equal(resumed.job.minHealth, 700);
  game.onMessage(peer, {t: 'me', driving: true, car: '593.1.1.0.', vehicle: damagedId,
    x: nextTo[0], y: nextTo[1], z: nextTo[2] + 2, speed: 0, health: 800});
  assert.equal(resumed.job.minHealth, 700, 'later health report cannot restore smooth status');
  resumed.job.landingSince -= 2100;
  const damagedFinish = game.action(resumed, 'job.complete', {});
  assert.equal(resumed.cash, 2150);
  assert.equal(resumed.xp, 430);
  assert.equal(resumed.pilotFlights, 6);
  assert.equal(resumed.pilotStreak, 6);
  assert(!/pilot bonus/.test(damagedFinish.message));

  game.action(resumed, 'job.start', {job: 'pilot'});
  const cancelledId = resumed.job.vehicleId;
  game.action(resumed, 'job.cancel', {});
  assert.equal(game.vehicles.has(cancelledId), false);
  assert.equal(resumed.pilotStreak, 0);
  game.action(resumed, 'job.start', {job: 'pilot'});
  const expiredId = resumed.job.vehicleId;
  resumed.pilotStreak = 2;
  resumed.job.started = Date.now() - 601000;
  game.flushSync(); clearInterval(game.tick);
  fs.unlinkSync(path.join(local, 'players.json.lock'));
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  assert.equal(game.players.get(id).job, null);
  assert.equal(game.players.get(id).pilotStreak, 0);
  assert.equal(game.players.get(id).pilotFlights, 6);
  assert.equal(game.vehicles.has(expiredId), false);
  const unlocked = game.players.get(id);
  unlocked.pilotFlights = 9;
  const airportPeer = {player: unlocked, ready: true, lastSeen: Date.now(),
    state: {walking: true, x: 1480, y: -1738, z: 13}, send() {}};
  game.peers.add(airportPeer);
  assert.equal(game.gameplayState(unlocked).pilot.level, 4);
  assert.equal(game.gameplayState(unlocked).pilot.aircraft.find(item => item.model === 511).unlocked, true);
  const beagle = game.action(unlocked, 'job.start', {job: 'pilot', model: 511});
  assert.equal(beagle.state.job.plane, 'Beagle');
  assert.equal(beagle.state.job.radius, 75);
  const beagleId = unlocked.job.vehicleId;
  const beagleCode = game.vehicles.get(beagleId).row[2];
  assert.equal(beagleCode.split('.')[0], '511');
  unlocked.job.started = Date.now() - 3100;
  const beagleSpawn = game.vehicles.get(beagleId).row;
  const beagleFrom = [beagleSpawn[3], beagleSpawn[4], beagleSpawn[5] - 1.1];
  const beagleTarget = game.gameplayState(unlocked).job.target;
  const beagleTo = [beagleTarget.x, beagleTarget.y, airport(unlocked.job.to).stand[2]];
  game.onMessage(airportPeer, {t: 'me', driving: true, car: beagleCode,
    vehicle: beagleId, x: beagleFrom[0], y: beagleFrom[1],
    z: beagleFrom[2] + 40, speed: 20, health: 1000});
  game.onMessage(airportPeer, {t: 'me', driving: true, car: beagleCode,
    vehicle: beagleId, x: beagleTo[0] + 73, y: beagleTo[1],
    z: beagleTo[2] + 2, speed: 0, health: 1000});
  unlocked.job.landingSince -= 2100;
  const beagleFinished = game.action(unlocked, 'job.complete', {});
  assert.match(beagleFinished.message, /Beagle aircraft/);
  assert.equal(unlocked.cash, 3250);
  assert.equal(unlocked.xp, 650);
  assert.equal(unlocked.pilotFlights, 10);
  clearInterval(game.tick);
  console.log('PASS: pilot unlocks, aircraft, landing hold, bonuses, streak, restart and expiry');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
