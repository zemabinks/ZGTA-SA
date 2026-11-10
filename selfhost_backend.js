// An independent, local-only starting point for the archived browser client.
// This intentionally implements a small, documented part of the live protocol.
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const MAX_FRAME = 64 * 1024;
const MAX_PEERS = 32;
const STATE_FILE = path.join(__dirname, 'local-only', 'selfhost', 'players.json');
const COOKIE = 'zgta_local';
const JOIN_CODE = process.env.ZGTA_JOIN_CODE || '';
if (JOIN_CODE && JOIN_CODE.length < 12) throw new Error('ZGTA_JOIN_CODE must be at least 12 characters.');
const ACCESS_TOKEN = JOIN_CODE ? crypto.createHmac('sha256', JOIN_CODE).update('ZGTA:SA local access v1').digest('hex') : '';

function json(res, status, body) {
  const data = Buffer.from(JSON.stringify(body));
  res.writeHead(status, {'Content-Type': 'application/json; charset=utf-8',
    'Content-Length': data.length, 'Cache-Control': 'no-store'});
  res.end(data);
}

function readBody(req, limit = 16 * 1024) {
  return new Promise((resolve, reject) => {
    let size = 0;
    const chunks = [];
    req.on('data', chunk => {
      size += chunk.length;
      if (size > limit) { reject(new Error('Request too large')); req.destroy(); }
      else chunks.push(chunk);
    });
    req.on('end', () => {
      try { resolve(JSON.parse(Buffer.concat(chunks).toString('utf8') || '{}')); }
      catch { reject(new Error('Invalid JSON')); }
    });
    req.on('error', reject);
  });
}

function cookieId(req) {
  const match = /(?:^|;\s*)zgta_local=([0-9a-f]{32})(?:;|$)/.exec(req.headers.cookie || '');
  return match ? match[1] : null;
}

function safeName(value) {
  return String(value || '').trim().replace(/[^\p{L}\p{N} _.-]/gu, '').slice(0, 24);
}

function finite(value, fallback = 0) { return Number.isFinite(value) ? value : fallback; }

class LocalGame {
  constructor() {
    this.players = new Map();
    this.peers = new Set();
    this.chat = [];
    this.chatSequence = 0;
    this.nextNumber = 1;
    try {
      const data = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
      for (const [id, value] of Object.entries(data.players || {})) {
        if (!/^[0-9a-f]{32}$/.test(id)) continue;
        this.players.set(id, {number: this.nextNumber++, name: safeName(value.name) || 'Local player',
          cash: finite(value.cash), settings: value.settings && typeof value.settings === 'object' ? value.settings : {}});
      }
    } catch (error) { if (error.code !== 'ENOENT') console.error('Could not load local players:', error.message); }
    this.saveTimer = null;
    this.tick = setInterval(() => this.broadcastPositions(), 200);
    this.tick.unref();
  }

  save() {
    if (this.saveTimer) return;
    this.saveTimer = setTimeout(() => {
      this.saveTimer = null;
      try { this.flushSync(); }
      catch (error) { console.error('Could not save local players:', error.message); }
    }, 300);
    this.saveTimer.unref();
  }

  flushSync() {
    if (this.saveTimer) {clearTimeout(this.saveTimer); this.saveTimer = null;}
    const players = Object.fromEntries([...this.players].map(([id, p]) =>
      [id, {name: p.name, cash: p.cash, settings: p.settings}]));
    fs.mkdirSync(path.dirname(STATE_FILE), {recursive: true});
    fs.writeFileSync(STATE_FILE + '.partial', JSON.stringify({version: 1, players}, null, 2) + '\n', {mode: 0o600});
    fs.renameSync(STATE_FILE + '.partial', STATE_FILE);
  }

