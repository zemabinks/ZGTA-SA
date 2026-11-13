#!/usr/bin/env node
// Isolated group heist, wanted escape, cooldown, payout, death and arrest checks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-heist-'));
try {
  const local = path.join(temporary, 'local-only', 'selfhost');
  fs.mkdirSync(local, {recursive: true});
  for (const file of ['selfhost_backend.js', 'optional_discord.js'])
    fs.copyFileSync(path.join(__dirname, file), path.join(temporary, file));
  const catalog = require(path.join(__dirname, 'local-only', 'selfhost', 'client-catalog.json'));
  fs.copyFileSync(path.join(__dirname, 'local-only', 'selfhost', 'client-catalog.json'),
    path.join(local, 'client-catalog.json'));
  const home = id => catalog.homes.find(item => item.key === id);
  const backend = path.join(temporary, 'selfhost_backend.js');
  let game = require(backend);
  const make = () => {
    const {id, player} = game.ensurePlayer({headers: {cookie: ''}}, {setHeader() {}});
    const sent = [];
    const peer = {player, ready: true, lastSeen: Date.now(),
      state: {walking: true, x: 1480, y: -1738, z: 13, health: 100},
      send: packet => sent.push(packet)};
    game.peers.add(peer);
    return {id, player, peer, sent};
  };
  const a = make(), b = make(), outsider = make();
  game.action(a.player, 'party.create', {});
  game.action(a.player, 'party.invite', {number: b.player.number});
  game.action(b.player, 'party.accept', {});
  const start = game.action(a.player, 'job.start', {job: 'heist'});
  assert.equal(start.state.job.mode, 'heist');
  assert.equal(start.state.job.stage, 'plan');
  assert.equal(start.state.job.secondsLeft, 600);
  const carId = a.player.job.vehicleId;
  assert.equal(game.vehicles.get(carId).row[2], '560.52.39.0.');
  assert(b.sent.some(packet => packet.t === 'spawned' && packet.v[0] === carId));
  game.onMessage(outsider.peer, {t: 'enter', v: carId});
  assert(outsider.sent.some(packet => packet.t === 'enter' && packet.v === carId && !packet.ok));
  assert.throws(() => game.action(a.player, 'heist.rob', {}), /on foot/);
  const site = home(a.player.job.site).out;
  a.peer.state = {driving: true, car: '560.52.39.0.', vehicle: carId,
    x: site[0], y: site[1], z: site[2]};
  assert.throws(() => game.action(a.player, 'heist.rob', {}), /on foot/);
  a.peer.state = {walking: true, x: site[0], y: site[1], z: site[2], health: 100};
  b.peer.state = {walking: true, x: site[0] + 2, y: site[1], z: site[2], health: 100};
  outsider.peer.state = {walking: true, x: site[0] + 2, y: site[1], z: site[2], health: 100};
  const robbed = game.action(a.player, 'heist.rob', {});
  assert.equal(robbed.state.job.stage, 'escape');
  assert.equal(a.player.wanted, 2);
  assert.equal(a.player.job.crewIds.length, 1);
  assert.equal(a.player.job.crewIds[0], b.id);
  assert(game.gameplayState(a.player).heistCooldown > 0);
  a.player.job.started = Date.now() - 3100;
  assert.throws(() => game.action(a.player, 'job.complete', {}), /Lose the police/);
  game.flushSync(); clearInterval(game.tick);
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  const leader = game.players.get(a.id), mate = game.players.get(b.id);
  const other = game.players.get(outsider.id);
  assert.equal(leader.job.stage, 'escape');
  assert.deepEqual(leader.job.crewIds, [b.id]);
  assert.equal(leader.wanted, 2);
  assert(game.vehicles.has(carId));
  const drop = home(leader.job.drop).out;
  const leaderPeer = {player: leader, ready: true, lastSeen: Date.now(),
    state: {driving: true, car: '560.52.39.0.', vehicle: carId,
      x: drop[0], y: drop[1], z: drop[2]}, send() {}};
  const matePeer = {player: mate, ready: true, lastSeen: Date.now(),
    state: {walking: true, x: drop[0] + 2, y: drop[1], z: drop[2]}, send() {}};
  const otherPeer = {player: other, ready: true, lastSeen: Date.now(),
    state: {walking: true, x: drop[0] + 2, y: drop[1], z: drop[2]}, send() {}};
  game.peers.add(leaderPeer); game.peers.add(matePeer); game.peers.add(otherPeer);
  game.action(leader, 'party.create', {});
  game.action(leader, 'party.invite', {number: mate.number});
  game.action(mate, 'party.accept', {});
  leaderPeer.state.vehicle = 'wrong';
  game.setWanted(leader, 0);
  assert.throws(() => game.action(leader, 'job.complete', {}), /marked Sultan/);
  leaderPeer.state.vehicle = carId;
  const finish = game.action(leader, 'job.complete', {});
  assert.match(finish.message, /crew bonus/);
  assert.equal(leader.cash, 1100);
  assert.equal(leader.xp, 220);
  assert.equal(mate.cash, 200);
  assert.equal(mate.xp, 40);
  assert.equal(other.cash, 0, 'nearby outsider gets no crew share');
  assert.equal(leader.jobsDone, 1);
  assert(!game.vehicles.has(carId));
  assert.throws(() => game.action(leader, 'job.start', {job: 'heist'}), /Wait .* another heist/);

  leader.heistCooldownUntil = 0;
  leaderPeer.state = {walking: true, x: 1480, y: -1738, z: 13, health: 100};
  game.action(leader, 'job.start', {job: 'heist'});
  const deathCar = leader.job.vehicleId;
  const deathSite = home(leader.job.site).out;
  leaderPeer.state.x = deathSite[0]; leaderPeer.state.y = deathSite[1];
  matePeer.state.x = 1480; matePeer.state.y = -1738;
  game.action(leader, 'heist.rob', {});
  game.onMessage(leaderPeer, {t: 'me', walking: true,
    x: deathSite[0], y: deathSite[1], z: deathSite[2], health: 0});
  assert.equal(leader.job, null, 'death drops the heist bag');
  assert(!game.vehicles.has(deathCar));

  leader.health = 100;
  leader.heistCooldownUntil = 0;
  leaderPeer.state = {walking: true, x: 1480, y: -1738, z: 13, health: 100};
  game.setWanted(leader, 0);
  game.action(leader, 'job.start', {job: 'heist'});
  const arrestCar = leader.job.vehicleId;
  const arrestSite = home(leader.job.site).out;
  leaderPeer.state.x = arrestSite[0]; leaderPeer.state.y = arrestSite[1];
  game.action(leader, 'heist.rob', {});
  mate.policeDuty = true;
  matePeer.state = {walking: true, x: arrestSite[0] + 1,
    y: arrestSite[1], z: arrestSite[2], health: 100};
  game.action(mate, 'police.arrest', {number: leader.number});
  assert.equal(leader.job, null, 'arrest confiscates the heist bag');
  assert.equal(leader.wanted, 0);
  assert(!game.vehicles.has(arrestCar));
  leader.heistCooldownUntil = 0;
  game.action(leader, 'job.start', {job: 'heist'});
  const cancelledCar = leader.job.vehicleId;
  game.action(leader, 'job.cancel', {});
  assert(!game.vehicles.has(cancelledCar));
  assert.equal(leader.heistCooldownUntil, 0, 'planning cancellation has no cooldown');
  game.action(leader, 'job.start', {job: 'heist'});
  const expiredCar = leader.job.vehicleId;
  leader.job.started = Date.now() - 601000;
  game.flushSync(); clearInterval(game.tick);
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  assert.equal(game.players.get(a.id).job, null);
  assert(!game.vehicles.has(expiredCar));
  clearInterval(game.tick);
  console.log('PASS: heist crew, wanted escape, cooldown, restart, death, arrest and expiry');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
