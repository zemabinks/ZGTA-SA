#!/usr/bin/env node
// Isolated group convoy bonus, privacy, and saved bonus state.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-convoy-'));
try {
  const local = path.join(temporary, 'local-only', 'selfhost');
  fs.mkdirSync(local, {recursive: true});
  for (const file of ['selfhost_backend.js', 'optional_discord.js'])
    fs.copyFileSync(path.join(__dirname, file), path.join(temporary, file));
  fs.copyFileSync(path.join(__dirname, 'local-only', 'selfhost', 'client-catalog.json'),
    path.join(local, 'client-catalog.json'));
  const backend = path.join(temporary, 'selfhost_backend.js');
  let game = require(backend);
  const make = () => {
    const {id, player} = game.ensurePlayer({headers: {cookie: ''}}, {setHeader() {}});
    const sent = [];
    const peer = {player, ready: true, lastSeen: Date.now(),
      state: {walking: true, x: 1480, y: -1738, z: 13},
      send: packet => sent.push(packet)};
    game.peers.add(peer);
    return {id, player, peer, sent};
  };
  const a = make(), b = make(), outsider = make();
  game.action(a.player, 'party.create', {});
  game.action(a.player, 'party.invite', {number: b.player.number});
  game.action(b.player, 'party.accept', {});
  for (const driver of [a, b, outsider]) {
    game.action(driver.player, 'job.start', {job: 'trucker'});
    const pickup = game.gameplayState(driver.player).job.target;
    driver.peer.state = {driving: true, x: pickup.x, y: pickup.y, z: 13,
      car: '414.25.1.0.', vehicle: driver.player.job.vehicleId};
    game.action(driver.player, 'job.pickup', {});
    driver.player.job.started = Date.now() - 3100;
  }
  assert.equal(a.player.job.drop, b.player.job.drop);
  const target = game.gameplayState(a.player).job.target;
  for (const driver of [a, b, outsider]) {
    driver.peer.state.x = target.x;
    driver.peer.state.y = target.y;
  }
  const first = game.action(a.player, 'job.complete', {});
  assert.match(first.message, /convoy bonus/);
  assert.equal(a.player.cash, 600);
  assert.equal(a.player.xp, 120);
  assert.equal(b.player.cash, 100, 'group mate receives the shared bonus immediately');
  assert.equal(b.player.xp, 20);
  assert.equal(b.player.job.bonusAwarded, true);
  assert(b.sent.some(packet => packet.t === 'note' && /Convoy bonus/.test(packet.text)));
  assert.equal(outsider.player.cash, 0, 'a nearby outsider gets no convoy bonus');

  game.flushSync(); clearInterval(game.tick);
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  const restored = game.players.get(b.id);
  assert.equal(restored.job.bonusAwarded, true, 'paid bonus survives restart');
  assert.equal(restored.cash, 100);
  const peer = {player: restored, ready: true, lastSeen: Date.now(),
    state: {driving: true, x: target.x, y: target.y, z: 13,
      car: '414.25.1.0.', vehicle: restored.job.vehicleId}, send() {}};
  game.peers.add(peer);
  const second = game.action(restored, 'job.complete', {});
  assert.doesNotMatch(second.message, /convoy bonus/);
  assert.equal(restored.cash, 600);
  assert.equal(restored.xp, 120);
  assert.equal(restored.jobsDone, 1);
  clearInterval(game.tick);
  console.log('PASS: private convoy reward, outsider exclusion, one-time payout and restart persistence');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
