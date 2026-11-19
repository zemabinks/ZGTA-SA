#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Registration/index regression using authored opaque pack bytes. No listener,
// original recordings, decoder, browser or device is needed by this test.
'use strict';
const fs = require('node:fs'), path = require('node:path'), assert = require('node:assert/strict');
const {Writable} = require('node:stream');
const {spawnSync} = require('node:child_process');
const {create, register, locations} = require('../../native_radio_server');
const {createHandler, configuredHandler} = require('../../serve_development_radio');
const {HEADER} = require('../../radio_streams');

async function main() {
  const output = path.resolve(process.argv[2] || path.join(require('node:path').resolve(__dirname, '../..'), 'local-only/research/radio-development-test-' + process.hrtime.bigint()));
  const privateRoot = path.join(require('node:path').resolve(__dirname, '../..'), 'local-only') + path.sep;
  assert(output.startsWith(privateRoot), 'Use a new ignored local-only output');
  let parent = path.dirname(output);
  while (parent !== path.dirname(parent)) {
    if (fs.existsSync(parent)) assert(!fs.lstatSync(parent).isSymbolicLink(), 'Test output cannot use linked ancestors');
    parent = path.dirname(parent);
  }
  fs.mkdirSync(output, {recursive: false});
  let checks = 0;
  function check(value, message) { assert(value, message); checks++; }
  function pack(directory, name) {
    fs.mkdirSync(path.join(directory, 'audio/config'), {recursive: true});
    fs.mkdirSync(path.join(directory, 'audio/streams'), {recursive: true});
    const names = Buffer.alloc(16); names.write(name);
    const lookup = Buffer.alloc(12); lookup.writeUInt32LE(HEADER + 32, 8);
    fs.writeFileSync(path.join(directory, 'audio/config/StrmPaks.dat'), names);
    fs.writeFileSync(path.join(directory, 'audio/config/TrakLkup.dat'), lookup);
    fs.writeFileSync(path.join(directory, 'audio/streams', name), Buffer.alloc(HEADER + 32, 0x39));
  }
  const owner = path.join(output, 'authored-owner'), second = path.join(output, 'authored-second-owner');
  pack(owner, 'CH'); pack(second, 'CO');
  const localOnly = path.join(output, 'host'); fs.mkdirSync(localOnly);
  const siteTarget = path.join(output, 'immutable-site'); fs.mkdirSync(siteTarget);
  fs.writeFileSync(path.join(siteTarget, 'keep'), 'unchanged');
  fs.symlinkSync(siteTarget, path.join(localOnly, 'site'), 'dir');
  const server = create({localOnly});
  check(server.index().stations.length === 0, 'Absent registration produces no invented tracks');
  const result = register(owner, {localOnly});
  check(result.tracks === 1 && result.audioCopied === false, 'Registration discovers authored source without copying audio');
  check(result.configuration === locations(localOnly).configuration, 'Default registration is outside site alias');
  check((fs.statSync(result.configuration).mode & 0o777) === 0o600, 'Owner registration is private');
  check(server.index().stations[1].length === 1, 'Running helper discovers new preferred registration');
  check(fs.readdirSync(siteTarget).join() === 'keep' && fs.readFileSync(path.join(siteTarget, 'keep'), 'utf8') === 'unchanged', 'Read-only asset alias target receives no writes');
  check(!fs.existsSync(locations(localOnly).cache), 'Index/registration do not predecode audio');
  const before = fs.readFileSync(result.configuration);
  assert.throws(() => register(second, {localOnly}), /EEXIST/); checks++;
  check(fs.readFileSync(result.configuration).equals(before), 'Existing registration is preserved');
  const explicit = path.join(output, 'explicit/owner.json'); register(second, {configuration: explicit});
  check(create({localOnly, configuration: explicit}).index().stations[2].length === 1, 'Explicit QA registration selects its source');
  check(create({localOnly, configuration: path.join(output, 'absent.json')}).index().stations.length === 0, 'Explicit missing registration does not borrow a default owner');
  const broken = path.join(output, 'broken-local'); fs.mkdirSync(path.join(broken, 'site/game/radio'), {recursive: true});
  fs.writeFileSync(locations(broken).legacyConfiguration, JSON.stringify({directory: owner}));
  const legacy = create({localOnly: broken});
  check(legacy.index().stations[1].length === 1, 'Legacy owner registration remains readable');
  register(second, {localOnly: broken});
  check(legacy.index().stations[2].length === 1, 'Preferred registration supersedes legacy source');
  fs.writeFileSync(locations(broken).configuration, '{invalid');
  assert.throws(() => legacy.index(), SyntaxError); checks++;
  const target = path.join(output, 'do-not-modify.json'); fs.writeFileSync(target, 'keep');
  const linked = path.join(output, 'linked.json'); fs.symlinkSync(target, linked);
  assert.throws(() => register(owner, {configuration: linked}), /linked path/); checks++;
  assert.throws(() => register(owner, {configuration: path.join(localOnly, 'site/forbidden/owner.json')}), /linked path/); checks++;
  check(fs.readFileSync(target, 'utf8') === 'keep' && !fs.existsSync(path.join(siteTarget, 'forbidden')), 'Linked registration refusal leaves targets unchanged');
  const invalidOutput = path.join(output, 'invalid-source/owner.json');
  const emptyOwner = path.join(output, 'empty-owner'); fs.mkdirSync(emptyOwner);
  assert.throws(() => register(emptyOwner, {configuration: invalidOutput}), /no audio\/config/); checks++;
  check(!fs.existsSync(path.dirname(invalidOutput)), 'Invalid source is rejected before output creation');
  const cliConfiguration = path.join(output, 'cli/owner.json');
  const cli = spawnSync(process.execPath, [path.join(require('node:path').resolve(__dirname, '../..'), 'native_radio_server.js'), owner, '--configuration', cliConfiguration], {encoding: 'utf8'});
  check(cli.status === 0 && JSON.parse(cli.stdout).tracks === 1 && fs.existsSync(cliConfiguration), 'CLI explicit registration is functional');
  const cliRepeat = spawnSync(process.execPath, [path.join(require('node:path').resolve(__dirname, '../..'), 'native_radio_server.js'), second, '--configuration', cliConfiguration], {encoding: 'utf8'});
  check(cliRepeat.status !== 0 && JSON.parse(fs.readFileSync(cliConfiguration)).directory === owner, 'CLI cannot silently replace another source');
  async function request(helper) {
    const bytes = []; let status;
    const response = new Writable({write(data, encoding, done) { bytes.push(data); done(); }});
    response.writeHead = (value) => {status = value; response.headersSent = true;};
    const finished = new Promise(resolve => response.on('finish', resolve));
    check(await helper.handle({method: 'GET', headers: {}}, response, '/game/radio/native/index'), 'Index is handled without opening a network listener');
    await finished; return {status, body: Buffer.concat(bytes).toString()};
  }
  const success = await request(server);
  check(success.status === 200 && !success.body.includes(output) && JSON.parse(success.body).stations[1][0].url.startsWith('/game/radio/native/track/'), 'Client index has same-origin URLs and no owner path');
  const failure = await request(legacy);
  check(failure.status === 503 && failure.body === 'Owner radio audio is unavailable', 'Malformed preferred source fails closed without exposing private paths');
  const token = 'a'.repeat(64), port = 28001;
  const isolated = createHandler({radio: server, token, port});
  async function isolatedRequest(url, options = {}) {
    const chunks = []; let status;
    const response = new Writable({write(data, encoding, done) {chunks.push(data); done();}});
    response.writeHead = value => {status = value; response.headersSent = true;};
    const finished = new Promise(resolve => response.on('finish', resolve));
    await isolated({url, method: options.method || 'GET', headers: {host: options.host || `127.0.0.1:${port}`, 'x-zgta-radio-token': options.token ?? token}}, response);
    await finished; return {status, body: Buffer.concat(chunks)};
  }
  check((await isolatedRequest('/game/radio/native/index')).status === 200, 'Token-authenticated isolated index works');
  const head = await isolatedRequest('/game/radio/native/index', {method: 'HEAD'});
  check(head.status === 200 && head.body.length === 0, 'Isolated HEAD has no body');
  for (const invalid of ['', 'b'.repeat(64), 'a'.repeat(63)]) check((await isolatedRequest('/game/radio/native/index', {token: invalid})).status === 403, 'Isolated helper refuses missing/incorrect token');
  check((await isolatedRequest('/game/radio/native/index', {host: 'untrusted.example'})).status === 403, 'Isolated helper rejects unexpected Host');
  check((await isolatedRequest('/game/radio/native/index', {method: 'POST'})).status === 405, 'Isolated helper accepts read methods only');
  for (const url of ['/game/state', '/game/native/resource-manifest.json', '/game/radio/custom/song.mp3', '/', 'http://127.0.0.1:28001/game/radio/native/index'])
    check((await isolatedRequest(url)).status === 404, 'Isolated helper refuses non-allowlisted route');
  check((await isolatedRequest('/game/radio/native/track/99999.wav?v=revision')).status === 404, 'Allowed track route still requires a catalogued recording');
  const tokenFile = path.join(output, 'authored-token'), unusedDecoder = path.join(output, 'authored-not-run-decoder');
  fs.writeFileSync(tokenFile, token, {mode: 0o600});
  fs.writeFileSync(unusedDecoder, '#!/bin/sh\nexit 1\n', {mode: 0o700});
  const environment = {ZGTA_RADIO_CONFIGURATION: result.configuration, ZGTA_RADIO_CACHE: path.join(output, 'isolated-cache'), ZGTA_RADIO_DECODER: unusedDecoder, ZGTA_RADIO_TOKEN_FILE: tokenFile};
  check(typeof configuredHandler(environment, port) === 'function' && !fs.existsSync(environment.ZGTA_RADIO_CACHE), 'Isolated setup validates configuration without decoding or opening a listener');
  assert.throws(() => configuredHandler({...environment, ZGTA_RADIO_CONFIGURATION: 'relative.json'}, port), /absolute/); checks++;
  fs.chmodSync(tokenFile, 0o644);
  assert.throws(() => configuredHandler(environment, port), /owner-only/); checks++;
  fs.chmodSync(tokenFile, 0o600);
  assert.throws(() => configuredHandler({...environment, ZGTA_RADIO_DECODER: linked}, port), /regular ancestors/); checks++;
  fs.writeFileSync(environment.ZGTA_RADIO_CACHE, 'keep');
  assert.throws(() => configuredHandler(environment, port), /cache directory/); checks++;
  check(fs.readFileSync(environment.ZGTA_RADIO_CACHE, 'utf8') === 'keep', 'Invalid isolated cache is preserved');
  const report = {passed: true, checks, output, scope: 'Authored opaque-pack registration/index tests; no audio decode, network listener or device playback'};
  fs.writeFileSync(path.join(output, 'report.json'), JSON.stringify(report, null, 2) + '\n');
  console.log(JSON.stringify(report));
}
main().catch(error => {console.error(error); process.exitCode = 1;});
