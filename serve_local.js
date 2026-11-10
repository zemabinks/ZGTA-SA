#!/usr/bin/env node
// Serve archived files from this Mac and forward the original game's live APIs.
const fs = require('fs');
const http = require('http');
const https = require('https');
const path = require('path');

const ROOT = path.join(__dirname, 'local-only', 'site');
const PORT = Number(process.env.PORT || 8765);
const HOST = '127.0.0.1';
const UPSTREAM = 'play.samp.directory';
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json', '.wasm': 'application/wasm',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.ico': 'image/x-icon', '.svg': 'image/svg+xml', '.woff': 'font/woff',
  '.woff2': 'font/woff2', '.bin': 'application/octet-stream',
  '.dff': 'application/octet-stream', '.txd': 'application/octet-stream',
  '.glb': 'model/gltf-binary', '.wav': 'audio/wav',
};

function securityHeaders(res) {
  res.setHeader('Cross-Origin-Opener-Policy', 'same-origin');
  res.setHeader('Cross-Origin-Embedder-Policy', 'require-corp');
  res.setHeader('Cross-Origin-Resource-Policy', 'same-origin');
}

function proxyHeaders(headers) {
  const result = {...headers, host: UPSTREAM, origin: `https://${UPSTREAM}`};
  delete result.connection;
  delete result['content-length'];
  delete result['accept-encoding'];
  if (result.referer) result.referer = result.referer.replace(/^http:\/\/127\.0\.0\.1:\d+/, `https://${UPSTREAM}`);
  return result;
}

function proxyHttp(req, res) {
  const remote = https.request({hostname: UPSTREAM, port: 443, path: req.url,
    method: req.method, headers: proxyHeaders(req.headers)}, upstream => {
    const headers = {...upstream.headers};
    delete headers['content-security-policy'];
    if (headers.location && headers.location.startsWith(`https://${UPSTREAM}/`)) {
      headers.location = headers.location.replace(`https://${UPSTREAM}`, `http://${HOST}:${PORT}`);
    }
    res.writeHead(upstream.statusCode, headers);
    upstream.pipe(res);
  });
  remote.on('error', error => {res.writeHead(502); res.end(`Live service unavailable: ${error.message}`);});
  req.pipe(remote);
}

function proxyWebSocket(req, socket, head) {
  const remote = https.request({hostname: UPSTREAM, port: 443, path: req.url,
    method: 'GET', headers: {...proxyHeaders(req.headers), connection: 'Upgrade', upgrade: 'websocket'}});
  remote.on('upgrade', (response, upstreamSocket, upstreamHead) => {
    let status = `HTTP/1.1 101 Switching Protocols\r\n`;
    for (const [key, value] of Object.entries(response.headers)) status += `${key}: ${value}\r\n`;
    socket.write(status + '\r\n');
    if (upstreamHead.length) socket.write(upstreamHead);
    if (head.length) upstreamSocket.write(head);
    socket.pipe(upstreamSocket).pipe(socket);
    socket.on('error', () => upstreamSocket.destroy());
    upstreamSocket.on('error', () => socket.destroy());
  });
  remote.on('response', response => {
    socket.write(`HTTP/1.1 ${response.statusCode} ${response.statusMessage}\r\nConnection: close\r\n\r\n`);
    socket.end();
  });
  remote.on('error', () => socket.destroy());
  remote.end();
}

function serve(req, res) {
  securityHeaders(res);
  const pathname = new URL(req.url, `http://${HOST}:${PORT}`).pathname;
  if (pathname.startsWith('/api/')) return proxyHttp(req, res);
  let decoded;
  try { decoded = decodeURIComponent(pathname); } catch { res.writeHead(400); return res.end(); }
  const filename = path.resolve(ROOT, '.' + (decoded === '/' ? '/index.html' : decoded));
  if (!filename.startsWith(ROOT + path.sep)) { res.writeHead(403); return res.end(); }
  fs.stat(filename, (error, stat) => {
    if (error || !stat.isFile()) { res.writeHead(404); return res.end('Not in local archive'); }
    const type = MIME[path.extname(filename)] || 'application/octet-stream';
    let start = 0, end = stat.size - 1;
    const match = /^bytes=(\d*)-(\d*)$/.exec(req.headers.range || '');
    if (match && (match[1] || match[2])) {
      if (match[1]) { start = Number(match[1]); if (match[2]) end = Math.min(end, Number(match[2])); }
      else start = Math.max(0, stat.size - Number(match[2]));
      if (start > end || start >= stat.size) { res.writeHead(416, {'Content-Range': `bytes */${stat.size}`}); return res.end(); }
      res.statusCode = 206;
      res.setHeader('Content-Range', `bytes ${start}-${end}/${stat.size}`);
    }
    res.setHeader('Content-Type', type);
    res.setHeader('Content-Length', end - start + 1);
    res.setHeader('Accept-Ranges', 'bytes');
    if (req.method === 'HEAD') return res.end();
    fs.createReadStream(filename, {start, end}).pipe(res);
  });
}

const server = http.createServer(serve);
server.on('upgrade', (req, socket, head) => {
  if (req.url.startsWith('/api/')) proxyWebSocket(req, socket, head);
  else socket.destroy();
});
server.listen(PORT, HOST, () => console.log(`ZGTA:SA local mirror: http://${HOST}:${PORT}/`));
