#!/usr/bin/env node
// Isolated exploration-location, payout, and persistence check.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');

const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-explore-'));
try {
  fs.mkdirSync(path.join(temporary, 'local-only', 'selfhost'), {recursive: true});
  for (const file of ['selfhost_backend.js', 'optional_discord.js'])
    fs.copyFileSync(path.join(__dirname, file), path.join(temporary, file));
  fs.copyFileSync(path.join(__dirname, 'local-only', 'selfhost', 'client-catalog.json'),
    path.join(temporary, 'local-only', 'selfhost', 'client-catalog.json'));
  const backend = path.join(temporary, 'selfhost_backend.js');
  const game = require(backend);
  const {player} = game.ensurePlayer({headers: {cookie: ''}}, {setHeader() {}});
  const sent = [];
  const peer = {player, ready: true, lastSeen: Date.now(),
    state: {walking: true, x: 1480, y: -1738, z: 13},
    send: message => sent.push(message)};
  game.peers.add(peer);
  const initial = game.gameplayState(player).exploration;
  assert.equal(initial.found, 0);
  assert.equal(initial.total, 12);
  const first = initial.items[0];
  game.action(player, 'explore.track', {id: first.id});
  assert.equal(game.gameplayState(player).exploration.tracked.id, first.id);
  assert.throws(() => game.action(player, 'explore.claim', {}), /within 12 m/);
  peer.state.x = first.x; peer.state.y = first.y; peer.state.walking = false;
  assert.throws(() => game.action(player, 'explore.claim', {}), /on foot/);
  peer.state.walking = true;
  game.action(player, 'explore.claim', {});
  assert.equal(player.cash, 75);
  assert.equal(player.xp, 20);
  assert.equal(game.gameplayState(player).exploration.tracked, null);
  assert.throws(() => game.action(player, 'explore.claim', {id: first.id}), /already found/);
  for (const place of initial.items.slice(1)) {
    peer.state.x = place.x; peer.state.y = place.y;
    game.action(player, 'explore.claim', {id: place.id});
  }
  assert.equal(player.discoveries.length, 12);
  assert.equal(player.cash, 1400);
  assert.equal(player.xp, 340);
  assert(sent.some(packet => packet.t === 'note' && packet.text.includes('Trail complete')));
  game.flushSync();
  const saved = JSON.parse(fs.readFileSync(path.join(temporary, 'local-only', 'selfhost', 'players.json')));
  assert(Object.values(saved.players).some(entry => entry.discoveries?.length === 12 &&
    entry.cash === 1400 && entry.xp === 340));
  clearInterval(game.tick);
  delete require.cache[require.resolve(backend)];
  const restored = require(backend);
  assert([...restored.players.values()].some(entry => entry.discoveries.length === 12));
  clearInterval(restored.tick);
  console.log('PASS: exploration distance and on-foot checks, duplicate denial, completion bonus, restart persistence');
} finally {
  fs.rmSync(temporary, {recursive: true, force: true});
}
