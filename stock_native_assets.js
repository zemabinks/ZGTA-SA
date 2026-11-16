'use strict';
// SPDX-License-Identifier: AGPL-3.0-only
// Explicit owner-local stock routes. Missing preparation never proxies upstream.
const fs = require('node:fs');
const fsp = require('node:fs/promises');
const path = require('node:path');
const crypto = require('node:crypto');
const { StockIMGAssetProvider } = require('./stock_img_assets');
const SHA = /^[a-f0-9]{64}$/;
const integer = (n, lo, hi) => Number.isSafeInteger(n) && n >= lo && n <= hi;
const fail = (code, message) => Object.assign(new Error(message), { code });
const fingerprint = s => [s.dev, s.ino, s.size, s.mtimeNs].map(String).join(':');
const inside = (root, target) => target.startsWith(root.endsWith(path.sep) ? root : root + path.sep);
const namespace = value => /^\/+game\/native\/(?:stock-models(?:[/.]|$)|stock-img(?:\/|$)|stock-collision(?:\/|$))/i.test(value);
const crcTable = Array.from({ length: 256 }, (_, n) => { for (let i = 0; i < 8; i++) n = (n >>> 1) ^ ((n & 1) ? 0xedb88320 : 0); return n >>> 0; });
function crc32(data) { let n = 0xffffffff; for (const b of data) n = crcTable[(n ^ b) & 255] ^ (n >>> 8); return (n ^ 0xffffffff) >>> 0; }

