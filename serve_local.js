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
const CONNECTED = process.env.ZGTA_CONNECTED === '1';
const SELFHOST = process.env.ZGTA_SELFHOST === '1';
if (CONNECTED && SELFHOST) throw new Error('Choose connected or self-hosted mode.');
const PORT = Number(process.env.PORT || (CONNECTED ? 9443 : SELFHOST ? 8766 : 8765));
const HOST = SELFHOST ? (process.env.BIND_HOST || '127.0.0.1') : '127.0.0.1';
if (SELFHOST && HOST !== '127.0.0.1' && HOST !== '::1' &&
    (!(process.env.ZGTA_JOIN_CODE || process.env.ZGTA_JOIN_CODE_FILE) || !process.env.ZGTA_ALLOWED_HOSTS))
  throw new Error('Network hosting requires a join code and ZGTA_ALLOWED_HOSTS.');
const localGame = SELFHOST ? require('./selfhost_backend') : null;
const allowedHosts = new Set([`127.0.0.1:${PORT}`, `localhost:${PORT}`,
  ...(process.env.ZGTA_ALLOWED_HOSTS || '').split(',').map(host => host.trim()).filter(Boolean)]);
const UPSTREAM = 'play.samp.directory';
const PUBLIC_ORIGIN = CONNECTED ? `https://${UPSTREAM}` : `http://127.0.0.1:${PORT}`;
const COMMUNITY_DISCORD = 'https://discord.gg/Cg39cguVUa';
const pendingAssets = new Map();
const unavailableAssets = new Set();
let manifestWrite = Promise.resolve();
const COMMUNITY_SCRIPT = `<script>
(() => {
  const invite = ${JSON.stringify(COMMUNITY_DISCORD)};
  const connected = ${CONNECTED};
  const selfhost = ${SELFHOST};
  function localCopy() {
    if (!selfhost) return;
    const welcome = document.querySelector('[data-welcome="true"]');
    if (!welcome) return;
    welcome.setAttribute('aria-label', 'Welcome to ZGTA:SA');
    welcome.querySelector('h2')?.setAttribute('aria-label', 'Welcome to ZGTA:SA');
    if (!document.getElementById('zgta-welcome-style')) {
      const style = document.createElement('style');
      style.id = 'zgta-welcome-style';
      style.textContent = '[data-welcome="true"] h2 canvas{display:none!important}[data-welcome="true"] h2::before{content:"Welcome to ZGTA:SA";display:block;font:700 clamp(25px,4vw,37px) system-ui;color:#e6eeff;letter-spacing:-.03em;padding:2px 0 8px}';
      document.head.append(style);
    }
    const replacements = [
      ['Welcome to samp.directory', 'Welcome to ZGTA:SA'],
      ['San Andreas, in your browser, with everybody else.', 'San Andreas, in your browser, with players on this local server.'],
      ['Log in with Discord to play: it keeps your money, levels and achievements.', 'No Discord login is needed. Your name, cash, cars, homes, and jobs are saved on this Mac.'],
      ['Get a job', 'Local jobs'],
      ['The job centre is just below the Conference Center, right where you start: walk into the yellow arrow, or type /jobs. Every job has a tutorial whenever you want one: /tutorial.', 'Press F6 in the world to start a local job, see your progress, and claim its payout.'],
      ['Save for a car, then a home', 'Cars and homes'],
      ['Once you’ve looked at the jobs, the First steps card under your money shows the next goal, its price and where it is.', 'Earn cash from local jobs, buy a car or home in the F6 panel, and spawn an owned car nearby.'],
      ['Everybody you see is another player. Press T to chat, and work a job side by side.', 'Press T to chat with other players connected to this Mac.'],
    ];
    const walker = document.createTreeWalker(welcome, NodeFilter.SHOW_TEXT);
    while (walker.nextNode()) {
      const node = walker.currentNode;
      if (node.parentElement?.closest('script,style')) continue;
      for (const [from, to] of replacements) if (node.data.includes(from)) node.data = node.data.replace(from, to);
    }
  }
  function addCommunityLink() {
    localCopy();
    const login = document.querySelector('a[href*="/api/auth/discord/login"]');
    if (!login) return;
    if (selfhost) {
      login.href = '#';
      login.onclick = event => event.preventDefault();
      login.textContent = 'Local account active — no Discord required';
    } else if (!connected) {
      const originalLogin = new URL(login.getAttribute('href'), 'https://play.samp.directory').href;
      if (login.href !== originalLogin) login.href = originalLogin;
      login.target = '_blank';
      login.rel = 'noopener noreferrer';
      if (login.textContent !== 'Log in on the original site') login.textContent = 'Log in on the original site';
    }
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
  let scheduled = false;
  new MutationObserver(() => {
    if (scheduled) return;
    scheduled = true;
    requestAnimationFrame(() => {scheduled = false; addCommunityLink();});
  }).observe(document.documentElement, {childList:true,subtree:true});
  addCommunityLink();
})();
</script>`;
const GAMEPLAY_SCRIPT = SELFHOST ? '<script defer src="/local-gameplay.js"></script>' : '';
const SELFHOST_TIPS_SCRIPT = SELFHOST ? `<script>
try {
  const key = 'world-tune';
  const stored = JSON.parse(localStorage.getItem(key) || '{}');
  const settings = stored && typeof stored === 'object' && !Array.isArray(stored) ? stored : {};
  settings.hideTips = true;
  localStorage.setItem(key, JSON.stringify(settings));
} catch {}
</script>` : '';
const MIME = {
  '.html': 'text/html; charset=utf-8', '.js': 'text/javascript; charset=utf-8',
  '.css': 'text/css; charset=utf-8', '.json': 'application/json; charset=utf-8',
  '.webmanifest': 'application/manifest+json', '.wasm': 'application/wasm',
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg', '.webp': 'image/webp',
  '.ico': 'image/x-icon', '.svg': 'image/svg+xml', '.woff': 'font/woff',
  '.woff2': 'font/woff2', '.bin': 'application/octet-stream',
  '.dff': 'application/octet-stream', '.txd': 'application/octet-stream',
  '.glb': 'model/gltf-binary', '.wav': 'audio/wav',
  '.mp3': 'audio/mpeg', '.m4a': 'audio/mp4', '.aac': 'audio/aac',
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
    if (!CONNECTED && headers.location && headers.location.startsWith(`https://${UPSTREAM}/`)) {
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
  if (SELFHOST) {
    if (!allowedHosts.has(req.headers.host || '')) {res.writeHead(421); return res.end('Host not allowed');}
    if (req.headers.origin) {
      try {
        if (new URL(req.headers.origin).host !== req.headers.host) {
          res.writeHead(403); return res.end('Origin not allowed');
        }
      } catch {res.writeHead(403); return res.end('Origin not allowed');}
    }
  }
  let pathname;
  try { pathname = new URL(req.url, PUBLIC_ORIGIN).pathname; }
  catch { res.writeHead(400); return res.end('Invalid URL'); }
  // Discord returns from another site, so the LAN join cookie may be withheld
  // by SameSite=Strict. The callback separately validates a bound OAuth state
  // and the existing local player cookie before touching an account.
  if (SELFHOST && pathname === '/api/local/discord/callback' && req.method === 'GET')
    return localGame.discordCallback(req, res);
  if (SELFHOST && localGame.requiresJoinCode) {
    if (pathname === '/join' && req.method === 'GET') return localGame.join(req, res);
    if (pathname === '/api/local/join') return localGame.join(req, res);
    if (!localGame.authorized(req)) {
      if (req.headers.accept?.includes('text/html') || req.headers['sec-fetch-dest'] === 'document') {
        res.writeHead(302, {Location: '/join'}); return res.end();
      }
      res.writeHead(401); return res.end('Access code required');
    }
  }
  // The game document needs its cookie before JavaScript opens the socket.
  // Assets are fetched concurrently and must not each create an account.
  if (SELFHOST && req.method === 'GET' &&
      (pathname === '/' || pathname === '/index.html' ||
        req.headers['sec-fetch-dest'] === 'document'))
    localGame.ensurePlayer(req, res);
  if (SELFHOST && pathname === '/local-gameplay.js' && req.method === 'GET') {
    const content = fs.readFileSync(path.join(__dirname, 'local_gameplay.js'));
    res.writeHead(200, {'Content-Type': 'text/javascript; charset=utf-8',
      'Content-Length': content.length, 'Cache-Control': 'no-store'});
    return res.end(content);
  }
  if (pathname.startsWith('/api/')) {
    if (!SELFHOST) return proxyHttp(req, res);
    return localGame.http(req, res).catch(error => {
      if (!res.headersSent) {res.writeHead(500); res.end('Local game error');}
      console.error('Local API error:', error.message);
    });
  }
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
      if (!SELFHOST && cacheable && ['GET', 'HEAD'].includes(req.method) && !unavailableAssets.has(decoded)) {
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
      if (!SELFHOST && req.method === 'GET' && (req.headers['sec-fetch-dest'] === 'document' ||
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
      const content = Buffer.from(gamePage ? html
        .replace('<head>', '<head>' + SELFHOST_TIPS_SCRIPT)
        .replace('</body>', COMMUNITY_SCRIPT + GAMEPLAY_SCRIPT + '</body>') : html);
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

const server = CONNECTED
  ? https.createServer({
      key: fs.readFileSync(path.join(LOCAL_ONLY, 'connected.key')),
      cert: fs.readFileSync(path.join(LOCAL_ONLY, 'connected.crt')),
    }, serve)
  : http.createServer(serve);
server.on('upgrade', (req, socket, head) => {
  if (SELFHOST) {
    if (!allowedHosts.has(req.headers.host || '')) return socket.destroy();
    if (req.headers.origin) {
      try { if (new URL(req.headers.origin).host !== req.headers.host) return socket.destroy(); }
      catch { return socket.destroy(); }
    }
  }
  if (req.url.startsWith('/api/')) SELFHOST ? localGame.upgrade(req, socket, head) : proxyWebSocket(req, socket, head);
  else socket.destroy();
});
server.listen(PORT, HOST, () => console.log(`ZGTA:SA local mirror: ${PUBLIC_ORIGIN}/`));
