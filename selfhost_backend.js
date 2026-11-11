// An independent, local-only starting point for the archived browser client.
// This intentionally implements a small, documented part of the live protocol.
const crypto = require('crypto');
const fs = require('fs');
const path = require('path');

const MAX_FRAME = 64 * 1024;
const MAX_PEERS = 32;
const MAX_CASH = 100000000;
const JOBS = Object.freeze([
  {id: 'courier', name: 'Courier', pay: 250, distance: 38},
  {id: 'taxi', name: 'Taxi', pay: 300, distance: 48},
  {id: 'mechanic', name: 'Mechanic', pay: 350, distance: 55},
  {id: 'medic', name: 'Medic', pay: 350, distance: 55},
  {id: 'trial', name: 'Street time trial', pay: 450, distance: 75},
]);
const CATALOG_FILE = path.join(__dirname, 'local-only', 'selfhost', 'client-catalog.json');
let clientCatalog = {vehicles: [], homes: []};
try { clientCatalog = JSON.parse(fs.readFileSync(CATALOG_FILE, 'utf8')); }
catch (error) { if (error.code !== 'ENOENT') console.error('Could not load local client catalog:', error.message); }
const STARTER_CARS = [
  {model: 410, name: 'Manana', price: 500, car: '410.52.39.0.', source: 'starter'},
  {model: 400, name: 'Landstalker', price: 900, car: '400.52.39.0.', source: 'starter'},
  {model: 560, name: 'Sultan', price: 2500, car: '560.52.39.0.', source: 'starter'},
];
const starterModels = new Set(STARTER_CARS.map(car => car.model));
const CAR_CATALOG = Object.freeze([...STARTER_CARS, ...(clientCatalog.vehicles || [])
  .filter(item => Number.isInteger(item.model) && Number.isSafeInteger(item.price) && item.price > 0 &&
    Array.isArray(item.dealers) && item.dealers.length > 0 &&
    ['car', 'bike', 'bicycle', 'quad'].includes(item.type) && !starterModels.has(item.model))
  .map(item => ({model: item.model, name: String(item.name).slice(0, 80), price: item.price,
    car: `${item.model}.${Number.isInteger(item.colors?.[0]) ? item.colors[0] : 1}.` +
      `${Number.isInteger(item.colors?.[1]) ? item.colors[1] : 1}.0.`,
    type: item.type, source: 'archived'}))]);
const HOME_CATALOG = Object.freeze([
  {id: 'starter', name: 'Starter apartment', price: 1500, source: 'starter'},
  {id: 'loft', name: 'City loft', price: 5000, source: 'starter'},
  ...(clientCatalog.homes || [])
    .filter(item => typeof item.key === 'string' && Number.isSafeInteger(item.price) && item.price > 0 &&
      Array.isArray(item.out) && item.out.length === 4 && item.out.every(Number.isFinite))
    .map(item => ({id: item.key, name: String(item.name).slice(0, 80), price: item.price,
      city: String(item.city || '').slice(0, 8), tier: String(item.tier || '').slice(0, 20),
      out: item.out, source: 'archived'})),
]);
const STATE_FILE = path.join(__dirname, 'local-only', 'selfhost', 'players.json');
const COOKIE = 'zgta_local';
const JOIN_CODE = process.env.ZGTA_JOIN_CODE || (process.env.ZGTA_JOIN_CODE_FILE
  ? fs.readFileSync(process.env.ZGTA_JOIN_CODE_FILE, 'utf8').trim() : '');
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
function limited(value, limit, fallback = 0) {
  return Number.isFinite(value) ? Math.max(-limit, Math.min(limit, value)) : fallback;
}
function rounded(value, fallback = 0) { return Math.round(finite(value, fallback) * 1000) / 1000; }
function money(value) { return Number.isSafeInteger(value) ? Math.max(0, Math.min(MAX_CASH, value)) : 0; }
function savedJob(value) {
  return value && JOBS.some(job => job.id === value.id) &&
    Number.isFinite(value.started) && Date.now() - value.started < 86400000
    ? {id: value.id, goal: JOBS.find(job => job.id === value.id).distance,
      progress: Math.max(0, Math.min(JOBS.find(job => job.id === value.id).distance,
        finite(value.progress))), started: value.started} : null;
}

