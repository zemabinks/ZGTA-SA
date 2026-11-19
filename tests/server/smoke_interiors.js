#!/usr/bin/env node
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-interiors-'));
try {
  const local = path.join(temporary, 'local-only/selfhost');
  fs.mkdirSync(local, {recursive: true});
  for (const file of ['selfhost_backend.js','player_placement.js', 'optional_discord.js', 'weapon_inventory.js', 'world_collision.js', 'local_projectiles.js'])
    fs.copyFileSync(path.join(require('node:path').resolve(__dirname, '../..'), file), path.join(temporary, file));
  const catalog = require('../../local-only/selfhost/client-catalog.json');
  fs.writeFileSync(path.join(local, 'client-catalog.json'), JSON.stringify(catalog));
  const game = require(path.join(temporary, 'selfhost_backend.js'));
  const {player} = game.ensurePlayer({headers: {cookie: ''}}, {setHeader() {}});
  const sent = [];
  const peer = {player, ready: true, lastSeen: Date.now(),
    state: {walking: true, x: 1480, y: -1738, z: 13}, send: value => sent.push(value)};
  game.peers.add(peer);
  const home = catalog.homes.find(x => x.key === 'elcorona');
  assert.throws(() => game.action(player, 'home.enter', {home: home.key}), /do not own/);
  player.cash = home.price;
  game.action(player, 'home.buy', {home: home.key});
  assert.throws(() => game.action(player, 'home.enter', {home: home.key}), /within 8 m/);
  [peer.state.x, peer.state.y, peer.state.z] = home.out;
  peer.state.walking = false;
  assert.throws(() => game.action(player, 'home.enter', {home: home.key}), /on foot/);
  peer.state.walking = true;
  game.action(player, 'home.enter', {home: home.key});
  const entry = sent.filter(x => x.t === 'tp').at(-1);
  assert.equal(entry.x, catalog.interior_spawns[home.kind][0]);
  assert.equal(game.gameplayState(player).insideHome.id, home.key);
  assert.throws(() => game.action(player, 'home.exit', {}), /Return to/);
  Object.assign(peer.state, {x: entry.x, y: entry.y, z: entry.z});
  game.action(player, 'home.exit', {});
  const exit = sent.filter(x => x.t === 'tp').at(-1);
  assert.deepEqual([exit.x, exit.y, exit.z], home.out.slice(0, 3));
  assert.equal(game.gameplayState(player).insideHome, null);
  assert.throws(() => game.action(player, 'home.exit', {}), /not inside/);
  game.flushSync(); clearInterval(game.tick);
  console.log('PASS: home ownership, entrance distance, on-foot gate, archived interior and exit');
} finally { fs.rmSync(temporary, {recursive: true, force: true}); }
