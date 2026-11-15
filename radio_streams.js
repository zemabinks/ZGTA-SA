// Owner-supplied San Andreas audio/streams reader. Nothing is downloaded here.
const fs = require('node:fs'), path = require('node:path');
const KEY = Buffer.from([234,58,196,161,154,168,20,243,72,176,215,35,157,232,255,241]);
const PACKS = ['AA','CH','CO','CR','DS','HC','MH','MR','NJ','RE','RG','TK'];
const HEADER = 8068;

function discover(directory) {
  const files = new Map();
  function walk(root, relative = '', depth = 0) {
    for (const entry of fs.readdirSync(root, {withFileTypes: true})) {
      const name = entry.name.toLowerCase(), rel = relative + name;
      if (entry.isFile() && /(^|\/)audio\/(config\/(strmpaks|traklkup)\.dat|streams\/[a-z]+)$/.test(rel))
        files.set(rel, path.join(root, entry.name));
      else if (entry.isDirectory() && depth < 3 && (depth === 0 || /^(audio|config|streams)$/.test(name)))
        walk(path.join(root, entry.name), rel + '/', depth + 1);
    }
  }
  walk(path.resolve(directory));
  return files;
}

function catalog(directory) {
  const files = discover(directory);
  const find = name => [...files].find(([key]) => key === name || key.endsWith('/' + name))?.[1];
  const packsPath = find('audio/config/strmpaks.dat'), lookupPath = find('audio/config/traklkup.dat');
  if (!packsPath || !lookupPath) throw Error('The owner directory has no audio/config radio lookup files');
  const pakBytes = fs.readFileSync(packsPath), lookup = fs.readFileSync(lookupPath);
  const packs = [];
  for (let at = 0; at + 16 <= pakBytes.length; at += 16) {
    const name = pakBytes.toString('latin1', at, at + 16).replace(/\0.*$/, '').trim().toLowerCase();
    const file = /^[a-z]+$/.test(name) ? find('audio/streams/' + name) : null;
    packs.push({name, file, size: file ? fs.statSync(file).size : 0});
  }
  const tracks = [];
  for (let at = 0; at + 12 <= lookup.length; at += 12) {
    const pack = packs[lookup.readUInt8(at)], offset = lookup.readUInt32LE(at + 4), size = lookup.readUInt32LE(at + 8);
    if (!pack?.file || size <= HEADER || offset + size > pack.size) continue;
    tracks.push({id: at / 12, pack: pack.name.toUpperCase(), file: pack.file, offset, size, seconds: null});
  }
  const stations = [...PACKS, null].map(pack => pack ? tracks.filter(track => track.pack === pack) : []);
  const adverts = tracks.filter(track => track.pack === 'ADVERTS');
  if (!stations.some(station => station.length)) throw Error('No valid owner radio streams were found');
  return {version: 1, source: 'Archived module19737.mH/mK; owner files',
    directory: path.resolve(directory), stations, adverts};
}

function read(track, start, end) {
  if (![start,end].every(Number.isSafeInteger) || start < 0 || end < start) throw Error('Invalid radio byte range');
  const size = track.size - HEADER;
  if (start >= size) return Buffer.alloc(0);
  const at = track.offset + HEADER + start, length = Math.min(end, size) - start;
  const bytes = Buffer.alloc(length), fd = fs.openSync(track.file, 'r');
  try {
    if (fs.readSync(fd, bytes, 0, length, at) !== length) throw Error('Owner radio stream changed while reading');
  } finally { fs.closeSync(fd); }
  for (let i = 0; i < bytes.length; i++) bytes[i] ^= KEY[(at + i) & 15];
  return bytes;
}

module.exports = {catalog, read, discover, KEY, HEADER, PACKS};
