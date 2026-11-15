#!/usr/bin/env node
// Isolated staged mechanic repair, interruption, restart and payout checks.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-mechanic-'));
try {
  const local = path.join(temporary, 'local-only', 'selfhost');
  fs.mkdirSync(local, {recursive: true});
  for (const file of ['selfhost_backend.js', 'optional_discord.js', 'weapon_inventory.js', 'world_collision.js', 'local_projectiles.js'])
    fs.copyFileSync(path.join(__dirname, file), path.join(temporary, file));
  fs.copyFileSync(path.join(__dirname, 'local-only', 'selfhost', 'client-catalog.json'),
    path.join(local, 'client-catalog.json'));
  const backend = path.join(temporary, 'selfhost_backend.js');
  let game = require(backend);
  clearInterval(game.tick);
  const {id, player} = game.ensurePlayer({headers: {cookie: ''}}, {setHeader() {}});
  const state = {walking: true, x: 1480, y: -1738, z: 13};
  const peer = {player, ready: true, lastSeen: Date.now(), state, send() {}};
  game.peers.add(peer);
  game.action(player, 'job.start', {job: 'mechanic'});
  const missionId = player.job.vehicleId;
  assert.equal(game.vehicles.get(missionId).row[9], 350);
  assert.throws(() => game.action(player, 'job.complete', {}), /recently|stranded/);
  const target = game.gameplayState(player).job.target;
  state.x = target.x; state.y = target.y;
  const advance = count => {
    for (let i = 0; i < count; i++) {
      if (!peer.player.job) break;
      peer.player.job.repairTick = Date.now() - 300;
      game.mechanicTick();
    }
  };
  advance(5);
  assert.equal(player.job.repairStep, 0);
  assert(player.job.repairProgress > 0);
  state.x += 20;
  advance(1);
  assert.equal(player.job.repairProgress, 0, 'moving away interrupts the current stage');
  state.x = target.x;
  advance(11);
  assert.equal(player.job.repairStep, 1);
  assert.equal(game.gameplayState(player).job.repairPart, 'tyres');
  player.job.started = Date.now() - 20000;
  assert.throws(() => game.action(player, 'job.complete', {}), /engine, tyres, and bodywork/);
  game.flushSync();
  fs.unlinkSync(path.join(temporary, 'local-only', 'selfhost', 'players.json.lock'));
  delete require.cache[require.resolve(backend)];
  game = require(backend);
  clearInterval(game.tick);
  const resumed = game.players.get(id);
  assert.equal(resumed.job.repairStep, 1);
  assert(game.vehicles.has(missionId));
  peer.player = resumed;
  game.peers.add(peer);
  advance(11);
  assert.equal(resumed.job.repairStep, 2);
  assert.equal(game.gameplayState(resumed).job.repairPart, 'bodywork');
  advance(11);
  advance(1);
  assert.equal(resumed.job, null, 'the finished repair pays automatically');
  assert.equal(resumed.cash, 350);
  assert.equal(resumed.xp, 70);
  assert(!game.vehicles.has(missionId));
  console.log('PASS: staged roadside repair, interruption, restart and automatic payout');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
