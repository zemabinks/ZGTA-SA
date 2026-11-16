'use strict';
// SPDX-License-Identifier: AGPL-3.0-only
// Independent owner-local VER2 IMG range provider. No original assets included.
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const crypto = require('node:crypto');

const SECTOR = 2048;
const NAME = /^[a-z0-9_#()+.\-]{1,128}$/;
const SHA = /^[0-9a-f]{64}$/;
const integer = (value, min, max) => Number.isSafeInteger(value) && value >= min && value <= max;
const failure = (code, message) => Object.assign(new Error(message), { code });
const fingerprint = stat => [stat.dev, stat.ino, stat.size, stat.mtimeNs].map(String).join(':');
const sameRange = (a, b) => a.archive === b.archive && a.name === b.name && a.offset === b.offset && a.allocatedBytes === b.allocatedBytes;
const crcTable = Array.from({ length: 256 }, (_, n) => {
  for (let bit = 0; bit < 8; bit++) n = (n >>> 1) ^ ((n & 1) ? 0xedb88320 : 0);
  return n >>> 0;
});
function updateCRC(value, data) {
  for (const byte of data) value = crcTable[(value ^ byte) & 255] ^ (value >>> 8);
  return value >>> 0;
}
async function exact(handle, length, position, signal) {
  const data = Buffer.alloc(length);
  for (let at = 0; at < length;) {
    if (signal?.aborted) throw failure('ABORTED', 'Asset request cancelled');
    const result = await handle.read(data, at, Math.min(65536, length - at), position + at);
    if (!result.bytesRead) throw failure('INTEGRITY', 'Truncated IMG source range');
    at += result.bytesRead;
  }
  return data;
}
async function boundedJSON(path, maximum) {
  const handle = await fsp.open(path, 'r');
  try {
    const stat = await handle.stat();
    if (!integer(stat.size, 2, maximum)) throw failure('LIMIT', 'IMG index metadata size');
    const data = await exact(handle, stat.size, 0);
    if ((await handle.stat()).size !== stat.size) throw failure('INTEGRITY', 'IMG index changed while reading');
    return JSON.parse(data.toString('utf8'));
  } finally { await handle.close(); }
}

class StockIMGAssetProvider {
  static async open({ indexPath, archivePaths, limits = {} }) {
    const value = new StockIMGAssetProvider(limits);
    try { await value.initialize(await boundedJSON(indexPath, value.limits.indexBytes), archivePaths); return value; }
    catch (error) { await value.close(); throw error; }
  }
  constructor(limits) {
    this.limits = { indexBytes: 32 * 1024 * 1024, fileBytes: 64 * 1024 * 1024,
      residentBytes: 128 * 1024 * 1024, concurrent: 2, pending: 16, responseTimeoutMs: 30000, ...limits };
    const l = this.limits;
    if (!integer(l.indexBytes, 2, 32 * 1024 * 1024) || !integer(l.fileBytes, 12, 64 * 1024 * 1024) ||
        !integer(l.residentBytes, 12, 256 * 1024 * 1024) || !integer(l.concurrent, 1, 8) ||
        !integer(l.pending, 1, 256) || !integer(l.responseTimeoutMs, 1, 120000)) throw failure('LIMIT', 'IMG provider configuration');
    this.archives = new Map(); this.assets = new Map(); this.paths = new Map(); this.ambiguous = new Map(); this.unavailable = new Map();
    this.pending = []; this.active = new Set(); this.residentBytes = 0; this.closed = false;
  }
  async initialize(index, archivePaths) {
    if (index.schema !== 1 || typeof index.prefix !== 'string' || index.prefix.length > 256 ||
        !index.prefix.split('/').every(part => NAME.test(part) && part !== '.' && part !== '..') ||
        !Array.isArray(index.archives) || !integer(index.archives.length, 1, 8) ||
        !Array.isArray(index.entries) || index.entries.length > 100000 ||
        !Array.isArray(index.ambiguous) || index.ambiguous.length > 100000 ||
        !Array.isArray(index.unavailable) || index.unavailable.length > 100000) throw failure('INDEX', 'Invalid IMG index');
    this.prefix = '/' + index.prefix + '/';
    const records = new Map(); let total = 0;
    for (const archive of index.archives) {
      if (!NAME.test(archive.name) || !archive.name.endsWith('.img') || this.archives.has(archive.name) ||
          !integer(archive.bytes, SECTOR, 8 * 1024 * 1024 * 1024) || !SHA.test(archive.directorySHA256) ||
          !archivePaths || !Object.hasOwn(archivePaths, archive.name)) throw failure('INDEX', 'Invalid IMG archive identity');
      // Only explicit owner configuration supplies a source pathname. HTTP
      // names/paths can never choose an arbitrary local file or archive range.
      const path = await fsp.realpath(archivePaths[archive.name]);
      const handle = await fsp.open(path, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
      const owner = { handle, fingerprint: null }; this.archives.set(archive.name, owner);
      const stat = await handle.stat({ bigint: true });
      if (!stat.isFile() || stat.size !== BigInt(archive.bytes) || stat.size % 2048n) throw failure('INTEGRITY', 'IMG archive size');
      const header = await exact(handle, 8, 0);
      const count = header.readUInt32LE(4); total += count;
      if (header.toString('ascii', 0, 4) !== 'VER2' || count > 100000 || total > 100000 ||
          archive.entries !== count || archive.directoryBytes !== 8 + count * 32) throw failure('INDEX', 'IMG table count');
      const table = await exact(handle, count * 32, 8);
      const digest = crypto.createHash('sha256').update(header).update(table).digest('hex');
      if (digest !== archive.directorySHA256) throw failure('INTEGRITY', 'IMG directory fingerprint');
      const ranges = [];
      for (let at = 0; at < table.length; at += 32) {
        const raw = table.subarray(at + 8, at + 32), nul = raw.indexOf(0);
        const nameBytes = nul < 0 ? raw : raw.subarray(0, nul);
        if (nameBytes.some(byte => byte > 127)) throw failure('INDEX', 'Non-ASCII IMG name');
        const name = nameBytes.toString('ascii').toLowerCase();
        const offset = table.readUInt32LE(at) * SECTOR, allocatedBytes = table.readUInt16LE(at + 4) * SECTOR;
        if (!NAME.test(name) || !allocatedBytes || table.readUInt16LE(at + 6) || offset < archive.directoryBytes ||
            offset + allocatedBytes > archive.bytes) throw failure('INDEX', 'Invalid/packed IMG range');
        const record = { archive: archive.name, name, offset, allocatedBytes }; ranges.push(record);
        if (/\.(dff|txd)$/.test(name)) { if (!records.has(name)) records.set(name, []); records.get(name).push(record); }
      }
      ranges.sort((a, b) => a.offset - b.offset); let end = archive.directoryBytes;
      for (const range of ranges) { if (range.offset < end) throw failure('INDEX', 'Overlapping IMG ranges'); end = range.offset + range.allocatedBytes; }
      const after = await handle.stat({ bigint: true });
      if (fingerprint(stat) !== fingerprint(after)) throw failure('INTEGRITY', 'IMG changed during initialization');
      owner.fingerprint = fingerprint(after);
    }
    for (const entry of index.entries) {
      const originals = records.get(entry.name);
      if (!originals || originals.length !== 1 || !sameRange(entry, originals[0]) || this.assets.has(entry.name) ||
          !integer(entry.bytes, 12, this.limits.fileBytes) || entry.bytes > this.limits.residentBytes ||
          entry.bytes > entry.allocatedBytes || entry.allocatedBytes - entry.bytes >= SECTOR ||
          !integer(entry.crc32, 0, 0xffffffff) || !SHA.test(entry.sha256) ||
          entry.path !== index.prefix + '/' + entry.sha256 + entry.name.slice(-4)) throw failure('INDEX', 'Invalid logical IMG asset');
      const prior = this.paths.get('/' + entry.path);
      if (prior && (prior.bytes !== entry.bytes || prior.crc32 !== entry.crc32 || prior.sha256 !== entry.sha256)) throw failure('INDEX', 'Conflicting asset address');
      const value = Object.freeze({ ...entry }); this.assets.set(entry.name, value);
      if (!prior) this.paths.set('/' + entry.path, value);
    }
    for (const row of index.ambiguous) {
      const originals = records.get(row.name);
      if (!originals || originals.length < 2 || this.ambiguous.has(row.name) || !Array.isArray(row.candidates) ||
          row.candidates.length !== originals.length || !originals.every(original => row.candidates.some(item => sameRange(item, original)))) throw failure('INDEX', 'Invalid ambiguous IMG name');
      this.ambiguous.set(row.name, Object.freeze(originals.map(item => Object.freeze({ ...item }))));
    }
    for (const [name, originals] of records) if (originals.length > 1 && !this.ambiguous.has(name)) throw failure('INDEX', 'Omitted IMG name ambiguity');
    for (const row of index.unavailable) {
      const originals = records.get(row.name);
      if (!originals || originals.length !== 1 || !sameRange(row, originals[0]) || this.assets.has(row.name) ||
          this.unavailable.has(row.name) || typeof row.reason !== 'string' || row.reason.length > 1024) throw failure('INDEX', 'Invalid unavailable IMG entry');
      this.unavailable.set(row.name, row.reason);
    }
  }
  resolve(name) {
    if (typeof name !== 'string' || !NAME.test(name.toLowerCase())) return { state: 'missing' };
    name = name.toLowerCase();
    if (this.ambiguous.has(name)) return { state: 'ambiguous', candidates: this.ambiguous.get(name) };
    if (this.unavailable.has(name)) return { state: 'unavailable', reason: this.unavailable.get(name) };
    return this.assets.has(name) ? { state: 'available', file: this.assets.get(name) } : { state: 'missing' };
  }
  get status() { return { active: this.active.size, pending: this.pending.length, residentBytes: this.residentBytes, closed: this.closed }; }
  withAsset(name, action, { signal } = {}) {
    const resolved = this.resolve(name);
    if (resolved.state !== 'available') return Promise.reject(failure(resolved.state.toUpperCase(), 'Exact stock IMG asset unavailable'));
    if (this.closed || signal?.aborted) return Promise.reject(failure(this.closed ? 'CLOSED' : 'ABORTED', 'Asset owner closed/cancelled'));
    if (this.pending.length >= this.limits.pending) return Promise.reject(failure('BUSY', 'Stock asset queue full'));
    return new Promise((resolve, reject) => {
      const controller = new AbortController();
      const job = { entry: resolved.file, action, resolve, reject, controller, signal, done: null };
      job.abort = () => {
        controller.abort(); const at = this.pending.indexOf(job);
        if (at >= 0) { this.pending.splice(at, 1); signal?.removeEventListener('abort', job.abort); reject(failure('ABORTED', 'Queued asset cancelled')); }
      };
      signal?.addEventListener('abort', job.abort, { once: true }); this.pending.push(job); this.pump();
    });
  }
  pump() {
    while (!this.closed && this.active.size < this.limits.concurrent && this.pending.length) {
      const job = this.pending[0]; if (this.residentBytes + job.entry.bytes > this.limits.residentBytes) break;
      this.pending.shift(); this.active.add(job); this.residentBytes += job.entry.bytes;
      job.done = (async () => {
        try {
          const data = await this.readVerified(job.entry, job.controller.signal);
          const result = await job.action(data, job.entry, job.controller.signal);
          if (job.controller.signal.aborted) throw failure('ABORTED', 'Active asset cancelled');
          return result;
        }
        finally { job.signal?.removeEventListener('abort', job.abort); this.active.delete(job); this.residentBytes -= job.entry.bytes; this.pump(); }
      })();
      job.done.then(job.resolve, job.reject);
    }
  }
  async readVerified(entry, signal) {
    const owner = this.archives.get(entry.archive), { handle } = owner;
    if (fingerprint(await handle.stat({ bigint: true })) !== owner.fingerprint) throw failure('INTEGRITY', 'IMG source changed');
    const data = await exact(handle, entry.bytes, entry.offset, signal);
    const kind = data.readUInt32LE(0), rootEnd = 12 + data.readUInt32LE(4), expected = entry.name.endsWith('.dff') ? 16 : 22;
    if (kind !== expected || rootEnd > data.length) throw failure('INTEGRITY', 'RW root extent');
    if (rootEnd !== data.length) {
      if (expected !== 16 || data.length - rootEnd < 12 || data.readUInt32LE(rootEnd) !== 3 ||
          rootEnd + 12 + data.readUInt32LE(rootEnd + 4) !== data.length) throw failure('INTEGRITY', 'RW top-level extension extent');
    }
    const tail = await exact(handle, entry.allocatedBytes - entry.bytes, entry.offset + entry.bytes, signal);
    if (tail.some(byte => byte !== 0)) throw failure('INTEGRITY', 'Nonzero IMG allocation padding');
    if (((updateCRC(0xffffffff, data) ^ 0xffffffff) >>> 0) !== entry.crc32 ||
        crypto.createHash('sha256').update(data).digest('hex') !== entry.sha256) throw failure('INTEGRITY', 'Stock IMG asset digest mismatch');
    if (signal.aborted) throw failure('ABORTED', 'Asset request cancelled');
    if (fingerprint(await handle.stat({ bigint: true })) !== owner.fingerprint) throw failure('INTEGRITY', 'IMG changed while reading');
    return data;
  }
  async handle(req, res) {
    let url;
    try { url = new URL(req.url, 'http://localhost'); } catch { return false; }
    if (!url.pathname.startsWith(this.prefix)) return false;
    const entry = !url.search && this.paths.get(url.pathname);
    if (!entry) { res.writeHead(404, { 'Content-Length': '0' }); res.end(); return true; }
    if (!['GET', 'HEAD'].includes(req.method)) { res.writeHead(405, { Allow: 'GET, HEAD', 'Content-Length': '0' }); res.end(); return true; }
    if (req.headers.range) { res.writeHead(416, { 'Content-Length': '0', 'Content-Range': `bytes */${entry.bytes}` }); res.end(); return true; }
    const controller = new AbortController(), abort = () => controller.abort();
    req.once('aborted', abort); res.once('close', abort);
    try {
      await this.withAsset(entry.name, async (data, file, signal) => {
        if (signal.aborted || res.destroyed) throw failure('ABORTED', 'HTTP asset request cancelled');
        await new Promise((resolve, reject) => {
          const destroy = () => res.destroy();
          const timer = setTimeout(destroy, this.limits.responseTimeoutMs); timer.unref();
          const done = () => { clearTimeout(timer); signal.removeEventListener('abort', destroy); resolve(); };
          signal.addEventListener('abort', destroy, { once: true }); res.once('close', done); res.once('finish', done); res.once('error', reject);
          res.writeHead(200, { 'Content-Type': 'application/octet-stream', 'Content-Length': String(file.bytes),
            'Cache-Control': 'private, max-age=86400, immutable', ETag: `"${file.sha256}"`, 'Accept-Ranges': 'none' });
          res.end(req.method === 'HEAD' ? undefined : data);
        });
      }, { signal: controller.signal });
    } catch (error) {
      if (!res.destroyed && !res.headersSent) { res.writeHead(['BUSY', 'CLOSED'].includes(error.code) ? 503 : 500, { 'Content-Length': '0' }); res.end(); }
      else if (!res.destroyed) res.destroy();
    } finally { req.removeListener('aborted', abort); res.removeListener('close', abort); }
    return true;
  }
  async close() {
    if (!this.closed) {
      this.closed = true;
      for (const job of this.pending.splice(0)) { job.signal?.removeEventListener('abort', job.abort); job.reject(failure('CLOSED', 'Asset owner closed')); }
      for (const job of this.active) job.controller.abort();
    }
    await Promise.allSettled([...this.active].map(job => job.done));
    await Promise.allSettled([...this.archives.values()].map(owner => owner.handle.close())); this.archives.clear();
  }
}
module.exports = { StockIMGAssetProvider };
