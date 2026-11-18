#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Optional isolated loopback helper. No backend, saves, imports or hydration.
'use strict';
const fs = require('node:fs'), path = require('node:path'), http = require('node:http'), crypto = require('node:crypto');
const {create} = require('./native_radio_server');
const allowedPath = pathname => pathname === '/game/radio/native/index' || /^\/game\/radio\/native\/track\/\d+\.wav$/.test(pathname);
function createHandler({radio, token, port}) {
  const secret = Buffer.from(token);
  if (!/^[a-f0-9]{64}$/.test(token)) throw Error('Use a private 64-character random hexadecimal token');
  return async function handle(req, res) {
    const reject = (code, text) => {res.writeHead(code, {'content-type': 'text/plain', 'cache-control': 'no-store'}); res.end(text);};
    if (![ `127.0.0.1:${port}`, `localhost:${port}` ].includes(req.headers.host)) return reject(403, 'Forbidden');
    const supplied = Buffer.from(typeof req.headers['x-zgta-radio-token'] === 'string' ? req.headers['x-zgta-radio-token'] : '');
    if (supplied.length !== secret.length || !crypto.timingSafeEqual(supplied, secret)) return reject(403, 'Forbidden');
    if (!['GET', 'HEAD'].includes(req.method)) return reject(405, 'Method not allowed');
    let url;
    try {url = new URL(req.url, `http://127.0.0.1:${port}`);} catch {return reject(400, 'Bad request');}
    // Permit relative origin-form requests only; no proxying or arbitrary files.
    if (!req.url.startsWith('/') || req.url.startsWith('//') || !allowedPath(url.pathname)) return reject(404, 'Not found');
    try {await radio.handle(req, res, url.pathname);}
    catch {if (!res.headersSent) reject(503, 'Owner radio audio is unavailable'); else res.destroy();}
  };
}
function configuredHandler(environment, port) {
  const names = ['ZGTA_RADIO_CONFIGURATION', 'ZGTA_RADIO_CACHE', 'ZGTA_RADIO_DECODER', 'ZGTA_RADIO_TOKEN_FILE'];
  for (const name of names) if (!environment[name] || !path.isAbsolute(environment[name])) throw Error(`Set ${name} to an absolute private path`);
  for (const name of names) {
    let node = path.resolve(environment[name]);
    while (node !== path.dirname(node)) {
      try {if (fs.lstatSync(node).isSymbolicLink()) throw Error('Isolated radio paths must have regular ancestors');}
      catch (error) {if (error.code !== 'ENOENT') throw error;}
      node = path.dirname(node);
    }
  }
  const tokenFile = environment.ZGTA_RADIO_TOKEN_FILE, stat = fs.statSync(tokenFile);
  if (!stat.isFile() || stat.size > 128 || (stat.mode & 0o077)) throw Error('Use a private token file with owner-only permissions');
  if (!fs.statSync(environment.ZGTA_RADIO_DECODER).isFile()) throw Error('Use a regular radio decoder executable');
  fs.accessSync(environment.ZGTA_RADIO_DECODER, fs.constants.X_OK);
  if (fs.existsSync(environment.ZGTA_RADIO_CACHE) && !fs.statSync(environment.ZGTA_RADIO_CACHE).isDirectory()) throw Error('Use a radio cache directory');
  const token = fs.readFileSync(tokenFile, 'utf8').trim();
  const radio = create({configuration: environment.ZGTA_RADIO_CONFIGURATION,
    cache: environment.ZGTA_RADIO_CACHE, decoder: environment.ZGTA_RADIO_DECODER, includeCustom: false});
  // Validate registration/discovery before opening a listener. Nothing decodes.
  if (!radio.tracks().length) throw Error('Register original radio before starting the helper');
  return createHandler({radio, token, port});
}
if (require.main === module) {
  const [flag, text, ...extra] = process.argv.slice(2), port = Number(text);
  if (flag !== '--port' || extra.length || !/^\d+$/.test(text || '') || !Number.isInteger(port) || port < 1024 || port > 65535)
    throw Error('Usage: node serve_development_radio.js --port <unused-loopback-port>');
  const server = http.createServer(configuredHandler(process.env, port));
  server.maxHeadersCount = 32; server.headersTimeout = 10000; server.requestTimeout = 120000;
  server.listen(port, '127.0.0.1', () => console.log(`Isolated original-radio helper: http://127.0.0.1:${port}`));
}
module.exports = {createHandler, configuredHandler, allowedPath};