  ensurePlayer(req, res) {
    let id = cookieId(req);
    if (!id || !this.players.has(id)) {
      id = crypto.randomBytes(16).toString('hex');
      this.players.set(id, {number: this.nextNumber++, name: `Local ${this.nextNumber - 1}`,
        cash: 0, settings: {}});
      const secure = req.headers['x-forwarded-proto'] === 'https' ? '; Secure' : '';
      if (res) res.setHeader('Set-Cookie', `${COOKIE}=${id}; Path=/; HttpOnly; SameSite=Lax${secure}`);
      this.save();
    }
    return {id, player: this.players.get(id)};
  }

  authorized(req) {
    if (!JOIN_CODE) return true;
    const match = /(?:^|;\s*)zgta_access=([0-9a-f]{64})(?:;|$)/.exec(req.headers.cookie || '');
    return !!match && crypto.timingSafeEqual(Buffer.from(match[1], 'hex'), Buffer.from(ACCESS_TOKEN, 'hex'));
  }

  async join(req, res) {
    if (req.method === 'GET') {
      const content = Buffer.from(`<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Join ZGTA:SA</title><style>body{font:16px system-ui;background:#101114;color:white;max-width:28rem;margin:12vh auto;padding:1rem}input,button{font:inherit;padding:.7rem;border-radius:.4rem}input{width:100%;box-sizing:border-box}button{margin-top:1rem;cursor:pointer}p{line-height:1.5}</style><h1>Join ZGTA:SA</h1><p>Enter the access code from the person hosting this server.</p><form><input type="password" name="code" autocomplete="off" required><button>Join game</button></form><p id="message" role="status"></p><script>document.querySelector('form').onsubmit=async e=>{e.preventDefault();const r=await fetch('/api/local/join',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({code:e.target.code.value})});if(r.ok)location.href='/';else document.querySelector('#message').textContent='That code did not work.'}</script></html>`);
      res.writeHead(200, {'Content-Type': 'text/html; charset=utf-8', 'Content-Length': content.length,
        'Cache-Control': 'no-store'});
      return res.end(content);
    }
    if (req.method !== 'POST') return json(res, 405, {error: 'Method not allowed'});
    try {
      const body = await readBody(req, 2048);
      const proposed = crypto.createHmac('sha256', String(body.code || '')).update('ZGTA:SA local access v1').digest();
      if (!crypto.timingSafeEqual(proposed, Buffer.from(ACCESS_TOKEN, 'hex')))
        return json(res, 403, {error: 'Access code incorrect'});
      const secure = req.headers['x-forwarded-proto'] === 'https' ? '; Secure' : '';
      res.setHeader('Set-Cookie', `zgta_access=${ACCESS_TOKEN}; Path=/; HttpOnly; SameSite=Strict${secure}`);
      return json(res, 200, {joined: true});
    } catch (error) { return json(res, 400, {error: error.message}); }
  }