class LocalGame {
  get requiresJoinCode() { return !!JOIN_CODE; }

  constructor() {
    this.players = new Map();
    this.peers = new Set();
    this.vehicles = new Map();
    this.nextVehicle = 1;
    this.chat = [];
    this.chatSequence = 0;
    this.nextNumber = 1;
    try {
      const data = JSON.parse(fs.readFileSync(STATE_FILE, 'utf8'));
      for (const [id, value] of Object.entries(data.players || {})) {
        if (!/^[0-9a-f]{32}$/.test(id)) continue;
        this.players.set(id, {number: this.nextNumber++, name: safeName(value.name) || 'Local player',
          cash: money(value.cash), xp: money(value.xp), jobsDone: money(value.jobsDone),
          cars: Array.isArray(value.cars) ? value.cars.filter(car => CAR_CATALOG.some(item => item.model === car)).slice(0, 12) : [],
          homes: Array.isArray(value.homes) ? value.homes.filter(home => HOME_CATALOG.some(item => item.id === home)).slice(0, 32) : [],
          job: savedJob(value.job),
          settings: value.settings && typeof value.settings === 'object' ? value.settings : {}});
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
      [id, {name: p.name, cash: p.cash, xp: p.xp, jobsDone: p.jobsDone,
        cars: p.cars, homes: p.homes, job: p.job, settings: p.settings}]));
    fs.mkdirSync(path.dirname(STATE_FILE), {recursive: true});
    fs.writeFileSync(STATE_FILE + '.partial', JSON.stringify({version: 1, players}, null, 2) + '\n', {mode: 0o600});
    fs.renameSync(STATE_FILE + '.partial', STATE_FILE);
  }

  ensurePlayer(req, res) {
    let id = cookieId(req);
    if (!id || !this.players.has(id)) {
      id = crypto.randomBytes(16).toString('hex');
      this.players.set(id, {number: this.nextNumber++, name: `Local ${this.nextNumber - 1}`,
        cash: 0, xp: 0, jobsDone: 0, cars: [], homes: [], job: null, settings: {}});
      const secure = req.headers['x-forwarded-proto'] === 'https' ? '; Secure' : '';
      if (res) res.setHeader('Set-Cookie', `${COOKIE}=${id}; Path=/; HttpOnly; SameSite=Lax${secure}`);
      this.save();
    }
    return {id, player: this.players.get(id)};
  }

  authorized(req) {
    if (!JOIN_CODE) return true;
    const remote = req.socket.remoteAddress;
    const localSocket = remote === '127.0.0.1' || remote === '::1' || remote === '::ffff:127.0.0.1';
    const localHost = /^((127\.0\.0\.1)|(localhost)):\d+$/.test(req.headers.host || '');
    // A local reverse proxy is still a remote visitor. Do not let a rewritten
    // loopback Host header bypass the access code.
    if (localSocket && localHost && !req.headers['x-forwarded-for'] &&
        !req.headers['x-forwarded-proto']) return true;
    const match = /(?:^|;\s*)zgta_access=([0-9a-f]{64})(?:;|$)/.exec(req.headers.cookie || '');
    return !!match && crypto.timingSafeEqual(Buffer.from(match[1], 'hex'), Buffer.from(ACCESS_TOKEN, 'hex'));
  }

  position(player) {
    const peer = [...this.peers].find(item => item.player === player && item.ready &&
      Date.now() - item.lastSeen < 10000 && item.state &&
      (item.state.walking === true || item.state.driving === true) &&
      Number.isFinite(item.state.x) && Number.isFinite(item.state.y));
    return peer ? {x: peer.state.x, y: peer.state.y,
      z: finite(peer.state.z, 13), peer} : null;
  }

