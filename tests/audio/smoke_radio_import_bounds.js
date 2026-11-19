#!/usr/bin/env node
// Self-contained format-page fixture, not a synthetic-audio listening test.
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const {spawnSync} = require('node:child_process');
const candidate = require('../../radio_streams'), metadata = require('../../radio_metadata');
const {corrected} = require('../../tools/assets/prepare_owner_radio');

function page(serial, sequence, flags, granule, body) {
  const segments = []; let left = body.length;
  while (left >= 255) {segments.push(255); left -= 255;}
  segments.push(left);
  const header = Buffer.alloc(27 + segments.length);
  header.write('OggS'); header[5] = flags; header.writeBigUInt64LE(BigInt(granule), 6);
  header.writeUInt32LE(serial, 14); header.writeUInt32LE(sequence, 18); header[26] = segments.length;
  Buffer.from(segments).copy(header, 27);
  const result = Buffer.concat([header, body]);
  // Ogg checksum makes this a well-formed page carrier; the final packet is a
  // deterministic metadata fixture and is intentionally not decoded as sound.
  let crc = 0;
  for (const byte of result) {
    crc ^= byte << 24;
    for (let bit = 0; bit < 8; bit++) crc = (crc << 1) ^ (crc & 0x80000000 ? 0x04c11db7 : 0);
  }
  result.writeUInt32LE(crc >>> 0, 22); return result;
}
function payload(serial, frames) {
  const identification = Buffer.alloc(30);
  Buffer.from([1,118,111,114,98,105,115]).copy(identification);
  identification[11] = 2; identification.writeUInt32LE(32000, 12); identification[28] = 0xB8; identification[29] = 1;
  const packet = Buffer.alloc(9500); for(let i = 0; i < packet.length; i++) packet[i] = (i * 37 + serial) & 255;
  return Buffer.concat([page(serial,0,2,0,identification),page(serial,1,4,frames,packet)]);
}
const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-radio-bounds-'));
try {
  const config = path.join(directory,'audio/config'), streams = path.join(directory,'audio/streams');
  fs.mkdirSync(config,{recursive:true});fs.mkdirSync(streams,{recursive:true});
  const parts = [payload(17,32000),payload(18,64000)], padding = 29;
  const offsets = [padding,padding + candidate.HEADER + parts[0].length];
  const pack = Buffer.alloc(offsets[1] + candidate.HEADER + parts[1].length);
  for (let track = 0; track < parts.length; track++) for(let i = 0; i < parts[track].length; i++) {
    const at = offsets[track] + candidate.HEADER + i; pack[at] = parts[track][i] ^ candidate.KEY[at & 15];
  }
  fs.writeFileSync(path.join(streams,'CH'),pack);
  const names = Buffer.alloc(16); names.write('CH'); fs.writeFileSync(path.join(config,'strmpaks.dat'),names);
  const lookup = Buffer.alloc(24);
  for(let i = 0; i < 2; i++) {lookup[i*12] = 0;lookup.writeUInt32LE(offsets[i],i*12+4);}
  lookup.writeUInt32LE(parts[0].length,8); // Payload-only convention.
  lookup.writeUInt32LE(candidate.HEADER + parts[1].length,20); // Header-inclusive convention.
  fs.writeFileSync(path.join(config,'traklkup.dat'),lookup);
  const tracks = candidate.catalog(directory).stations[1]; assert.equal(tracks.length,2);
  for(let i = 0; i < 2; i++) {
    assert.equal(tracks[i].size,candidate.HEADER + parts[i].length);
    assert.deepEqual(candidate.read(tracks[i],0,parts[i].length + 500),parts[i]);
    assert.deepEqual(candidate.read(tracks[i],parts[i].length-7,parts[i].length+700),parts[i].subarray(-7));
    assert.equal(candidate.read(tracks[i],parts[i].length,parts[i].length+1).length,0);
    assert.equal(metadata.inspect(tracks[i]).frames,(i+1)*32000);
  }
  const input = {rate:32000,samples:[12000,64000],provenance:{source:'synthetic metadata test'}};
  const full = corrected(input,directory);
  assert.deepEqual(full.program.samples,[32000,64000]); assert.deepEqual(full.changed,[0]);
  assert.deepEqual(input.samples,[12000,64000],'Compatibility input was mutated');
  const compatibility=path.join(directory,'compatibility.json'),output=path.join(directory,'full.json');
  fs.writeFileSync(compatibility,JSON.stringify(input));
  const run=destination=>spawnSync(process.execPath,[path.join(require('node:path').resolve(__dirname, '../..'),'tools/assets/prepare_owner_radio.js'),compatibility,directory,destination],{encoding:'utf8'});
  assert.equal(run(output).status,0,'A fresh full-recording variant should be created');
  const originalOutput=fs.readFileSync(output),originalInput=fs.readFileSync(compatibility);
  assert.deepEqual(JSON.parse(originalOutput).samples,[32000,64000]);
  assert.notEqual(run(output).status,0,'An existing output must never be replaced');
  assert.deepEqual(fs.readFileSync(output),originalOutput);
  for(const kind of ['symlink','hardlink']) {
    const alias=path.join(directory,kind+'.json');
    if(kind==='symlink')fs.symlinkSync(compatibility,alias);else fs.linkSync(compatibility,alias);
    assert.notEqual(run(alias).status,0,'An alias must not overwrite the compatibility input');
    assert.deepEqual(fs.readFileSync(compatibility),originalInput);
  }
  assert.throws(()=>metadata.inspect({...tracks[0],size:tracks[0].size-1}),/Incomplete|bounds|end/);
  // Overlapping advertised sizes are rejected rather than reading the next track.
  lookup.writeUInt32LE(parts[0].length + candidate.HEADER + 1,8);
  fs.writeFileSync(path.join(config,'traklkup.dat'),lookup);
  assert.deepEqual(candidate.catalog(directory).stations[1].map(track=>track.id),[1]);
  console.log('PASS: archive-free mixed radio lookup sizes recover exact per-track bytes; unaligned XOR, EOF, metadata, program preservation and overlap rejection');
} finally {fs.rmSync(directory,{recursive:true,force:true});}