  async http(req, res) {
    const url = new URL(req.url, 'http://localhost');
    if (url.pathname === '/api/local/status' && req.method === 'GET')
      return json(res, 200, {selfhost: true, players: [...this.peers].filter(p => p.ready).length,
        features: ['local accounts', 'player positions', 'chat', 'local settings']});
    if (url.pathname === '/api/local/diagnostics' && process.env.ZGTA_DEBUG_SELFHOST === '1') {
      const keys = ['x', 'y', 'z', 'at', 'position', 'car', 'walking', 'driving', 'heading',
        'pitch', 'roll', 'speed', 'steer', 'health', 'life', 'weapon', 'act', 'clock'];
      return json(res, 200, {peers: [...this.peers].map(p => ({ready: p.ready,
        stateKeys: Object.keys(p.state || {}),
        sample: Object.fromEntries(keys.filter(k => p.state && k in p.state).map(k => [k, p.state[k]]))}))});
    }
    const {id, player} = this.ensurePlayer(req, res);
    if (url.pathname === '/api/auth/me' && req.method === 'GET')
      return json(res, 200, {id, name: player.name, username: player.name, rank: 'player', admin: false, local: true});
    if (url.pathname === '/api/auth/discord/login')
      return json(res, 409, {error: 'Local accounts are active; Discord is not required.'});
    if (url.pathname === '/api/settings') {
      if (req.method === 'GET') return json(res, 200, {settings: player.settings});
    }
    if (url.pathname.startsWith('/api/settings/')) {
      let key;
      try { key = decodeURIComponent(url.pathname.slice('/api/settings/'.length)); }
      catch { return json(res, 400, {error: 'Invalid setting'}); }
      if (!/^[a-zA-Z0-9_.-]{1,80}$/.test(key)) return json(res, 400, {error: 'Invalid setting'});
      if (req.method === 'PUT') {
        try { player.settings[key] = await readBody(req); this.save(); return json(res, 200, {ok: true}); }
        catch (error) { return json(res, 400, {error: error.message}); }
      }
      if (req.method === 'DELETE') { delete player.settings[key]; this.save(); return json(res, 200, {ok: true}); }
    }
    if (url.pathname === '/api/garage' && req.method === 'GET') return json(res, 200, {cars: []});
    if (url.pathname === '/api/world/cars' && req.method === 'GET') return json(res, 200, {cars: []});
    if (url.pathname === '/api/local/profile') {
      if (req.method === 'GET') return json(res, 200, {name: player.name, number: player.number});
      if (req.method === 'PUT') {
        try {
          const body = await readBody(req);
          const name = safeName(body.name);
          if (!name) return json(res, 400, {error: 'Enter a name'});
          player.name = name;
          this.save();
          for (const peer of this.peers) if (peer.player === player) peer.send({t: 'note', text: `Your local name is ${name}.`});
          return json(res, 200, {name, number: player.number});
        } catch (error) { return json(res, 400, {error: error.message}); }
      }
    }
    return json(res, 501, {error: 'This original-server feature is not implemented in self-hosted mode.'});
  }

  upgrade(req, socket, head) {
    if (!this.authorized(req)) {
      socket.end('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n'); return;
    }
    if (new URL(req.url, 'http://localhost').pathname !== '/api/world/live' ||
        req.headers.upgrade?.toLowerCase() !== 'websocket' ||
        !/^[A-Za-z0-9+/]{22}==$/.test(req.headers['sec-websocket-key'] || '')) {
      socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n'); return;
    }
    if (this.peers.size >= MAX_PEERS) {
      socket.end('HTTP/1.1 503 Service Unavailable\r\nConnection: close\r\n\r\n'); return;
    }
    const {id, player} = this.ensurePlayer(req);
    for (const old of this.peers) if (old.player === player) old.close();
    const accept = crypto.createHash('sha1').update(req.headers['sec-websocket-key'] +
      '258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
    socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n' +
      `Sec-WebSocket-Accept: ${accept}\r\n` +
      (cookieId(req) ? '' : `Set-Cookie: ${COOKIE}=${id}; Path=/; HttpOnly; SameSite=Lax\r\n`) + '\r\n');
    const peer = new Peer(socket, player, this);
    this.peers.add(peer);
    socket.on('data', bytes => peer.receive(bytes));
    socket.on('error', () => peer.close());
    socket.on('close', () => peer.close());
    if (head.length) peer.receive(head);
  }

  onMessage(peer, message) {
    if (!message || typeof message !== 'object') return;
    if (message.t === 'hi') {
      peer.ready = true;
      peer.send({t: 'hello', protocol: 38, time: Date.now(), day: {shift: 0, hold: null},
        weather: 0, account: true, admin: false, rank: 'player',
        spot: [1480, -1738, 13, 0], life: [100, 0], out: [1480, -1738],
        zombies: false, traffic: 0, peds: 0, party: 0});
      peer.send(this.fullState(peer));
      return;
    }
    if (!peer.ready) return;
    if (message.t === 'ping') return peer.send({t: 'pong', c: message.c, s: Date.now()});
    if (message.t === 'me') {
      peer.state = message;
      peer.lastSeen = Date.now();
      if (typeof message.say === 'string' && message.say.trim()) this.say(peer, message.say);
      return;
    }
    if (message.t === 'who' && Array.isArray(message.ids))
      return peer.send({t: 'cars', c: [...this.peers].filter(p => p !== peer && message.ids.includes(String(p.player.number)))
        .map(p => this.row(p)).filter(Boolean)});
    if (message.t === 'board') return peer.send(this.board(peer));
    if (message.t === 'tongue') return;
  }