async function boundedFile(filename, limit, signal) {
  const handle = await fsp.open(filename, fs.constants.O_RDONLY | (fs.constants.O_NOFOLLOW || 0));
  try {
    const before = await handle.stat({ bigint: true });
    if (!before.isFile() || before.size < 1n || before.size > BigInt(limit)) throw fail('LIMIT', 'Local stock resource size');
    const data = Buffer.alloc(Number(before.size));
    for (let at = 0; at < data.length;) {
      if (signal?.aborted) throw fail('ABORTED', 'Stock request cancelled');
      const { bytesRead } = await handle.read(data, at, Math.min(65536, data.length - at), at);
      if (!bytesRead) throw fail('INTEGRITY', 'Local stock resource truncated'); at += bytesRead;
    }
    if (fingerprint(before) !== fingerprint(await handle.stat({ bigint: true }))) throw fail('INTEGRITY', 'Local stock resource changed');
    return data;
  } finally { await handle.close(); }
}
async function jsonFile(filename, limit) {
  const data = await boundedFile(filename, limit); return { data, value: JSON.parse(data.toString('utf8')) };
}
class Gate {
  constructor() { this.active = new Set(); this.pending = []; this.closed = false; }
  run(signal, action) {
    if (this.closed || signal.aborted) return Promise.reject(fail('ABORTED', 'Stock owner closed/cancelled'));
    if (this.pending.length >= 16) return Promise.reject(fail('BUSY', 'Stock request queue full'));
    return new Promise((resolve, reject) => {
      const job = { signal, action, resolve, reject };
      job.abort = () => { const at = this.pending.indexOf(job); if (at >= 0) { this.pending.splice(at, 1); signal.removeEventListener('abort', job.abort); reject(fail('ABORTED', 'Queued stock request cancelled')); } };
      signal.addEventListener('abort', job.abort, { once: true }); this.pending.push(job); this.pump();
    });
  }
  pump() {
    while (!this.closed && this.active.size < 2 && this.pending.length) {
      const job = this.pending.shift(); this.active.add(job);
      job.done = Promise.resolve().then(job.action).finally(() => { job.signal.removeEventListener('abort', job.abort); this.active.delete(job); this.pump(); });
      job.done.then(job.resolve, job.reject);
    }
  }
  async close() {
    this.closed = true;
    for (const job of this.pending.splice(0)) { job.signal.removeEventListener('abort', job.abort); job.reject(fail('ABORTED', 'Stock owner closed')); }
    await Promise.allSettled([...this.active].map(job => job.done));
  }
}
class StockNativeAssets {
  constructor({ localOnly, env = process.env }) {
    this.localOnly = path.resolve(localOnly); this.env = { ...env }; this.gate = new Gate(); this.controllers = new Set();
    this.img = null; this.modelManifest = null; this.collision = null; this.loading = null; this.closed = false;
  }
  matches(pathname, raw = '') {
    for (const value of [pathname, raw.split('?')[0]]) {
      if (namespace(value)) return true;
      try { if (namespace(decodeURIComponent(value))) return true; } catch { /* Known raw prefix is still reserved. */ }
    }
    return false;
  }
  async initialize() {
    let config = {};
    if (this.env.ZGTA_STOCK_NATIVE_CONFIG) {
      const selected = path.resolve(this.localOnly, this.env.ZGTA_STOCK_NATIVE_CONFIG);
      const root = await fsp.realpath(this.localOnly), actual = await fsp.realpath(selected);
      if (!inside(root, actual)) throw fail('CONFIG', 'Stock config must remain local-only');
      config = (await jsonFile(actual, 64 * 1024)).value;
      if (!config || typeof config !== 'object' || Array.isArray(config)) throw fail('CONFIG', 'Stock config object required');
    }
    const selected = (key, variable) => this.env[variable] || config[key];
    const indexPath = selected('imgIndex', 'ZGTA_STOCK_IMG_INDEX');
    const manifestPath = selected('stockManifest', 'ZGTA_STOCK_MODELS_MANIFEST');
    const collisionRoot = selected('collisionRoot', 'ZGTA_STOCK_COLLISION_ROOT');
    let archivePaths = config.archivePaths;
    if (this.env.ZGTA_STOCK_IMG_ARCHIVES) {
      if (Buffer.byteLength(this.env.ZGTA_STOCK_IMG_ARCHIVES) > 64 * 1024) throw fail('CONFIG', 'Archive environment metadata size');
      archivePaths = JSON.parse(this.env.ZGTA_STOCK_IMG_ARCHIVES);
    }
    const configuredPath = name => { if (typeof name !== 'string' || !name || name.length > 4096) throw fail('CONFIG', 'Invalid stock path configuration'); return path.resolve(this.localOnly, name); };
    if (indexPath || manifestPath || archivePaths) {
      if (!indexPath || !manifestPath || !archivePaths || typeof archivePaths !== 'object' || Array.isArray(archivePaths)) throw fail('CONFIG', 'IMG configuration incomplete');
      const paths = Object.fromEntries(Object.entries(archivePaths).map(([name, filename]) => [name, configuredPath(filename)]));
      this.img = await StockIMGAssetProvider.open({ indexPath: configuredPath(indexPath), archivePaths: paths });
      if (this.img.prefix !== '/game/native/stock-img/') throw fail('CONFIG', 'Stock server requires the standard virtual prefix');
      const manifest = await jsonFile(configuredPath(manifestPath), 16 * 1024 * 1024), value = manifest.value;
      if (value.schema !== 1 || !Array.isArray(value.models) || value.models.length > 30000 || !value.assets || Object.keys(value.assets).length > 50000) throw fail('CONFIG', 'Invalid native stock manifest');
      for (const [name, asset] of Object.entries(value.assets)) {
        if (typeof asset.path !== 'string') throw fail('CONFIG', 'Invalid stock asset path');
        if (asset.path.startsWith(this.img.prefix.slice(1))) {
          const found = this.img.resolve(name);
          if (found.state !== 'available' || ['path', 'bytes', 'crc32', 'sha256'].some(key => found.file[key] !== asset[key])) throw fail('INTEGRITY', 'Stock manifest differs from IMG index');
        }
      }
      this.modelManifest = manifest.data;
    }
    if (collisionRoot) {
      const root = await fsp.realpath(configuredPath(collisionRoot));
      const file = path.join(root, 'game/native/stock-collision/catalog.json');
      if (!inside(root, await fsp.realpath(file))) throw fail('CONFIG', 'COL catalog leaves configured root');
      const catalog = await jsonFile(file, 16 * 1024 * 1024), value = catalog.value;
      if (value.schema !== 2 || !Array.isArray(value.models) || value.models.length > 30000) throw fail('CONFIG', 'Invalid native COL catalog');
      if (this.modelManifest && value.coverage?.stockManifestSHA256 &&
          crypto.createHash('sha256').update(this.modelManifest).digest('hex') !== value.coverage.stockManifestSHA256) throw fail('INTEGRITY', 'COL coverage binds a different stock manifest');
      const records = new Map(); let count = 0;
      for (const model of value.models) {
        if (!Array.isArray(model.records) || !Array.isArray(model.bindings)) throw fail('CONFIG', 'Invalid COL model records');
        for (const record of model.records) {
          if (++count > 100000 || !integer(record.bytes, 72, 32 * 1024 * 1024) || !integer(record.crc32, 0, 0xffffffff) || !SHA.test(record.sha256) ||
              record.path !== `game/native/stock-collision/${record.sha256}.col` || !integer(record.headerModelID, 0, 65535) ||
              !integer(record.version, 1, 3) || typeof record.headerName !== 'string' || record.headerName.length > 128) throw fail('CONFIG', 'Invalid COL record identity');
          const prior = records.get('/' + record.path);
          if (prior && ['bytes', 'crc32', 'sha256', 'headerModelID', 'headerName', 'version'].some(key => prior[key] !== record[key])) throw fail('CONFIG', 'Conflicting COL content address');
          records.set('/' + record.path, Object.freeze({ ...record }));
        }
      }
      this.collision = { root, data: catalog.data, records };
    }
  }
  async ready() {
    if (!this.loading) this.loading = this.initialize().catch(async error => { await this.img?.close(); this.img = null; this.modelManifest = null; this.collision = null; throw error; });
    await this.loading;
  }
  async reply(req, res, data, contentType, signal, digest) {
    if (signal.aborted || res.destroyed) throw fail('ABORTED', 'Stock response cancelled');
    await new Promise((resolve, reject) => {
      const destroy = () => res.destroy();
      const timer = setTimeout(destroy, 30000); timer.unref();
      const done = () => { clearTimeout(timer); signal.removeEventListener('abort', destroy); resolve(); };
      signal.addEventListener('abort', destroy, { once: true }); res.once('close', done); res.once('finish', done); res.once('error', reject);
      res.writeHead(200, { 'Content-Type': contentType, 'Content-Length': String(data.length), 'Cache-Control': digest ? 'private, max-age=86400, immutable' : 'no-cache',
        'Accept-Ranges': 'none', ...(digest ? { ETag: `"${digest}"` } : {}) });
      res.end(req.method === 'HEAD' ? undefined : data);
    });
  }
  async handle(req, res, pathname) {
    const controller = new AbortController(), abort = () => controller.abort(), signal = controller.signal;
    this.controllers.add(controller); req.once('aborted', abort); res.once('close', abort);
    const empty = status => { res.writeHead(status, { 'Content-Length': '0', ...(status === 405 ? { Allow: 'GET, HEAD' } : {}) }); res.end(); };
    try {
      if (!['GET', 'HEAD'].includes(req.method)) return empty(405);
      if (!req.url.startsWith('/') || req.url.includes('%') || req.url.split('?')[0] !== pathname || req.url.includes('?')) return empty(404);
      if (req.headers.range) return empty(416);
      await this.gate.run(signal, async () => {
        await this.ready();
        if (this.closed || signal.aborted) throw fail('ABORTED', 'Stock owner closed');
        if (pathname === '/game/native/stock-models.json') {
          if (!this.modelManifest) return empty(404);
          return this.reply(req, res, this.modelManifest, 'application/json; charset=utf-8', signal);
        }
        if (pathname === '/game/native/stock-collision/catalog.json' || pathname === '/game/native/stock-collision/index.json') {
          if (!this.collision) return empty(404);
          return this.reply(req, res, this.collision.data, 'application/json; charset=utf-8', signal);
        }
        if (pathname.startsWith('/game/native/stock-img/')) {
          if (!this.img || !await this.img.handle(req, res)) return empty(404);
          return;
        }
        const record = this.collision?.records.get(pathname);
        if (!record) return empty(404);
        const filename = path.resolve(this.collision.root, record.path), actual = await fsp.realpath(filename);
        if (!inside(this.collision.root, actual)) throw fail('INTEGRITY', 'COL asset leaves configured root');
        const data = await boundedFile(actual, 32 * 1024 * 1024, signal);
        const signature = data.toString('ascii', 0, 4), version = signature === 'COLL' ? 1 : signature === 'COL2' ? 2 : signature === 'COL3' ? 3 : 0;
        const name = data.subarray(8, 30).toString('ascii').split('\0')[0];
        if (data.length !== record.bytes || data.length !== data.readUInt32LE(4) + 8 || version !== record.version || name !== record.headerName ||
            data.readUInt16LE(30) !== record.headerModelID || crc32(data) !== record.crc32 || crypto.createHash('sha256').update(data).digest('hex') !== record.sha256) throw fail('INTEGRITY', 'COL asset differs from catalog');
        return this.reply(req, res, data, 'application/octet-stream', signal, record.sha256);
      });
    } catch (error) {
      if (!res.destroyed && !res.headersSent) empty(error.code === 'ENOENT' ? 404 : 503);
      else if (!res.destroyed) res.destroy();
    } finally { this.controllers.delete(controller); req.removeListener('aborted', abort); res.removeListener('close', abort); }
  }
  async close() {
    this.closed = true; for (const controller of this.controllers) controller.abort();
    await this.gate.close(); await this.img?.close(); this.modelManifest = null; this.collision = null;
  }
}
module.exports = { create: options => new StockNativeAssets(options) };
