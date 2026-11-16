'use strict';
// SPDX-License-Identifier: AGPL-3.0-only
const assert = require('node:assert/strict');
const fs = require('node:fs/promises');
const http = require('node:http');
const crypto = require('node:crypto');
const { StockIMGAssetProvider } = require('../../stock_img_assets');
let checks = 0;
function check(value, label) { checks++; assert(value, label); }
async function reject(operation, code) {
  checks++; await assert.rejects(operation, error => error.code === code);
}
async function open(config, limits) { return StockIMGAssetProvider.open({ indexPath: config.index, archivePaths: config.archives, limits }); }
async function main() {
  const config = JSON.parse(await fs.readFile(process.argv[2], 'utf8'));
  const provider = await open(config);
  try {
    check(provider.resolve('PANEL.DFF').state === 'available', 'RW case-insensitive exact lookup');
    check(provider.resolve('child.txd').state === 'ambiguous', 'duplicate source name remains ambiguous');
    check(provider.resolve('../panel.dff').state === 'missing', 'traversal cannot resolve');
    check(provider.resolve('bad.dff').state === 'unavailable', 'bad declared extent unavailable');
    check(provider.resolve('nonzero.txd').state === 'unavailable', 'nonzero allocation tail unavailable');
    check(provider.resolve('wholezero.txd').state === 'unavailable', 'whole extra padding sector unavailable');
    check(provider.resolve('uv_anim.dff').state === 'unavailable', 'unsupported RW root explicit');
    for (const name of ['panel.dff', 'extra.dff', 'unique.txd']) {
      const expected = await fs.readFile(config.expected[name]);
      await provider.withAsset(name, data => {
        check(data.equals(expected), 'exact logical bytes including legitimate payload zeros');
        if (name === 'panel.dff') check(data[data.length - 1] === 0, 'trailing payload zeros retained');
      });
    }
    await reject(() => provider.withAsset('child.txd', () => {}), 'AMBIGUOUS');
    await reject(() => provider.withAsset('missing.dff', () => {}), 'MISSING');
    const server = http.createServer((req, res) => {
      provider.handle(req, res).then(handled => { if (!handled) { res.writeHead(404); res.end(); } }).catch(error => { res.destroy(error); });
    });
    await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
    try {
      const base = `http://127.0.0.1:${server.address().port}`;
      const file = provider.resolve('panel.dff').file, target = base + '/' + file.path;
      const response = await fetch(target);
      check(response.status === 200 && response.headers.get('content-length') === String(file.bytes), 'HTTP exact length');
      check(Buffer.from(await response.arrayBuffer()).equals(await fs.readFile(config.expected['panel.dff'])), 'actual HTTP logical bytes');
      const head = await fetch(target, { method: 'HEAD' });
      check(head.status === 200 && (await head.arrayBuffer()).byteLength === 0, 'HEAD no body');
      check((await fetch(target, { method: 'POST' })).status === 405, 'method bound');
      check((await fetch(target, { headers: { Range: 'bytes=0-4' } })).status === 416, 'partial ranges not substituted');
      check((await fetch(target + '?alternate=1')).status === 404, 'query cannot alias asset identity');
      check((await fetch(base + '/game/native/stock-img/' + '0'.repeat(64) + '.dff')).status === 404, 'unknown hash unavailable');
      check((await fetch(base + '/outside/panel.dff')).status === 404, 'unrelated URL not handled');
    } finally { await new Promise(resolve => server.close(resolve)); }
    const original = await fs.readFile(config.archives['generated.img']);
    const file = provider.resolve('panel.dff').file;
    const changed = Buffer.from(original); changed[file.offset + 40] ^= 1;
    await fs.writeFile(config.archives['generated.img'], changed);
    await reject(() => provider.withAsset('panel.dff', () => {}), 'INTEGRITY');
    const reopened = await open(config);
    try { await reject(() => reopened.withAsset('panel.dff', () => {}), 'INTEGRITY'); }
    finally { await reopened.close(); await fs.writeFile(config.archives['generated.img'], original); }
  } finally { await provider.close(); }
  await reject(() => provider.withAsset('panel.dff', () => {}), 'CLOSED');

  const budget = await open(config, { concurrent: 2, pending: 1, residentBytes: 1024 });
  try {
    let entered; const started = new Promise(resolve => { entered = resolve; });
    let release; const barrier = new Promise(resolve => { release = resolve; });
    const first = budget.withAsset('panel.dff', async () => { entered(); await barrier; });
    await started;
    const controller = new AbortController();
    const pending = budget.withAsset('extra.dff', () => {}, { signal: controller.signal });
    check(budget.status.active === 1 && budget.status.pending === 1 && budget.status.residentBytes <= 1024, 'resident bytes prevent second allocation');
    await reject(() => budget.withAsset('unique.txd', () => {}), 'BUSY');
    controller.abort(); await reject(() => pending, 'ABORTED');
    check(budget.status.pending === 0, 'cancelled queued work removed');
    release(); await first;
    check(budget.status.active === 0 && budget.status.residentBytes === 0, 'resident reservation released');
    let activeEntered;const activeStarted = new Promise(resolve => { activeEntered = resolve; });
    const active = budget.withAsset('panel.dff', async (_, __, signal) => {
      activeEntered(); await new Promise(resolve => signal.addEventListener('abort', resolve, { once: true }));
    });
    await activeStarted; const rejected = reject(() => active, 'ABORTED'); await budget.close(); await rejected;
    check(budget.status.active === 0 && budget.status.residentBytes === 0, 'closing cancels active callback and releases bytes');
  } finally { await budget.close(); }

  for (const item of config.invalidIndexes) await reject(() => StockIMGAssetProvider.open({ indexPath: item, archivePaths: config.archives }), 'INDEX');
  await reject(() => open(config, { concurrent: 0 }), 'LIMIT');
  await reject(() => open(config, { indexBytes: 2 }), 'LIMIT');
  let ownerReads = 0;
  if (config.owner) {
    const actual = await StockIMGAssetProvider.open(config.owner);
    try {
      for (const row of config.owner.expected) {
        await actual.withAsset(row.name, data => {
          check(crypto.createHash('sha256').update(data).digest('hex') === row.sha256, 'exact owned range digest');
          check(data.length === row.bytes, 'exact owned logical range length'); ownerReads++;
        });
      }
      for (const name of ['barrier.txd', 'changeme.txd', 'kbmiscfrn1.txd', 'lawest1.txd']) check(actual.resolve(name).state === 'ambiguous', 'actual archive duplicate explicit');
    } finally { await actual.close(); }
  }
  console.log(JSON.stringify({ status: 'PASS', checks, ownerReads, scope: 'Exact bounded indexed IMG bytes and HTTP serving; native import/rendering remains separate.' }));
}
main().catch(error => { console.error(error); process.exitCode = 1; });
