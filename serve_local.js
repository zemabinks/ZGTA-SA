#!/usr/bin/env node
// Serve archived files from this Mac and forward the original game's live APIs.
const fs = require('fs');
const http = require('http');
const https = require('https');
const path = require('path');
const crypto = require('crypto');
const {pipeline} = require('stream/promises');

const ROOT = path.join(__dirname, 'local-only', 'site');
const LOCAL_ONLY = path.join(__dirname, 'local-only');
const MANIFEST = path.join(LOCAL_ONLY, 'manifest.json');
const PORT = Number(process.env.PORT || 8765);
const HOST = '127.0.0.1';
const UPSTREAM = 'play.samp.directory';
const COMMUNITY_DISCORD = 'https://discord.gg/Cg39cguVUa';
const pendingAssets = new Map();
const unavailableAssets = new Set();
let manifestWrite = Promise.resolve();
const COMMUNITY_SCRIPT = `<script>
(() => {
  const invite = ${JSON.stringify(COMMUNITY_DISCORD)};
  function addCommunityLink() {
    const login = document.querySelector('a[href*="/api/auth/discord/login"]');
    if (!login) return;
    const originalLogin = new URL(login.getAttribute('href'), 'https://play.samp.directory').href;
    if (login.href !== originalLogin) login.href = originalLogin;
    login.target = '_blank';
    login.rel = 'noopener noreferrer';
    if (login.textContent !== 'Log in on the original site') login.textContent = 'Log in on the original site';
    let community = document.getElementById('zgta-community-discord');
    if (!community) {
      community = document.createElement('a');
      community.id = 'zgta-community-discord';
      community.href = invite;
      community.target = '_blank';
      community.rel = 'noopener noreferrer';
      community.textContent = 'ZGTA:SA community Discord';
      community.className = login.className;
      community.style.cssText = 'display:inline-flex;align-items:center;justify-content:center;margin-top:8px;';
      login.insertAdjacentElement('afterend', community);
    }
    if (!document.getElementById('zgta-solo-world')) {
      const solo = document.createElement('a');
      solo.id = 'zgta-solo-world';
      solo.href = '/tools/world';
      solo.textContent = 'Solo free roam (no Discord)';
      solo.className = login.className;
      solo.style.cssText = 'display:inline-flex;align-items:center;justify-content:center;margin-top:8px;';
      community.insertAdjacentElement('afterend', solo);
    }
  }
  new MutationObserver(addCommunityLink).observe(document.documentElement, {childList:true,subtree:true});
  addCommunityLink();
})();
</script>`;
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json', '.wasm': 'application/wasm',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp',
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

function recordCachedAsset(pathname, filename, bytes, sha256, contentType) {
  manifestWrite = manifestWrite.catch(() => {}).then(async () => {
    const manifest = JSON.parse(await fs.promises.readFile(MANIFEST, 'utf8'));
    manifest.files[`https://${UPSTREAM}${pathname}`] = {
      path: path.relative(LOCAL_ONLY, filename).split(path.sep).join('/'),
      bytes, sha256, content_type: contentType, status: 'ok',
    };
    manifest.captured_at = new Date().toISOString();
    const partial = MANIFEST + '.partial';
    await fs.promises.writeFile(partial, JSON.stringify(manifest, null, 2) + '\n');
    await fs.promises.rename(partial, MANIFEST);
  });
  return manifestWrite;
}

async function cachePublicAsset(req, pathname, filename) {
  await fs.promises.mkdir(path.dirname(filename), {recursive: true});
  const partial = filename + `.${process.pid}.partial`;
  try {
    const result = await new Promise((resolve, reject) => {
      const upstream = https.get({hostname: UPSTREAM, path: req.url,
        headers: {'user-agent': 'ZGTA-SA-local-preservation/1.0', 'accept-encoding': 'identity'}}, response => {
        if (response.statusCode !== 200) {
          response.resume();
          const error = new Error(`Source returned ${response.statusCode}`);
          error.statusCode = response.statusCode;
          return reject(error);
        }
        const hash = crypto.createHash('sha256');
        let bytes = 0;
        response.on('data', chunk => { hash.update(chunk); bytes += chunk.length; });
        pipeline(response, fs.createWriteStream(partial))
          .then(() => resolve({bytes, sha256: hash.digest('hex'),
            contentType: response.headers['content-type'] || 'application/octet-stream'}))
          .catch(reject);
      });
      upstream.on('error', reject);
    });
    await fs.promises.rename(partial, filename);
    try {
      await recordCachedAsset(pathname, filename, result.bytes, result.sha256, result.contentType);
    } catch (error) {
      await fs.promises.rm(filename, {force: true});
      throw error;
    }
  } finally {
    await fs.promises.rm(partial, {force: true});
  }
}

function serve(req, res) {
  securityHeaders(res);
  let pathname;
  try { pathname = new URL(req.url, `http://${HOST}:${PORT}`).pathname; }
  catch { res.writeHead(400); return res.end('Invalid URL'); }
  if (pathname.startsWith('/api/')) return proxyHttp(req, res);
  let decoded;
  try { decoded = decodeURIComponent(pathname); } catch { res.writeHead(400); return res.end(); }
  const page = ['/', '/ru', '/es', '/pt', '/tr', '/offline', '/tools/world'].includes(decoded)
    ? (decoded.replace(/\/$/, '') + '/index.html') : decoded;
  const filename = path.resolve(ROOT, '.' + page);
  if (!filename.startsWith(ROOT + path.sep)) { res.writeHead(403); return res.end(); }
  fs.stat(filename, (error, stat) => {
    if (error || !stat.isFile()) {
      if (process.env.ZGTA_DEBUG_MISSING === '1') console.error(`Missing local asset: ${pathname}`);
      const cacheable = !decoded.endsWith('/') &&
        /^\/(?:game|reference|tools\/map|_next\/static)\//.test(decoded);
      if (cacheable && ['GET', 'HEAD'].includes(req.method) && !unavailableAssets.has(decoded)) {
        if (!pendingAssets.has(decoded)) {
          const pending = cachePublicAsset(req, pathname, filename)
            .finally(() => pendingAssets.delete(decoded));
          pendingAssets.set(decoded, pending);
        }
        return pendingAssets.get(decoded).then(() => serve(req, res), failure => {
          if (failure.statusCode === 404) unavailableAssets.add(decoded);
          res.writeHead(failure.statusCode || 502);
          res.end('Public asset unavailable');
        });
      }
      if (req.method === 'GET' && (req.headers['sec-fetch-dest'] === 'document' ||
          (req.headers.accept || '').includes('text/html'))) {
        res.writeHead(302, {Location: `https://samp.directory${req.url}`});
        return res.end();
      }
      res.writeHead(404);
      return res.end('Not in local archive');
    }
    const type = MIME[path.extname(filename)] || 'application/octet-stream';
    if (type.startsWith('text/html')) {
      const html = fs.readFileSync(filename, 'utf8');
      const gamePage = ['/', '/ru', '/es', '/pt', '/tr'].includes(decoded);
      const content = Buffer.from(gamePage ? html.replace('</body>', COMMUNITY_SCRIPT + '</body>') : html);
      res.setHeader('Content-Type', type);
      res.setHeader('Content-Length', content.length);
      res.setHeader('Accept-Ranges', 'none');
      return res.end(req.method === 'HEAD' ? undefined : content);
    }
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