  gameplayState(player) {
    const pos = this.position(player);
    const active = player.job;
    return {name: player.name, cash: player.cash, xp: player.xp, jobsDone: player.jobsDone,
      connected: !!pos, position: pos ? {x: rounded(pos.x), y: rounded(pos.y)} : null,
      job: active ? {id: active.id, name: JOBS.find(job => job.id === active.id)?.name,
        goal: active.goal, progress: Math.floor(active.progress),
        remaining: Math.max(0, Math.ceil(active.goal - active.progress)), started: active.started} : null,
      cars: player.cars.map(model => CAR_CATALOG.find(car => car.model === model)).filter(Boolean),
      homes: player.homes.map(id => HOME_CATALOG.find(home => home.id === id)).filter(Boolean),
      catalog: {jobs: JOBS,
        cars: CAR_CATALOG.map(({model, name, price, type, source}) => ({model, name, price, type, source})),
        homes: HOME_CATALOG.map(({id, name, price, city, tier, source}) =>
          ({id, name, price, city, tier, source}))}};
  }

  note(player, text) {
    for (const peer of this.peers) if (peer.player === player && peer.ready)
      peer.send({t: 'note', text});
  }

  owned(player) {
    const cars = player.cars.map(model => CAR_CATALOG.find(car => car.model === model));
    return {t: 'owned', cars: cars.map(car => car.car), out: [], login: true,
      worth: cars.map(car => car.price), stored: [], locked: [],
      rep: {level: 1 + Math.floor(player.xp / 1000)}, licence: true};
  }

  updatePlayer(player) {
    this.save();
    for (const peer of this.peers) if (peer.player === player && peer.ready) {
      peer.send({t: 'cash', cash: player.cash});
      peer.send(this.owned(player));
    }
  }

  spawnOwnedCar(player, slot) {
    const pos = this.position(player);
    if (!pos) throw new Error('Enter the game before spawning a car.');
    const car = CAR_CATALOG.find(item => item.model === player.cars[slot]);
    if (!car) throw new Error('That car is not in your garage.');
    const mine = [...this.vehicles.values()].filter(vehicle => vehicle.owner === player);
    if (mine.length >= 3) {
      const oldest = mine[0];
      this.vehicles.delete(oldest.id);
      for (const peer of this.peers) if (peer.ready) peer.send({t: 'vgone', id: oldest.id});
    }
    const id = `local-${this.nextVehicle++}`;
    // Vehicle origins sit above their tyres. Ground-height origins can embed
    // the body in the map and make the physics engine launch it on entry.
    const row = [id, player.name, car.car, rounded(pos.x + 4), rounded(pos.y + 3),
      rounded(pos.z + 1.1), 0, 0, 0, 1000, '', null];
    this.vehicles.set(id, {id, owner: player, row});
    for (const peer of this.peers) if (peer.ready) peer.send({t: 'spawned', v: row});
    return `${car.name} spawned nearby.`;
  }

