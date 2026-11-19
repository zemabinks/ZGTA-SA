#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Authored Ogg metadata carriers exercise the actual radio handler. They are
// deliberately not playable recordings, and need no listener, codec or device.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const crypto = require('node:crypto');
const {Writable} = require('node:stream');
const {EventEmitter} = require('node:events');
const {create, register, matches} = require('../../native_radio_server');
const {HEADER, KEY} = require('../../radio_streams');
const metadata = require('../../radio_metadata');

function page(serial, sequence, flags, frames, body) {
  const lacing = []; let remaining = body.length;
  while (remaining >= 255) {lacing.push(255); remaining -= 255;}
  lacing.push(remaining);
  const header = Buffer.alloc(27 + lacing.length);
  header.write('OggS'); header[5] = flags; header.writeBigUInt64LE(BigInt(frames), 6);
  header.writeUInt32LE(serial, 14); header.writeUInt32LE(sequence, 18); header[26] = lacing.length;
  Buffer.from(lacing).copy(header, 27);
  const bytes = Buffer.concat([header, body]);
  let crc = 0;
  for (const byte of bytes) {
    crc ^= byte << 24;
    for (let bit = 0; bit < 8; bit++) crc = (crc << 1) ^ (crc & 0x80000000 ? 0x04c11db7 : 0);
  }
  bytes.writeUInt32LE(crc >>> 0, 22); return bytes;
}
function ogg(serial, frames, rate, count = 2) {
  const identification = Buffer.alloc(30);
  Buffer.from([1,118,111,114,98,105,115]).copy(identification);
  identification[11] = 2; identification.writeUInt32LE(rate, 12); identification[28] = 0xB8; identification[29] = 1;
  const pages = [page(serial, 0, 2, 0, identification)];
  for (let sequence = 1; sequence <= count; sequence++) {
    const body = Buffer.alloc(16000);
    for (let i = 0; i < body.length; i++) body[i] = (i * 37 + sequence * 11 + serial) & 255;
    pages.push(page(serial, sequence, sequence === count ? 4 : 0, sequence === count ? frames : 0, body));
  }
  return Buffer.concat(pages);
}
function fixture(directory, durationMultiplier = 1) {
  const config = path.join(directory, 'audio/config'), streams = path.join(directory, 'audio/streams');
  fs.mkdirSync(config, {recursive: true}); fs.mkdirSync(streams, {recursive: true});
  const packs = ['CO', 'ADVERTS', 'CH'], names = Buffer.alloc(packs.length * 16);
  packs.forEach((name, index) => names.write(name, index * 16));
  fs.writeFileSync(path.join(config, 'strmpaks.dat'), names);
  const definitions = [
    {pack: 0, bytes: ogg(11, 72000 * durationMultiplier, 24000), seconds: 3 * durationMultiplier},
    {pack: 2, bytes: ogg(12, 160000 * durationMultiplier, 32000, 140), seconds: 5 * durationMultiplier},
    {pack: 1, bytes: ogg(13, 88200 * durationMultiplier, 44100), seconds: 2 * durationMultiplier},
    {pack: 2, bytes: ogg(14, 48000 * durationMultiplier, 48000), seconds: durationMultiplier}
  ];
  const lookup = Buffer.alloc(definitions.length * 12);
  for (let pack = 0; pack < packs.length; pack++) {
    const rows = definitions.filter(row => row.pack === pack);
    let offset = 29;
    for (const row of rows) {row.offset = offset; offset += HEADER + row.bytes.length;}
    const encoded = Buffer.alloc(offset, 0xA7);
    for (const row of rows) {
      const id = definitions.indexOf(row), start = row.offset + HEADER;
      row.file = path.join(streams, packs[pack]);
      for (let i = 0; i < row.bytes.length; i++) encoded[start + i] = row.bytes[i] ^ KEY[(start + i) & 15];
      lookup[id * 12] = pack; lookup.writeUInt32LE(row.offset, id * 12 + 4);
      // Exercise both known size conventions without encoding any owner data.
      lookup.writeUInt32LE(row.bytes.length + (id % 2 ? HEADER : 0), id * 12 + 8);
    }
    fs.writeFileSync(path.join(streams, packs[pack]), encoded);
  }
  fs.writeFileSync(path.join(config, 'traklkup.dat'), lookup); return definitions;
}
class Response extends Writable {
  constructor(hold = false) {
    super({highWaterMark: 1}); this.chunks = []; this.status = null; this.headers = {}; this.pending = []; this.hold = hold;
    this.done = new Promise(resolve => {
      this.once('finish', () => resolve({finished: true}));
      this.once('error', error => resolve({finished: false, error}));
      this.once('close', () => resolve({finished: this.writableFinished}));
    });
  }
  writeHead(status, headers = {}) {this.status = status; this.headers = headers; this.headersSent = true;}
  _write(chunk, encoding, done) {
    this.chunks.push(Buffer.from(chunk)); this.emit('chunk');
    if (this.hold) this.pending.push(done); else setImmediate(done);
  }
  release() {this.hold = false; for (const done of this.pending.splice(0)) done();}
  get body() {return Buffer.concat(this.chunks);}
}
const tick = () => new Promise(resolve => setImmediate(resolve));
const delay = milliseconds => new Promise(resolve => setTimeout(resolve, milliseconds));
function request(method = 'GET', range) {
  const req = new EventEmitter(); req.method = method; req.headers = range === undefined ? {} : {range}; return req;
}
async function response(server, route, method = 'GET', range) {
  const res = new Response(), req = request(method, range);
  const handled = await server.handle(req, res, route);
  if (!handled) res.end();
  await res.done; res.handled = handled; return res;
}
function digest(bytes) {return crypto.createHash('sha256').update(bytes).digest('hex');}
function snapshot(directory) {
  return fs.readdirSync(directory, {recursive: true}).filter(name => fs.statSync(path.join(directory, name)).isFile())
    .sort().map(name => {const file = path.join(directory, name), stat = fs.statSync(file);
      return [name, stat.size, stat.mtimeMs, digest(fs.readFileSync(file))];});
}
async function main() {
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'zgta-browser-radio-'));
  const oldInspect = metadata.inspect, originalCreateReadStream = fs.createReadStream;
  let checks = 0, scans = 0;
  const check = (value, message) => {assert(value, message); checks++;};
  try {
    const owner = path.join(root, 'authored-owner'), alternate = path.join(root, 'authored-alternate');
    const rows = fixture(owner), alternativeRows = fixture(alternate, 2), originalFiles = snapshot(owner);
    const localOnly = path.join(root, 'host'), errors = [];
    const {configuration} = register(owner, {localOnly});
    const server = create({localOnly, onError: error => errors.push(error)});
    metadata.inspect = track => {scans++; return oldInspect(track);};
    check(!matches('/game/state') && !matches('/game/radio/custom/song.wav'), 'Only radio-owned routes are reserved');
    const index = await response(server, '/game/radio/index');
    check(index.status === 200 && index.headers['cache-control'] === 'no-store', 'Browser index is successful and not stale-cached');
    assert.deepEqual(JSON.parse(index.body), {stations: [[], [[1,5],[3,1]], [[0,3]], [], [], [], [], [], [], [], [], [], []], adverts: [[2,2]]}); checks++;
    check(!index.body.includes(Buffer.from(root)) && scans === 4, 'IDs/slots/durations have no owner paths and each stream was inspected once');
    const nativeIndex = await response(server, '/game/radio/native/index');
    const nativeJSON = JSON.parse(nativeIndex.body);
    check(nativeIndex.status === 200 && nativeJSON.version === 1 && nativeJSON.stations[1][0].id === 1 && nativeJSON.stations[1][0].url.startsWith('/game/radio/native/track/1.wav?v='), 'Existing native index shape and URLs are preserved');
    const indexHead = await response(server, '/game/radio/index', 'HEAD');
    check(indexHead.status === 200 && indexHead.body.length === 0 && indexHead.headers['content-length'] === index.body.length, 'Index HEAD has matching length and no body');
    await response(server, '/game/radio/index');
    check(scans === 4 && !fs.existsSync(path.join(localOnly, 'native-radio-cache')), 'Unchanged metadata is cached without decoding or PCM cache creation');
    for (let id = 0; id < rows.length; id++) {
      const full = await response(server, `/game/radio/track/${id}`);
      check(full.status === 200 && full.headers['content-type'] === 'audio/ogg' && full.headers['content-length'] === rows[id].bytes.length, 'Browser sends compressed Ogg with complete payload length');
      check(digest(full.body) === digest(rows[id].bytes), 'Every full track reconstructs the exact authored payload across XOR block boundaries');
      const head = await response(server, `/game/radio/track/${id}`, 'HEAD');
      check(head.status === 200 && head.body.length === 0 && head.headers['content-length'] === full.body.length, 'Track HEAD describes the full body without streaming it');
    }
    const bytes = rows[1].bytes;
    const ranges = [
      ['bytes=0-0', 0, 0], ['bytes=7-33', 7, 33], ['bytes=65531-65551', 65531, 65551],
      [`bytes=${bytes.length-17}-`, bytes.length-17, bytes.length-1], ['bytes=-19', bytes.length-19, bytes.length-1],
      [`bytes=-${bytes.length+100}`, 0, bytes.length-1], [`bytes=${bytes.length-3}-${bytes.length+90}`, bytes.length-3, bytes.length-1]
    ];
    for (const [range, start, end] of ranges) {
      const part = await response(server, '/game/radio/track/1', 'GET', range);
      check(part.status === 206 && part.headers['content-range'] === `bytes ${start}-${end}/${bytes.length}`, 'Valid ordinary/open/suffix range has precise bounds');
      assert.deepEqual(part.body, bytes.subarray(start, end+1)); checks++;
      const head = await response(server, '/game/radio/track/1', 'HEAD', range);
      check(head.status === 206 && head.body.length === 0 && head.headers['content-length'] === end-start+1, 'Range HEAD returns headers without audio');
    }
    const reconstructed = [];
    for (let start = 0; start < rows[0].bytes.length; start += 997) {
      const part = await response(server, '/game/radio/track/0', 'GET', `bytes=${start}-${start+996}`);
      check(part.status === 206, 'Independent unaligned range is accepted'); reconstructed.push(part.body);
    }
    assert.deepEqual(Buffer.concat(reconstructed), rows[0].bytes); checks++;
    for (const range of ['bytes=-0', 'bytes=-', 'bytes=5-4', `bytes=${bytes.length}-`, 'bytes=0-1,3-4', 'items=0-1', 'bytes=NaN-', 'bytes=9007199254740992-', ['bytes=0-1']]) {
      const invalid = await response(server, '/game/radio/track/1', 'GET', range);
      check(invalid.status === 416 && invalid.body.length === 0 && invalid.headers['content-range'] === `bytes */${bytes.length}`, 'Invalid/unsafe/multiple range is refused');
    }
    for (const route of ['/game/radio/track', '/game/radio/track/-1', '/game/radio/track/01', '/game/radio/track/1.ogg', '/game/radio/track/9007199254740992', '/game/radio/track/9999', '/game/radio/index/extra', '/game/radio/native/track/9999.wav']) {
      const missing = await response(server, route); check(missing.handled && missing.status === 404, 'Missing/malformed reserved route never becomes an arbitrary file request');
    }
    for (const route of ['/game/radio/index', '/game/radio/track/1', '/game/radio/native/index']) {
      const denied = await response(server, route, 'POST'); check(denied.status === 405 && denied.headers.allow === 'GET, HEAD', 'Read routes refuse mutating methods');
    }
    check(!(await response(server, '/unrelated')).handled, 'Unrelated requests remain the host responsibility');

    // Actual stream backpressure/cancellation: no network listener is needed.
    let opened = [];
    fs.createReadStream = function(...args) {const stream = originalCreateReadStream.apply(this, args); opened.push(stream); return stream;};
    await response(server, '/game/radio/track/1', 'HEAD', 'bytes=-19');
    check(opened.length === 0, 'HEAD never opens a compressed-body stream');
    const held = new Response(true), heldReq = request();
    const firstChunk = new Promise(resolve => held.once('chunk', resolve));
    await server.handle(heldReq, held, '/game/radio/track/1'); await firstChunk; await delay(25);
    check(opened.length === 1 && opened[0].bytesRead <= 6*65536 && held.chunks.length === 1 && !held.writableFinished, 'Backpressure keeps physical reads bounded instead of buffering an entire track');
    const closed = new Promise(resolve => opened[0].once('close', resolve));
    held.destroy(); await held.done; await closed;
    check(opened[0].destroyed && opened[0].fd === null && opened[0].bytesRead < bytes.length, 'Response cancellation closes the owned descriptor before reading the track');
    opened = [];
    const aborted = new Response(true), abortedReq = request();
    const firstAborted = new Promise(resolve => aborted.once('chunk', resolve));
    await server.handle(abortedReq, aborted, '/game/radio/track/1'); await firstAborted;
    const abortClosed = new Promise(resolve => opened[0].once('close', resolve));
    abortedReq.aborted = true; abortedReq.emit('aborted'); await aborted.done; await abortClosed;
    check(opened[0].fd === null && !aborted.writableFinished, 'Request abort also terminates the pipeline and releases its descriptor');
    fs.createReadStream = originalCreateReadStream;
    check(scans === 4 && !fs.existsSync(path.join(localOnly, 'native-radio-cache')), 'Range/cancel requests reuse validated metadata without PCM conversion');
    assert.deepEqual(snapshot(owner), originalFiles); checks++;

    const yielding = create({localOnly}), scanStart = scans;
    const yieldingIndex = response(yielding, '/game/radio/index'); await tick();
    check(scans > scanStart && scans < scanStart+4, 'A first metadata index yields before scanning the entire catalogue');
    check((await yieldingIndex).status === 200 && scans === scanStart+4, 'Yielded index still validates every advertised recording');
    const cancellingIndex = create({localOnly}), cancelledReq = request(), cancelledResponse = new Response(), cancelStart = scans;
    const cancellation = cancellingIndex.handle(cancelledReq, cancelledResponse, '/game/radio/index'); await tick();
    cancelledReq.aborted = true; cancelledResponse.destroy(); await cancellation; await cancelledResponse.done;
    check(scans > cancelStart && scans < cancelStart+4, 'Closing a first index stops additional metadata scans between bounded records');

    // Preserve actual native WAV conversion/cache/range handling using a tiny
    // Node-only authored output tool. This is a route test, not a codec proof.
    const wav = Buffer.alloc(108); wav.write('RIFF'); wav.writeUInt32LE(100,4); wav.write('WAVE',8); wav.write('fmt ',12);
    wav.writeUInt32LE(16,16); wav.writeUInt16LE(3,20); wav.writeUInt16LE(2,22); wav.writeUInt32LE(32000,24);
    wav.writeUInt32LE(256000,28); wav.writeUInt16LE(8,32); wav.writeUInt16LE(32,34); wav.write('data',36); wav.writeUInt32LE(64,40);
    const decoder = path.join(root, 'authored-node-decoder'), countFile = path.join(root, 'decoder-count');
    fs.writeFileSync(decoder, '#!/usr/bin/env node\n'+`const fs=require('node:fs');fs.appendFileSync(${JSON.stringify(countFile)},'1');fs.writeFileSync(process.argv[5],Buffer.from('${wav.toString('base64')}','base64'),{flag:'wx'});\n`, {mode: 0o700});
    const native = create({localOnly, decoder});
    const wavResponses = await Promise.all([response(native, '/game/radio/native/track/0.wav'), response(native, '/game/radio/native/track/0.wav')]);
    check(wavResponses.every(res => res.status === 200 && res.headers['content-type'] === 'audio/wav' && res.body.equals(wav)), 'Native WAV routes still deliver the actual cached converter result');
    check(fs.readFileSync(countFile,'utf8') === '1', 'Existing native concurrent conversion deduplication is preserved');
    const wavRange = await response(native, '/game/radio/native/track/0.wav', 'GET', 'bytes=7-31');
    check(wavRange.status === 206 && wavRange.body.equals(wav.subarray(7,32)), 'Existing native WAV range result is unchanged');
    assert.deepEqual(snapshot(owner), originalFiles); checks++;

    // Cache identity includes replacement inode/ctime, even when mtime/size
    // are preserved. All mutations below target only the authored fixture.
    const originalStat = fs.statSync(rows[0].file), replacement = rows[0].file + '.replacement';
    const replacementPack = fs.readFileSync(alternativeRows[0].file);
    fs.writeFileSync(replacement, replacementPack); fs.utimesSync(replacement, originalStat.atime, originalStat.mtime); fs.renameSync(replacement, rows[0].file);
    check(fs.statSync(rows[0].file).size === originalStat.size, 'Replacement fixture deliberately preserves bank size');
    const changed = await response(server, '/game/radio/index');
    check(changed.status === 200 && JSON.parse(changed.body).stations[2][0][1] === 6 && scans > 4, 'Replaced bank invalidates metadata rather than reusing a same-size/mtime cache entry');
    const changedBytes = await response(server, '/game/radio/track/0');
    check(changedBytes.body.equals(alternativeRows[0].bytes), 'Metadata duration and streamed bytes identify the same replacement recording');
    const beforeLookupChange = scans;
    const lookup = path.join(owner, 'audio/config/traklkup.dat'); fs.utimesSync(lookup, new Date(), new Date(Date.now()+2000));
    await response(server, '/game/radio/index'); check(scans > beforeLookupChange, 'Lookup-table identity changes invalidate derived metadata');

    // Changing owner during an in-flight response aborts rather than mixing
    // recordings or silently using another registration.
    const moving = new Response(true), movingReq = request();
    const firstMoving = new Promise(resolve => moving.once('chunk', resolve));
    await server.handle(movingReq, moving, '/game/radio/track/1'); await firstMoving;
    fs.writeFileSync(configuration, JSON.stringify({directory: alternate}));
    moving.release(); const moved = await moving.done;
    check(!moved.finished && moving.body.length < rows[1].bytes.length, 'Owner replacement aborts an old response with bounded bytes already in flight');
    const alternateIndex = await response(server, '/game/radio/index');
    check(alternateIndex.status === 200 && JSON.parse(alternateIndex.body).stations[1][0][1] === 10, 'A subsequent request validates the newly selected owner separately');
    fs.writeFileSync(configuration, '{malformed-private-path:' + root);
    const broken = await response(server, '/game/radio/index');
    check(broken.status === 503 && broken.body.toString() === 'Owner radio audio is unavailable' && !broken.body.includes(Buffer.from(root)), 'Malformed registration fails closed with a sanitized error');
    const brokenHead = await response(server, '/game/radio/index', 'HEAD');
    check(brokenHead.status === 503 && brokenHead.body.length === 0, 'Unavailable HEAD does not leak an error body');

    const absent = create({configuration: path.join(root, 'absent.json')});
    check((await response(absent, '/game/radio/index')).status === 503, 'Missing owner registration reports browser audio unavailable');
    check((await response(absent, '/game/radio/track/0')).status === 404, 'Missing owner cannot serve invented track IDs');
    check(JSON.parse((await response(absent, '/game/radio/native/index')).body).stations.length === 0, 'Unregistered native index retains its existing empty shape');
    const fallbackRoot = path.join(root, 'fallback-host'); fs.mkdirSync(path.join(fallbackRoot, 'site/game/radio'), {recursive: true});
    fs.writeFileSync(path.join(fallbackRoot, 'site/game/radio/owner.json'), JSON.stringify({directory: owner}));
    const preferred = register(alternate, {localOnly: fallbackRoot}).configuration, fallback = create({localOnly: fallbackRoot});
    check(JSON.parse((await response(fallback, '/game/radio/index')).body).stations[2][0][1] === 6, 'Preferred owner supersedes an existing legacy registration');
    fs.unlinkSync(preferred);
    check((await response(fallback, '/game/radio/index')).status === 503, 'Removed preferred registration cannot resurrect a legacy owner');
    fs.writeFileSync(configuration, JSON.stringify({directory: alternate}));
    const corruptFile = alternativeRows[0].file; fs.truncateSync(corruptFile, HEADER + 1);
    const truncated = await response(server, '/game/radio/index');
    check(truncated.status === 200 && JSON.parse(truncated.body).stations[2].length === 0 &&
      (await response(server, '/game/radio/track/0')).status === 404, 'Truncated bounds remove the recording instead of serving cached metadata or bytes');
    const malformed = fs.openSync(alternativeRows[1].file, 'r+');
    try {fs.writeSync(malformed, Buffer.alloc(4), 0, 4, alternativeRows[1].offset + HEADER);} finally {fs.closeSync(malformed);}
    const corrupt = await response(server, '/game/radio/index');
    check(corrupt.status === 503 && !corrupt.body.includes(Buffer.from(root)), 'Malformed Ogg pages fail metadata validation with sanitized responses');
    const restoredHeader = Buffer.from(alternativeRows[1].bytes.subarray(0,4)), restoredAt = alternativeRows[1].offset+HEADER;
    for (let i = 0; i < restoredHeader.length; i++) restoredHeader[i] ^= KEY[(restoredAt+i)&15];
    const restoredFile = fs.openSync(alternativeRows[1].file, 'r+');
    try {fs.writeSync(restoredFile, restoredHeader, 0, restoredHeader.length, restoredAt);} finally {fs.closeSync(restoredFile);}
    const oversizedLookup = path.join(alternate, 'audio/config/traklkup.dat'), oversized = fs.readFileSync(oversizedLookup);
    const oversizedBytes = 64*1024*1024+1;
    fs.truncateSync(corruptFile, alternativeRows[0].offset+HEADER+oversizedBytes);
    oversized.writeUInt32LE(HEADER+oversizedBytes, 8); fs.writeFileSync(oversizedLookup, oversized);
    check((await response(server, '/game/radio/index')).status === 503 && errors.at(-1).message.includes('64MiB'), 'Oversized compressed metadata is refused before allocating/reading its sparse record');
    const zeroOwner = path.join(root, 'authored-zero-duration'); fixture(zeroOwner, 0);
    const zeroConfiguration = register(zeroOwner, {configuration: path.join(root, 'zero-owner.json')}).configuration;
    check((await response(create({configuration: zeroConfiguration}), '/game/radio/index')).status === 503, 'Zero-duration EOS metadata cannot enter a successful index');
    check(errors.length > 0, 'Private diagnostics retain errors separately from responses');
    await tick();
    console.log(JSON.stringify({passed: true, checks, scope: 'Authored format pages; actual handlers, metadata/ranges/XOR, backpressure/cancellation, registration identity and native WAV regressions; no original audio, listener or device'}));
  } finally {metadata.inspect = oldInspect; fs.createReadStream = originalCreateReadStream; fs.rmSync(root, {recursive: true, force: true});}
}
if (require.main === module) main().catch(error => {console.error(error); process.exitCode = 1;});
module.exports = {fixture};
