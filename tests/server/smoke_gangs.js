#!/usr/bin/env node
// Isolated crew, capture, contest, payout, and saved-territory check.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-gangs-'));
try {
  fs.mkdirSync(path.join(temporary, 'local-only', 'selfhost'), {recursive: true});
  for (const file of ['selfhost_backend.js','player_placement.js', 'optional_discord.js', 'weapon_inventory.js', 'world_collision.js', 'local_projectiles.js'])
    fs.copyFileSync(path.join(require('node:path').resolve(__dirname, '../..'), file), path.join(temporary, file));
  fs.copyFileSync(path.join(require('node:path').resolve(__dirname, '../..'), 'local-only', 'selfhost', 'client-catalog.json'),
    path.join(temporary, 'local-only', 'selfhost', 'client-catalog.json'));
  const game = require(path.join(temporary, 'selfhost_backend.js'));
  const make = (x, y) => {
    const sent = [];
    const cookie = {};
    const {player} = game.ensurePlayer({headers: {cookie: ''}}, {setHeader: (key, value) => {cookie[key] = value;}});
    const peer = {player, ready: true, lastSeen: Date.now(),
      state: {walking: true, x, y, z: 13}, send: packet => sent.push(packet)};
    game.peers.add(peer);
    return {player, peer, sent, cookie};
  };
  const green = make(1684.76, -2101.99);
  const violet = make(1700, -2101.99);
  assert(green.cookie['Set-Cookie']);
  assert.equal(game.action(green.player, 'gang.join', {gang: 'green'}).ok, true);
  assert.equal(game.action(violet.player, 'gang.join', {gang: 'violet'}).ok, true);
  assert.throws(() => game.action(green.player, 'gang.join', {gang: 'gold'}), /Wait/);
  assert.throws(() => game.action(green.player, 'turf.start', {turf: 'willowfield'}), /20 m/);
  game.action(green.player, 'turf.start', {turf: 'elcorona'});
  let capture = game.turfCaptures.get('elcorona');
  capture.progress = 29000;
  capture.lastTick = Date.now() - 2000;
  game.lastTurfTick = 0;
  game.turfTick();
  assert.equal(capture.contested, true);
  assert.equal(game.territories.elcorona, null);
  violet.peer.state.x = 1800;
  capture.lastTick = Date.now() - 2000;
  game.lastTurfTick = 0;
  game.turfTick();
  assert.equal(game.territories.elcorona, 'green');
  assert.equal(green.player.cash, 200);
  assert.equal(green.player.xp, 40);
  assert.equal(green.player.turfCaptures, 1);
  assert.equal(violet.player.cash, 0);
  assert.throws(() => game.action(green.player, 'turf.start', {turf: 'elcorona'}), /already controls/);
  assert.throws(() => game.action(green.player, 'money.transfer',
    {number: violet.player.number, amount: 50}), /within 8 m/);
  violet.peer.state.x = 1687;
  assert.throws(() => game.action(green.player, 'money.transfer',
    {number: violet.player.number, amount: 201}), /enough cash/);
  assert.throws(() => game.action(green.player, 'money.transfer',
    {number: violet.player.number, amount: 1.5}), /whole-dollar/);
  game.action(green.player, 'money.transfer', {number: violet.player.number, amount: 50});
  assert.equal(green.player.cash, 150);
  assert.equal(violet.player.cash, 50);
  assert.equal(game.gameplayState(green.player).leaderboard[0].name, green.player.name);
  game.flushSync();
  const saved = JSON.parse(fs.readFileSync(path.join(temporary, 'local-only', 'selfhost', 'players.json')));
  assert.equal(saved.territories.elcorona, 'green');
  assert(Object.values(saved.players).some(player => player.gang === 'green' && player.turfCaptures === 1));
  clearInterval(game.tick);
  console.log('PASS: crews, territory contest and capture, cash transfers, leaderboard, persistence');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
