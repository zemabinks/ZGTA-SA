#!/usr/bin/env node
// No live Discord account or network is used. Verify the OAuth boundary and
// one-time account reward with a mocked provider in an isolated directory.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const OptionalDiscord = require('./optional_discord');

const config = {clientId: '123456789012345678', clientSecret: 'test-secret-only',
  redirectUri: 'http://127.0.0.1:8766/api/local/discord/callback'};
const userId = '987654321098765432';
const calls = [];
const fetcher = async (url, options) => {
  calls.push({url, options});
  if (url.endsWith('/oauth2/token')) {
    assert.equal(options.method, 'POST');
    assert.equal(options.body.get('client_secret'), config.clientSecret);
    assert.equal(options.body.get('code'), 'valid-code');
    assert(options.body.get('code_verifier'));
    return {ok: true, json: async () => ({token_type: 'Bearer', access_token: 'temporary-token',
      scope: 'identify'})};
  }
  assert.equal(url, 'https://discord.com/api/v10/users/@me');
  assert.equal(options.headers.Authorization, 'Bearer temporary-token');
  return {ok: true, json: async () => ({id: userId, username: 'Verified player'})};
};

function response() {
  return {status: null, headers: {}, setHeader(key, value) {this.headers[key] = value;},
    writeHead(status, headers) {this.status = status; Object.assign(this.headers, headers);},
    end(body) {this.body = body;}};
}

async function main() {
  const disabled = new OptionalDiscord();
  assert.equal(disabled.enabled, false);
  assert.throws(() => disabled.start('player'));
  const auth = new OptionalDiscord(config, fetcher);
  const url = new URL(auth.start('player-one'));
  assert.equal(url.origin, 'https://discord.com');
  assert.equal(url.searchParams.get('scope'), 'identify');
  assert.equal(url.searchParams.get('code_challenge_method'), 'S256');
  assert(!url.href.includes(config.clientSecret));
  const state = url.searchParams.get('state');
  await assert.rejects(auth.finish({state, code: 'valid-code', iss: 'https://discord.com',
    playerId: 'different-player'}));
  assert.equal(calls.length, 0, 'a mismatched player cannot reach the provider');
  const valid = new URL(auth.start('player-one'));
  const secondState = valid.searchParams.get('state');
  const identity = await auth.finish({state: secondState, code: 'valid-code',
    iss: 'https://discord.com', playerId: 'player-one'});
  assert.deepEqual(identity, {id: userId, name: 'Verified player'});
  const challenge = crypto.createHash('sha256')
    .update(calls[0].options.body.get('code_verifier')).digest('base64url');
  assert.equal(challenge, valid.searchParams.get('code_challenge'));
  await assert.rejects(auth.finish({state: secondState, code: 'valid-code',
    iss: 'https://discord.com', playerId: 'player-one'}), 'OAuth state is single use');
  assert.equal(calls.length, 2);

  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-discord-'));
  try {
    const selfhost = path.join(temp, 'local-only', 'selfhost');
    fs.mkdirSync(selfhost, {recursive: true});
    fs.writeFileSync(path.join(selfhost, 'client-catalog.json'), '{"vehicles":[],"homes":[]}');
    fs.writeFileSync(path.join(selfhost, 'discord-oauth.json'), JSON.stringify(config));
    for (const file of ['selfhost_backend.js','player_placement.js', 'optional_discord.js', 'weapon_inventory.js', 'world_collision.js', 'local_projectiles.js'])
      fs.copyFileSync(path.join(__dirname, file), path.join(temp, file));
    const game = require(path.join(temp, 'selfhost_backend.js'));
    const first = 'a'.repeat(32), second = 'b'.repeat(32);
    const player = name => ({number: 1, name, cash: 0, xp: 0, jobsDone: 0,
      racesFinished: 0, racesWon: 0, health: 100, armour: 0,
      wanted: 0, wantedUntil: 0, passive: false, passiveWaitUntil: 0,
      kills: 0, deaths: 0, arrests: 0, policeDuty: false,
      gang: null, gangSwitchUntil: 0, turfCaptures: 0,
      discoveries: [], trackedDiscovery: null,
      cars: [], garage: [], homes: [], job: null, discord: null, settings: {}});
    game.players.set(first, player('Guest one'));
    game.players.set(second, player('Guest two'));
    assert.equal(game.gameplayState(game.players.get(first)).discord.available, true);
    const authorize = response();
    game.discordStart({headers: {host: '127.0.0.1:8766', cookie: `zgta_local=${first}`}}, authorize);
    assert.equal(authorize.status, 302);
    assert(new URL(authorize.headers.Location).searchParams.get('state'));
    const wrongHost = response();
    game.discordStart({headers: {host: 'other.example', cookie: `zgta_local=${first}`}}, wrongHost);
    assert.equal(wrongHost.status, 400);
    game.discord.finish = async () => identity;
    const request = id => ({url: '/api/local/discord/callback?state=mock&code=mock&iss=https%3A%2F%2Fdiscord.com',
      headers: {host: '127.0.0.1:8766', cookie: `zgta_local=${id}`}});
    const linked = response();
    await game.discordCallback(request(first), linked);
    assert.equal(linked.status, 302);
    assert.equal(game.players.get(first).cash, 500);
    assert.equal(game.players.get(first).discord.id, userId);
    await game.discordCallback(request(first), response());
    assert.equal(game.players.get(first).cash, 500, 'one identity earns the bonus once');
    const login = response();
    await game.discordCallback(request(second), login);
    assert.equal(login.status, 302);
    assert(login.headers['Set-Cookie'].includes(`zgta_local=${first}`),
      'an already-linked Discord identity signs in to its existing account');
    assert.equal(game.players.get(second).cash, 0);
    game.discord.finish = async () => ({id: '111111111111111111', name: 'Other player'});
    const conflict = response();
    await game.discordCallback(request(first), conflict);
    assert.equal(conflict.status, 400);
    assert.equal(game.players.get(first).cash, 500);
    game.flushSync();
    const saved = fs.readFileSync(path.join(selfhost, 'players.json'), 'utf8');
    assert(!saved.includes('temporary-token') && !saved.includes(config.clientSecret),
      'OAuth secrets and tokens must not be stored with players');
    console.log('PASS: optional Discord state/PKCE, identity verification, one-time bonus, repeat login, and secret-free save');
  } finally {fs.rmSync(temp, {recursive: true, force: true});}
}
main().catch(error => {console.error(error); process.exitCode = 1;});