  say(peer, raw) {
    const text = raw.trim().slice(0, 240);
    if (!text) return;
    if (text.startsWith('/name ')) {
      const name = safeName(text.slice(6));
      if (name) { peer.player.name = name; this.save(); peer.send({t: 'note', text: `Your local name is ${name}.`}); }
      return;
    }
    if (text === '/players') {
      peer.send(this.board(peer));
      peer.send({t: 'note', text: `${[...this.peers].filter(p => p.ready).length} local player(s) online.`});
      return;
    }
    const line = [++this.chatSequence, peer.player.name, text, peer.player.number, 0, '', 0, ''];
    this.chat.push(line);
    if (this.chat.length > 100) this.chat.shift();
    for (const p of this.peers) if (p.ready) p.send({t: 'chat', lines: [line]});
  }

  row(peer) {
    const s = peer.state;
    if (!s || Date.now() - peer.lastSeen > 10000) return null;
    const point = Array.isArray(s.at) ? s.at : Array.isArray(s.position) ? s.position : null;
    const x = finite(s.x, point ? finite(point[0]) : 1480);
    const y = finite(s.y, point ? finite(point[1]) : -1738);
    const z = finite(s.z, point ? finite(point[2]) : 13);
    const row = Array(50).fill(null);
    row[0] = String(peer.player.number);
    row[1] = peer.player.name;
    row[2] = typeof s.car === 'string' ? s.car : 's0';
    row[3] = x; row[4] = y; row[5] = z;
    row[6] = finite(s.heading); row[7] = finite(s.pitch); row[8] = finite(s.roll);
    row[9] = finite(s.speed); row[10] = finite(s.steer);
    row[11] = s.boost ? 1 : 0;
    row[12] = s.lights ? 1 : 0;
    row[13] = finite(s.vx); row[14] = finite(s.vy); row[15] = finite(s.vz);
    row[16] = finite(s.clock, Date.now());
    row[17] = Number.isInteger(s.horn) ? s.horn : 0;
    row[18] = finite(s.health, 100);
    row[24] = finite(s.move);
    row[25] = s.air ? 1 : 0;
    row[26] = s.crouch ? 1 : 0;
    row[27] = Number.isInteger(s.weapon) ? s.weapon : 0;
    row[28] = Number.isFinite(s.aim) ? s.aim : null;
    row[29] = finite(s.shots);
    row[30] = finite(s.armour);
    row[31] = Number.isInteger(s.skin) ? s.skin : 0;
    row[32] = Number.isInteger(s.act) ? s.act : 0;
    row[34] = typeof s.riding === 'string' && Number.isInteger(s.seat) ? [s.riding, s.seat] : null;
    row[35] = typeof s.vehicle === 'string' ? s.vehicle : null;
    row[36] = s.paused ? 1 : 0;
    row[37] = peer.player.number;
    row[39] = Array.isArray(s.on) ? s.on : null;
    row[43] = finite(s.life, 100);
    return row;
  }

  fullState(peer) {
    return {t: 'all', protocol: 38, number: peer.player.number, world: 1,
      id: String(peer.player.number), you: peer.player.name, out: [1480, -1738],
      time: Date.now(), cash: peer.player.cash, cars: [...this.peers].filter(p => p !== peer).map(p => this.row(p)).filter(Boolean),
      chat: this.chat.slice(-50), vehicles: [], objects: [], boomboxes: [], dots: [], vdots: [], orders: []};
  }

  board(peer) {
    const online = [...this.peers].filter(p => p.ready);
    return {t: 'board', you: String(peer.player.number), players: online.length,
      rows: online.map(p => [String(p.player.number), p.player.name, 0, 0, p.player.number])};
  }

  broadcastPositions() {
    for (const p of this.peers) {
      if (!p.ready) continue;
      const rows = [...this.peers].filter(other => other !== p).map(other => this.row(other)).filter(Boolean);
      if (rows.length) p.send({t: 'cars', c: rows});
    }
  }