  action(player, action, input) {
    const pos = this.position(player);
    let message;
    if (action === 'job.start') {
      const job = JOBS.find(item => item.id === input.job);
      if (!job) throw new Error('Unknown job.');
      if (!pos) throw new Error('Enter the game before starting a job.');
      if (player.job) throw new Error('Finish or cancel your current job first.');
      player.job = {id: job.id, goal: job.distance, progress: 0, started: Date.now()};
      message = `${job.name} started. Travel ${job.distance} m, then complete the task.`;
      this.save();
    } else if (action === 'job.complete') {
      if (!player.job) throw new Error('No active job.');
      if (!pos) throw new Error('Enter the game to complete this job.');
      if (Date.now() - player.job.started < 3000) throw new Error('The task started too recently.');
      if (player.job.progress < player.job.goal)
        throw new Error(`Travel ${Math.ceil(player.job.goal - player.job.progress)} m more.`);
      const job = JOBS.find(item => item.id === player.job.id);
      if (job.id === 'trial' && Date.now() - player.job.started > 180000)
        throw new Error('The time trial expired. Cancel it and start again.');
      player.cash = money(player.cash + job.pay);
      player.xp = money(player.xp + Math.round(job.pay / 5));
      player.jobsDone++;
      player.job = null;
      message = `${job.name} complete: +$${job.pay}. Balance: $${player.cash}.`;
      this.updatePlayer(player);
    } else if (action === 'job.cancel') {
      if (!player.job) throw new Error('No active job.');
      player.job = null;
      message = 'Job cancelled.';
      this.save();
    } else if (action === 'car.buy') {
      const car = CAR_CATALOG.find(item => item.model === Number(input.model));
      if (!car) throw new Error('Unknown car.');
      if (player.cars.length >= 12) throw new Error('Your garage is full.');
      if (player.cash < car.price) throw new Error(`You need $${car.price}.`);
      player.cash -= car.price;
      player.cars.push(car.model);
      message = `${car.name} bought for $${car.price}. Open My Vehicles or spawn it here.`;
      this.updatePlayer(player);
    } else if (action === 'car.spawn') {
      const slot = Number(input.slot);
      if (!Number.isInteger(slot) || slot < 0 || slot >= player.cars.length)
        throw new Error('Choose a car in your garage.');
      message = this.spawnOwnedCar(player, slot);
    } else if (action === 'home.buy') {
      const home = HOME_CATALOG.find(item => item.id === input.home);
      if (!home) throw new Error('Unknown home.');
      if (player.homes.includes(home.id)) throw new Error('You already own this home.');
      if (player.cash < home.price) throw new Error(`You need $${home.price}.`);
      player.cash -= home.price;
      player.homes.push(home.id);
      message = `${home.name} bought for $${home.price}.`;
      this.updatePlayer(player);
    } else if (action === 'home.visit') {
      const home = HOME_CATALOG.find(item => item.id === input.home);
      if (!home || !player.homes.includes(home.id)) throw new Error('You do not own this home.');
      if (!home.out) throw new Error('This starter home has no world entrance.');
      if (!pos) throw new Error('Enter the game before visiting your home.');
      pos.peer.send({t: 'tp', x: home.out[0], y: home.out[1], z: home.out[2],
        h: home.out[3], g: 1});
      message = `Travelling to ${home.name}.`;
    } else throw new Error('Unknown action.');
    this.note(player, message);
    return {ok: true, message, state: this.gameplayState(player)};
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
        joinCodeRequired: !!JOIN_CODE, lanAccessible: process.env.BIND_HOST === '0.0.0.0',
        allowedHosts: (process.env.ZGTA_ALLOWED_HOSTS || '').split(',').filter(Boolean),
        features: ['local accounts', 'player positions', 'chat', 'local settings',
          'jobs and cash', 'garage ownership', 'home ownership', 'client catalogs']});
    if (url.pathname === '/api/local/diagnostics' && process.env.ZGTA_DEBUG_SELFHOST === '1') {
      const keys = ['x', 'y', 'z', 'at', 'position', 'car', 'walking', 'driving', 'heading',
        'pitch', 'roll', 'speed', 'steer', 'health', 'life', 'weapon', 'act', 'clock'];
      return json(res, 200, {peers: [...this.peers].map(p => ({ready: p.ready,
        stateKeys: Object.keys(p.state || {}),
        sample: Object.fromEntries(keys.filter(k => p.state && k in p.state).map(k => [k, p.state[k]]))}))});
    }
    const {id, player} = this.ensurePlayer(req, res);
    if (url.pathname === '/api/local/state' && req.method === 'GET')
      return json(res, 200, this.gameplayState(player));
    if (url.pathname === '/api/local/action' && req.method === 'POST') {
      try {
        const body = await readBody(req, 2048);
        return json(res, 200, this.action(player, body.action, body));
      } catch (error) { return json(res, 400, {error: error.message}); }
    }
    if (url.pathname === '/api/auth/me' && req.method === 'GET')
      return json(res, 200, {id, name: player.name, username: player.name,
        loggedIn: true, available: true, rank: 'player', admin: false, local: true});
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
    if (url.pathname === '/api/garage' && req.method === 'GET')
      return json(res, 200, {cars: this.gameplayState(player).cars});
    if (url.pathname === '/api/world/cars' && req.method === 'GET')
      return json(res, 200, {cars: [...this.vehicles.values()].map(vehicle => vehicle.row)});
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
      peer.send(this.owned(peer.player));
      return;
    }
    if (!peer.ready) return;
    if (message.t === 'ping') return peer.send({t: 'pong', c: message.c, s: Date.now()});
    if (message.t === 'me') {
      const previous = peer.state;
      if (peer.player.job && previous && Date.now() - peer.lastSeen < 5000 &&
          (message.walking === true || message.driving === true) &&
          Number.isFinite(message.x) && Number.isFinite(message.y) &&
          Number.isFinite(previous.x) && Number.isFinite(previous.y)) {
        const step = Math.hypot(message.x - previous.x, message.y - previous.y);
        if (step >= 0.2 && step <= 10) {
          peer.player.job.progress = Math.min(peer.player.job.goal,
            peer.player.job.progress + step);
          this.save();
        }
      }
      peer.state = message;
      peer.lastSeen = Date.now();
      if (typeof message.say === 'string' && message.say.trim()) this.say(peer, message.say);
      return;
    }
    if (message.t === 'centre') {
      return peer.send({t: 'centre', open: !!message.open, jobs: JOBS.map(job => ({
        job: job.id, name: job.name, start: `/job ${job.id}`,
        marked: false, starts: [], spots: []}))});
    }
    if (message.t === 'spawn') {
      try {
        if (!Number.isInteger(message.own) ||
            CAR_CATALOG.find(car => car.model === peer.player.cars[message.own])?.car !== message.car)
          throw new Error('Buy this car before spawning it.');
        this.spawnOwnedCar(peer.player, message.own);
      } catch (error) { peer.send({t: 'note', text: error.message}); }
      return;
    }
    if (message.t === 'enter' || message.t === 'jack')
      return peer.send({t: message.t, v: message.v, ok: this.vehicles.has(message.v)});
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
    if (text === '/owned' || text === '/mycars' || text === '/garage')
      return peer.send(this.owned(peer.player));
    if (text === '/balance' || text === '/money')
      return peer.send({t: 'note', text: `Balance: $${peer.player.cash}. Jobs completed: ${peer.player.jobsDone}.`});
    if (text === '/jobs')
      return peer.send({t: 'note', text: `Local jobs: ${JOBS.map(job => `${job.id} ($${job.pay})`).join(', ')}. Type /job <name>.`});
    if (text.startsWith('/job ') || text === '/deliver' || text === '/canceljob' ||
        text.startsWith('/buycar ') || text.startsWith('/spawncar ') || text.startsWith('/buyhome ')) {
      try {
        const [command, value] = text.slice(1).split(/\s+/, 2);
        const actions = {job: ['job.start', {job: value}], deliver: ['job.complete', {}],
          canceljob: ['job.cancel', {}], buycar: ['car.buy', {model: value}],
          spawncar: ['car.spawn', {slot: Number(value) - 1}],
          buyhome: ['home.buy', {home: value}]};
        const [action, input] = actions[command];
        this.action(peer.player, action, input);
      } catch (error) { peer.send({t: 'note', text: error.message}); }
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
    const driving = s.driving === true && typeof s.car === 'string';
    const walking = !driving && s.walking === true && Number.isInteger(s.skin);
    if (!driving && !walking) return null;
    const point = Array.isArray(s.at) ? s.at : Array.isArray(s.position) ? s.position : null;
    const x = finite(s.x, point ? finite(point[0]) : 1480);
    const y = finite(s.y, point ? finite(point[1]) : -1738);
    const z = finite(s.z, point ? finite(point[2]) : 13);
    const row = Array(50).fill(null);
    row[0] = String(peer.player.number);
    row[1] = peer.player.name;
    row[2] = driving ? s.car.slice(0, 64) : `s${s.skin}`;
    row[3] = rounded(x); row[4] = rounded(y); row[5] = rounded(z);
    row[6] = rounded(s.heading); row[7] = rounded(s.pitch); row[8] = rounded(s.roll);
    row[9] = rounded(limited(s.speed, 150)); row[10] = rounded(limited(s.steer, 1));
    row[11] = s.boost ? 1 : 0;
    row[12] = s.lights ? 1 : 0;
    row[13] = rounded(limited(s.vx, 150)); row[14] = rounded(limited(s.vy, 150));
    row[15] = rounded(limited(s.vz, 150));
    row[16] = Math.round(finite(s.clock, Date.now()));
    row[17] = typeof s.horn === 'boolean' ? Number(s.horn) : Number.isInteger(s.horn) ? s.horn & 3 : 0;
    row[18] = Math.round(Math.max(0, Math.min(walking ? 100 : 1000,
      finite(s.health, walking ? 100 : 1000))));
    row[19] = typeof s.damage === 'string' ? s.damage.slice(0, 512) : '';
    row[20] = rounded(limited(s.wx, 30)); row[21] = rounded(limited(s.wy, 30));
    row[22] = rounded(limited(s.wz, 30));
    row[23] = Math.round(Math.max(0, limited(s.lag, 2000)));
    row[24] = walking ? rounded(Math.max(0, limited(s.move, 3))) : 0;
    row[25] = walking && s.air ? 1 : 0;
    row[26] = s.crouch ? 1 : 0;
    row[27] = walking || (driving && s.aim !== undefined) ?
      (Number.isInteger(s.weapon) ? s.weapon : 0) : 0;
    row[28] = (walking || (driving && s.aim !== undefined)) && Number.isFinite(s.aim) ?
      rounded(limited(s.aim, 1.6)) : null;
    row[29] = (walking || (driving && s.aim !== undefined)) && Number.isFinite(s.shots) ?
      Math.max(0, s.shots) : 0;
    row[30] = Math.round(Math.max(0, Math.min(100, finite(s.armour))));
    row[31] = driving && Number.isInteger(s.skin) ? s.skin : 0;
    row[32] = Number.isInteger(s.act) ? s.act : 0;
    const riding = walking && typeof s.riding === 'string' ?
      [s.riding.slice(0, 64), Number.isInteger(s.seat) ? s.seat : 0] : null;
    row[33] = walking && !riding && typeof s.car === 'string' && s.parked &&
      typeof s.parked === 'object' ? [s.car.slice(0, 64),
        rounded(s.parked.x), rounded(s.parked.y), rounded(s.parked.z),
        rounded(s.parked.heading), rounded(s.parked.pitch), rounded(s.parked.roll),
        Math.round(finite(s.parked.health, 1000)),
        typeof s.parked.damage === 'string' ? s.parked.damage.slice(0, 512) : ''] : null;
    row[34] = riding;
    row[35] = typeof s.vehicle === 'string' ? s.vehicle.slice(0, 64) : null;
    row[36] = s.paused ? 1 : 0;
    row[37] = peer.player.number;
    row[38] = walking && !riding && Number.isInteger(s.down) ? s.down : 0;
    row[39] = walking && !riding && s.on && typeof s.on.v === 'string' ?
      [s.on.v.slice(0, 64), rounded(s.on.x), rounded(s.on.y), rounded(s.on.z)] : null;
    row[40] = driving && Number.isFinite(s.smoke) && s.smoke > 0 ? rounded(s.smoke) : null;
    row[41] = walking && !riding && typeof s.anim === 'string' ? s.anim.slice(0, 96) : null;
    row[42] = driving && Array.isArray(s.kit) ? s.kit.slice(0, 16).map(value => rounded(value)) : null;
    row[43] = driving ? Math.round(Math.max(0, Math.min(100, finite(s.life, 100)))) : 0;
    return row;
  }

  fullState(peer) {
    return {t: 'all', protocol: 38, number: peer.player.number, world: 1,
      id: String(peer.player.number), you: peer.player.name, out: [1480, -1738],
      time: Date.now(), cash: peer.player.cash, cars: [...this.peers].filter(p => p !== peer).map(p => this.row(p)).filter(Boolean),
      chat: this.chat.slice(-50), vehicles: [...this.vehicles.values()].map(vehicle => vehicle.row),
      objects: [], boomboxes: [], dots: [], vdots: [], orders: []};
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