  remove(peer) {
    if (!this.peers.delete(peer)) return;
    for (const p of this.peers) if (p.ready) p.send({t: 'gone', id: String(peer.player.number)});
  }
}

class Peer {
  constructor(socket, player, game) {
    this.socket = socket;
    this.player = player;
    this.game = game;
    this.buffer = Buffer.alloc(0);
    this.fragments = [];
    this.fragmentBytes = 0;
    this.ready = false;
    this.state = null;
    this.lastSeen = 0;
    this.closed = false;
    this.messages = 0;
    this.window = Date.now();
  }

  send(message) {
    if (this.closed) return;
    const data = Buffer.from(JSON.stringify(message));
    let header;
    if (data.length < 126) header = Buffer.from([0x81, data.length]);
    else if (data.length < 65536) header = Buffer.from([0x81, 126, data.length >> 8, data.length & 255]);
    else { header = Buffer.alloc(10); header[0] = 0x81; header[1] = 127; header.writeBigUInt64BE(BigInt(data.length), 2); }
    if (this.socket.writable && this.socket.writableLength < 1024 * 1024)
      this.socket.write(Buffer.concat([header, data]));
  }

  receive(bytes) {
    this.buffer = Buffer.concat([this.buffer, bytes]);
    if (this.buffer.length > MAX_FRAME * 2) return this.close();
    while (this.buffer.length >= 2) {
      const first = this.buffer[0], second = this.buffer[1];
      const masked = !!(second & 0x80);
      let length = second & 0x7f, offset = 2;
      if (!masked) return this.close();
      if (length === 126) { if (this.buffer.length < 4) return; length = this.buffer.readUInt16BE(2); offset = 4; }
      else if (length === 127) return this.close();
      if (length > MAX_FRAME || this.buffer.length < offset + 4 + length) return length > MAX_FRAME ? this.close() : undefined;
      const mask = this.buffer.subarray(offset, offset + 4);
      const payload = Buffer.from(this.buffer.subarray(offset + 4, offset + 4 + length));
      this.buffer = this.buffer.subarray(offset + 4 + length);
      for (let i = 0; i < payload.length; i++) payload[i] ^= mask[i & 3];
      const opcode = first & 15;
      if (opcode === 8) return this.close(payload);
      if (opcode === 9) {
        if (payload.length > 125) return this.close();
        this.socket.write(Buffer.from([0x8a, payload.length, ...payload])); continue;
      }
      if (opcode !== 1 && opcode !== 0) continue;
      if (opcode === 1 && this.fragments.length) return this.close();
      if (opcode === 0 && !this.fragments.length) return this.close();
      this.fragments.push(payload);
      this.fragmentBytes += payload.length;
      if (this.fragmentBytes > MAX_FRAME) return this.close();
      if (!(first & 0x80)) continue;
      const text = Buffer.concat(this.fragments).toString('utf8');
      this.fragments = [];
      this.fragmentBytes = 0;
      if (Date.now() - this.window > 1000) { this.window = Date.now(); this.messages = 0; }
      if (++this.messages > 120) return this.close();
      try { this.game.onMessage(this, JSON.parse(text)); } catch (error) { console.error('Local message error:', error.message); }
    }
  }

  close(payload = Buffer.from([3, 232])) {
    if (this.closed) return;
    this.closed = true;
    this.game.remove(this);
    if (this.socket.writable) {
      const reply = payload.length <= 125 ? payload : Buffer.from([3, 232]);
      this.socket.write(Buffer.concat([Buffer.from([0x88, reply.length]), reply]));
      this.socket.end();
    } else this.socket.destroy();
  }
}

const game = new LocalGame();
for (const signal of ['SIGINT', 'SIGTERM']) process.on(signal, () => {
  try {game.flushSync();} catch (error) {console.error('Could not save local players:', error.message);}
  process.exit(signal === 'SIGINT' ? 130 : 143);
});
module.exports = game;
