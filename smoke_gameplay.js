#!/usr/bin/env node
// Isolated account, job, purchase, vehicle, and persistence check.
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const {spawn} = require('node:child_process');

async function freePort() {
  const server = net.createServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return port;
}

async function connect(port, cookie) {
  const socket = net.connect(port, '127.0.0.1');
  const key = crypto.randomBytes(16).toString('base64');
  let buffer = Buffer.alloc(0), upgraded = false;
  const messages = [], waiters = [];
  const opened = new Promise((resolve, reject) => {
    socket.once('connect', () => socket.write(`GET /api/world/live HTTP/1.1\r\n` +
      `Host: 127.0.0.1:${port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n` +
      `Sec-WebSocket-Version: 13\r\nSec-WebSocket-Key: ${key}\r\nCookie: ${cookie}\r\n\r\n`));
    socket.once('error', reject);
    socket.on('data', chunk => {
      buffer = Buffer.concat([buffer, chunk]);
      if (!upgraded) {
        const end = buffer.indexOf('\r\n\r\n');
        if (end < 0) return;
        const header = buffer.subarray(0, end).toString('utf8');
        if (!header.startsWith('HTTP/1.1 101')) return reject(new Error(header));
        buffer = buffer.subarray(end + 4);
        upgraded = true;
        resolve();
      }
      while (buffer.length >= 2) {
        let length = buffer[1] & 127, offset = 2;
        if (length === 126) {
          if (buffer.length < 4) return;
          length = buffer.readUInt16BE(2); offset = 4;
        } else if (length === 127) {
          if (buffer.length < 10) return;
          length = Number(buffer.readBigUInt64BE(2)); offset = 10;
        }
        if (buffer.length < offset + length) return;
        const opcode = buffer[0] & 15;
        const payload = buffer.subarray(offset, offset + length);
        buffer = buffer.subarray(offset + length);
        if (opcode !== 1) continue;
        const message = JSON.parse(payload.toString('utf8'));
        messages.push(message);
        for (const waiter of [...waiters]) if (waiter.match(message)) {
          clearTimeout(waiter.timer);
          waiters.splice(waiters.indexOf(waiter), 1);
          waiter.resolve(message);
        }
      }
    });
  });
  await opened;
  return {
    close: () => socket.end(),
    send(message) {
      const data = Buffer.from(JSON.stringify(message));
      const mask = crypto.randomBytes(4);
      const header = data.length < 126 ? Buffer.from([0x81, 0x80 | data.length]) :
        Buffer.from([0x81, 0xfe, data.length >> 8, data.length & 255]);
      const masked = Buffer.from(data);
      for (let i = 0; i < masked.length; i++) masked[i] ^= mask[i & 3];
      socket.write(Buffer.concat([header, mask, masked]));
    },
    wait(match) {
      const found = messages.find(match);
      if (found) return Promise.resolve(found);
      return new Promise((resolve, reject) => {
        const waiter = {match, resolve, timer: setTimeout(() => reject(new Error('WebSocket message timed out')), 5000)};
        waiters.push(waiter);
      });
    },
  };
}

async function main() {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-gameplay-'));
  const local = path.join(temporary, 'local-only');
  fs.mkdirSync(local);
  fs.symlinkSync(path.join(__dirname, 'local-only', 'site'), path.join(local, 'site'));
  fs.mkdirSync(path.join(local, 'selfhost'));
  fs.copyFileSync(path.join(__dirname, 'local-only', 'selfhost', 'client-catalog.json'),
    path.join(local, 'selfhost', 'client-catalog.json'));
  for (const file of ['serve_local.js', 'selfhost_backend.js', 'local_gameplay.js', 'optional_discord.js'])
    fs.copyFileSync(path.join(__dirname, file), path.join(temporary, file));
  const port = await freePort();
  let child, ws, otherWs, otherCookie;
  const start = () => spawn(process.execPath, ['serve_local.js'], {
    cwd: temporary, env: {...process.env, ZGTA_SELFHOST: '1', PORT: String(port),
      BIND_HOST: '127.0.0.1', ZGTA_JOIN_CODE: '', ZGTA_JOIN_CODE_FILE: '', ZGTA_ALLOWED_HOSTS: ''},
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  const root = `http://127.0.0.1:${port}`;
  const ready = async () => {
    for (let i = 0; i < 50; i++) {
      try { if ((await fetch(root + '/api/local/status')).ok) return; } catch {}
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    throw new Error('Temporary local server did not start');
  };
  try {
    child = start();
    await ready();
    const asset = await fetch(root + '/local-gameplay.js');
    assert.equal(asset.status, 200);
    assert.equal(asset.headers.get('set-cookie'), null, 'assets must not create player accounts');
    const document = await fetch(root + '/');
    assert.equal(document.status, 200);
    const cookie = document.headers.get('set-cookie')?.split(';')[0];
    assert(cookie);
    const first = await fetch(root + '/api/auth/me', {headers: {Cookie: cookie}});
    assert.equal(first.headers.get('set-cookie'), null, 'document account must carry into the API');
    const api = async (url, method = 'GET', body) => {
      const response = await fetch(root + url, {method, headers: {Cookie: cookie,
        ...(body ? {'Content-Type': 'application/json'} : {})},
        ...(body ? {body: JSON.stringify(body)} : {})});
      return {status: response.status, body: await response.json()};
    };
    const profile = await api('/api/local/profile');
    ws = await connect(port, cookie);
    ws.send({t: 'hi'});
    const all = await ws.wait(message => message.t === 'all');
    assert.equal(all.id, String(profile.body.number), 'HTTP and WebSocket must share the account');
    ws.send({t: 'me', walking: true, skin: 7, x: 1480, y: -1738, z: 13});
    const connected = await api('/api/local/state');
    assert.equal(connected.body.connected, true);
    assert.equal(connected.body.discord.available, false, 'guest mode works without OAuth configuration');
    assert.equal((await api('/api/local/discord/start')).status, 404);
    assert(connected.body.catalog.cars.length > 80, 'archived vehicle catalog must load');
    assert.equal(connected.body.catalog.homes.length, 31, 'archived property catalog must load');
    const earlyBuy = await api('/api/local/action', 'POST', {action: 'car.buy', model: 410});
    assert.equal(earlyBuy.status, 400);
    let x = 1480, y = -1738;
    async function moveTo(target, driving = false) {
      const startX = x, startY = y;
      const steps = Math.ceil(Math.hypot(target.x - x, target.y - y) / 5);
      for (let i = 1; i <= steps; i++) {
        x = startX + (target.x - startX) * i / steps;
        y = startY + (target.y - startY) * i / steps;
        ws.send({t: 'me', walking: !driving, driving, skin: 7, x, y, z: 13});
        // Match an actual client's update cadence; the server limits bursts.
        await new Promise(resolve => setTimeout(resolve, 20));
      }
      await new Promise(resolve => setTimeout(resolve, 150));
    }
    async function courier() {
      const started = await api('/api/local/action', 'POST', {action: 'job.start', job: 'courier'});
      assert.equal(started.status, 200, JSON.stringify(started.body));
      assert.equal(started.body.state.job.stage, 'pickup');
      assert.equal(started.body.state.job.remaining, 0);
      const beforePickup = await api('/api/local/action', 'POST', {action: 'job.complete'});
      assert.equal(beforePickup.status, 400);
      const pickupPoint = started.body.state.job.target;
      await moveTo({x: x + 20, y});
      assert.equal((await api('/api/local/action', 'POST', {action: 'job.pickup'})).status, 400);
      await moveTo(pickupPoint);
      const pickup = await api('/api/local/action', 'POST', {action: 'job.pickup'});
      assert.equal(pickup.status, 200, JSON.stringify(pickup.body));
      assert.equal(pickup.body.state.job.stage, 'delivery');
      assert(pickup.body.state.job.remaining > pickup.body.state.job.radius);
      const premature = await api('/api/local/action', 'POST', {action: 'job.complete'});
      assert.equal(premature.status, 400);
      await moveTo(pickup.body.state.job.target);
      const arrived = await api('/api/local/state');
      assert(arrived.body.job.remaining <= arrived.body.job.radius, JSON.stringify(arrived.body.job));
      await new Promise(resolve => setTimeout(resolve, 3100));
      const delivered = await api('/api/local/action', 'POST', {action: 'job.complete'});
      assert.equal(delivered.status, 200, JSON.stringify(delivered.body));
      assert.equal(delivered.body.state.job, null);
    }
    async function mechanic() {
      const otherDocument = await fetch(root + '/');
      otherCookie = otherDocument.headers.get('set-cookie')?.split(';')[0];
      assert(otherCookie && otherCookie !== cookie);
      otherWs = await connect(port, otherCookie);
      otherWs.send({t: 'hi'});
      await otherWs.wait(message => message.t === 'all');
      const started = await api('/api/local/action', 'POST', {action: 'job.start', job: 'mechanic'});
      assert.equal(started.status, 200, JSON.stringify(started.body));
      assert.equal(started.body.state.job.mode, 'service');
      const broken = await ws.wait(message => message.t === 'spawned' &&
        message.v[0].startsWith('mission-'));
      assert.equal(broken.v[9], 350, 'roadside car starts damaged');
      const shared = await otherWs.wait(message => message.t === 'spawned' &&
        message.v[0] === broken.v[0]);
      assert.equal(shared.v[9], 350, 'second player sees the same damaged car');
      otherWs.send({t: 'enter', v: broken.v[0]});
      assert.equal((await otherWs.wait(message => message.t === 'enter' &&
        message.v === broken.v[0])).ok, false, 'other player cannot take the mission car');
      assert.equal((await api('/api/local/action', 'POST', {action: 'job.complete'})).status, 400);
      await moveTo(started.body.state.job.target, true);
      await new Promise(resolve => setTimeout(resolve, 3100));
      assert.equal((await api('/api/local/action', 'POST', {action: 'job.complete'})).status, 400,
        'mechanic must leave the vehicle to repair');
      ws.send({t: 'me', walking: true, driving: false, skin: 7, x, y, z: 13});
      await new Promise(resolve => setTimeout(resolve, 100));
      const repaired = await api('/api/local/action', 'POST', {action: 'job.complete'});
      assert.equal(repaired.status, 200, JSON.stringify(repaired.body));
      assert.equal(repaired.body.state.job, null);
      await ws.wait(message => message.t === 'vgone' && message.id === broken.v[0]);
      await otherWs.wait(message => message.t === 'vgone' && message.id === broken.v[0]);
      otherWs.close(); otherWs = null;
    }
    async function medic() {
      const started = await api('/api/local/action', 'POST', {action: 'job.start', job: 'medic'});
      assert.equal(started.status, 200, JSON.stringify(started.body));
      assert.equal(started.body.state.job.mode, 'route');
      const ambulance = await ws.wait(message => message.t === 'spawned' &&
        message.v[2] === '416.1.1.0.');
      assert(ambulance.v[0].startsWith('mission-'));
      ws.send({t: 'enter', v: ambulance.v[0]});
      assert.equal((await ws.wait(message => message.t === 'enter' && message.v === ambulance.v[0])).ok, true);
      await moveTo(started.body.state.job.target);
      assert.equal((await api('/api/local/action', 'POST', {action: 'job.pickup'})).status, 400,
        'patient pickup requires driving');
      ws.send({t: 'me', walking: false, driving: true, skin: 7, x, y, z: 13});
      await new Promise(resolve => setTimeout(resolve, 100));
      const pickup = await api('/api/local/action', 'POST', {action: 'job.pickup'});
      assert.equal(pickup.status, 200, JSON.stringify(pickup.body));
      assert.equal(pickup.body.state.job.stage, 'delivery');
      await moveTo(pickup.body.state.job.target, true);
      await new Promise(resolve => setTimeout(resolve, 3100));
      const delivered = await api('/api/local/action', 'POST', {action: 'job.complete'});
      assert.equal(delivered.status, 200, JSON.stringify(delivered.body));
      assert.equal(delivered.body.state.job, null);
      await ws.wait(message => message.t === 'vgone' && message.id === ambulance.v[0]);
    }
    async function trial() {
      const started = await api('/api/local/action', 'POST', {action: 'job.start', job: 'trial'});
      assert.equal(started.status, 200, JSON.stringify(started.body));
      assert.equal(started.body.state.job.mode, 'checkpoints');
      assert.equal(started.body.state.job.total, 3);
      assert.equal((await api('/api/local/action', 'POST', {action: 'job.complete'})).status, 400);
      for (let index = 1; index <= 3; index++) {
        const state = await api('/api/local/state');
        assert.equal(state.body.job.index, index);
        await moveTo(state.body.job.target, true);
        if (index < 3) {
          const pass = await api('/api/local/action', 'POST', {action: 'job.checkpoint'});
          assert.equal(pass.status, 200, JSON.stringify(pass.body));
          assert.equal(pass.body.state.job.index, index + 1);
        }
      }
      await new Promise(resolve => setTimeout(resolve, 3100));
      const finished = await api('/api/local/action', 'POST', {action: 'job.complete'});
      assert.equal(finished.status, 200, JSON.stringify(finished.body));
      assert.equal(finished.body.state.job, null);
    }
    async function taxi() {
      const started = await api('/api/local/action', 'POST', {action: 'job.start', job: 'taxi'});
      assert.equal(started.status, 200, JSON.stringify(started.body));
      assert.equal(started.body.state.job.stage, 'pickup');
      await moveTo(started.body.state.job.target);
      assert.equal((await api('/api/local/action', 'POST', {action: 'job.pickup'})).status, 400,
        'passenger pickup requires driving');
      ws.send({t: 'me', walking: false, driving: true, skin: 7, x, y, z: 13});
      await new Promise(resolve => setTimeout(resolve, 100));
      const pickup = await api('/api/local/action', 'POST', {action: 'job.pickup'});
      assert.equal(pickup.status, 200, JSON.stringify(pickup.body));
      assert.equal(pickup.body.state.job.stage, 'delivery');
      await moveTo(pickup.body.state.job.target, true);
      ws.send({t: 'me', walking: true, driving: false, skin: 7, x, y, z: 13});
      await new Promise(resolve => setTimeout(resolve, 100));
      assert.equal((await api('/api/local/action', 'POST', {action: 'job.complete'})).status, 400,
        'passenger drop-off requires driving');
      ws.send({t: 'me', walking: false, driving: true, skin: 7, x, y, z: 13});
      await new Promise(resolve => setTimeout(resolve, 3100));
      const delivered = await api('/api/local/action', 'POST', {action: 'job.complete'});
      assert.equal(delivered.status, 200, JSON.stringify(delivered.body));
      assert.equal(delivered.body.state.job, null);
    }

    assert.equal((await api('/api/local/action', 'POST', {action: 'job.start', job: 'taxi'})).status, 400,
      'taxi requires an owned car');
    assert.equal((await api('/api/local/action', 'POST', {action: 'job.start', job: 'trial'})).status, 400,
      'time trial requires an owned car');
    await mechanic();
    await medic();
    await courier();
    await courier();
    const money = await api('/api/local/state');
    assert.equal(money.body.cash, 1200);
    assert.equal(money.body.jobsDone, 4);
    const buyCar = await api('/api/local/action', 'POST', {action: 'car.buy', model: 410});
    assert.equal(buyCar.status, 200);
    assert.equal(buyCar.body.state.cash, 700);
    const spawnCar = await api('/api/local/action', 'POST', {action: 'car.spawn', slot: 0});
    assert.equal(spawnCar.status, 200, JSON.stringify(spawnCar.body));
    const vehicle = await ws.wait(message => message.t === 'spawned' &&
      message.v[0].startsWith('local-'));
    assert.equal(vehicle.v[2], '410.52.39.0.');
    assert.equal(vehicle.v[5], 14.1, 'vehicle origin must clear the ground');
    ws.send({t: 'enter', v: vehicle.v[0]});
    assert.equal((await ws.wait(message => message.t === 'enter')).ok, true);
    ws.send({t: 'me', walking: false, driving: true, car: vehicle.v[2],
      vehicle: vehicle.v[0], x, y, z: 13, health: 450, damage: 'test-damage'});
    await new Promise(resolve => setTimeout(resolve, 100));
    assert.equal((await api('/api/local/state')).body.garage[0].health, 450);
    ws.send({t: 'me', walking: true, driving: false, skin: 7, car: vehicle.v[2],
      vehicle: vehicle.v[0], x, y, z: 13,
      parked: {x: vehicle.v[3], y: vehicle.v[4], z: vehicle.v[5], heading: 0,
        health: 450, damage: 'test-damage'}});
    await new Promise(resolve => setTimeout(resolve, 100));
    assert.equal((await api('/api/local/action', 'POST', {action: 'car.store', slot: 0})).status, 200);
    await ws.wait(message => message.t === 'vgone' && message.id === vehicle.v[0]);
    assert.equal((await api('/api/local/state')).body.garage[0].active, false);
    assert.equal((await api('/api/local/action', 'POST', {action: 'car.spawn', slot: 0})).status, 200);
    const damagedCar = await ws.wait(message => message.t === 'spawned' &&
      message.v[0].startsWith('local-') && message.v[0] !== vehicle.v[0] &&
      message.v[2] === vehicle.v[2]);
    assert.equal(damagedCar.v[9], 450, 'stored condition must return on spawn');
    const noHome = await api('/api/local/action', 'POST', {action: 'home.buy', home: 'starter'});
    assert.equal(noHome.status, 400);
    await taxi();
    assert.equal((await api('/api/local/state')).body.cash, 1000);
    await trial();
    assert.equal((await api('/api/local/state')).body.cash, 1450);
    await courier();
    const buyHome = await api('/api/local/action', 'POST', {action: 'home.buy', home: 'starter'});
    assert.equal(buyHome.status, 200, JSON.stringify(buyHome.body));
    assert.equal(buyHome.body.state.cash, 200);
    const persistedRoute = await api('/api/local/action', 'POST', {action: 'job.start', job: 'courier'});
    assert.equal(persistedRoute.status, 200);
    assert.equal((await api('/api/local/action', 'POST', {action: 'job.pickup'})).status, 200);
    const deliveryTarget = (await api('/api/local/state')).body.job.target;
    ws.close(); ws = null;
    child.kill('SIGINT');
    await new Promise(resolve => child.once('exit', resolve));
    child = start();
    await ready();
    const saved = await api('/api/local/state');
    assert.equal(saved.body.cash, 200);
    assert.equal(saved.body.jobsDone, 7);
    assert.equal(saved.body.cars[0].model, 410);
    assert.equal(saved.body.garage[0].health, 450);
    assert.equal(saved.body.garage[0].active, true);
    const restoredCar = (await api('/api/world/cars')).body.cars.find(car =>
      car[2] === vehicle.v[2] && car[9] === 450);
    assert(restoredCar, 'active damaged car must survive server restart');
    assert.equal(saved.body.homes[0].id, 'starter');
    assert.equal(saved.body.job.stage, 'delivery');
    assert.deepEqual(saved.body.job.target, deliveryTarget);
    assert.equal((await api('/api/local/action', 'POST', {action: 'job.cancel'})).status, 200);
    ws = await connect(port, cookie);
    ws.send({t: 'hi'});
    const owned = await ws.wait(message => message.t === 'owned');
    assert.deepEqual(owned.cars, ['410.52.39.0.']);
    ws.send({t: 'me', walking: true, skin: 7, x, y, z: 13});
    await new Promise(resolve => setTimeout(resolve, 100));
    await moveTo({x: restoredCar[3], y: restoredCar[4]});
    const repairedCar = await api('/api/local/action', 'POST', {action: 'car.repair', slot: 0});
    assert.equal(repairedCar.status, 200, JSON.stringify(repairedCar.body));
    assert.equal(repairedCar.body.state.cash, 90);
    assert.equal(repairedCar.body.state.garage[0].health, 1000);
    await ws.wait(message => message.t === 'vgone' && message.id === restoredCar[0]);
    assert((await api('/api/world/cars')).body.cars.some(car =>
      car[2] === vehicle.v[2] && car[9] === 1000), 'repair must refresh the shared vehicle');
    const ongoing = await api('/api/local/action', 'POST', {action: 'job.start', job: 'mechanic'});
    assert.equal(ongoing.status, 200, JSON.stringify(ongoing.body));
    const missionCar = await ws.wait(message => message.t === 'spawned' &&
      message.v[0].startsWith('mission-'));
    ws.close(); ws = null;
    child.kill('SIGINT');
    await new Promise(resolve => child.once('exit', resolve));
    child = start();
    await ready();
    assert.equal((await api('/api/local/state')).body.job.mode, 'service');
    assert((await api('/api/world/cars')).body.cars.some(car => car[0] === missionCar.v[0]),
      'unfinished mechanic vehicle must survive server restart');
    assert.equal((await api('/api/local/action', 'POST', {action: 'job.cancel'})).status, 200);
    assert(!(await api('/api/world/cars')).body.cars.some(car => car[0] === missionCar.v[0]),
      'cancelled mission vehicle must be removed');
    child.kill('SIGINT');
    await new Promise(resolve => child.once('exit', resolve));
    const playerFile = path.join(local, 'selfhost', 'players.json');
    const localPlayers = JSON.parse(fs.readFileSync(playerFile, 'utf8'));
    const accountId = cookie.split('=')[1];
    localPlayers.players[accountId].cash = 100000;
    fs.writeFileSync(playerFile, JSON.stringify(localPlayers));
    child = start();
    await ready();
    ws = await connect(port, cookie);
    ws.send({t: 'hi'});
    await ws.wait(message => message.t === 'all');
    await ws.wait(message => message.t === 'home' && Array.isArray(message.own));
    ws.send({t: 'me', walking: true, skin: 7, x: 1480, y: -1738, z: 13});
    assert.equal((await api('/api/local/state')).body.connected, true);
    const originalCar = await api('/api/local/action', 'POST', {action: 'car.buy', model: 401});
    assert.equal(originalCar.status, 200, JSON.stringify(originalCar.body));
    assert.equal(originalCar.body.state.cash, 80000);
    const originalHome = await api('/api/local/action', 'POST', {action: 'home.buy', home: 'willowfield'});
    assert.equal(originalHome.status, 200, JSON.stringify(originalHome.body));
    assert.equal(originalHome.body.state.cash, 44000);
    assert((await ws.wait(message => message.t === 'home' && message.own?.includes('willowfield'))).own.includes('willowfield'));
    const visit = await api('/api/local/action', 'POST', {action: 'home.visit', home: 'willowfield'});
    assert.equal(visit.status, 200, JSON.stringify(visit.body));
    const teleport = await ws.wait(message => message.t === 'tp');
    assert.deepEqual([teleport.x, teleport.y, teleport.z, teleport.h],
      [2483.4, -1999.18, 12.851, -180]);
    ws.send({t: 'me', walking: true, skin: 7, x: 2483.4, y: -1999.18, z: 12.851,
      say: '/home enter willowfield'});
    await ws.wait(message => message.t === 'note' && message.text.includes('interiors'));
    x = 2483.4; y = -1999.18;
    const otherApi = async (url, method = 'GET', body) => {
      const response = await fetch(root + url, {method, headers: {Cookie: otherCookie,
        ...(body ? {'Content-Type': 'application/json'} : {})},
      ...(body ? {body: JSON.stringify(body)} : {})});
      return {status: response.status, body: await response.json()};
    };
    otherWs = await connect(port, otherCookie);
    otherWs.send({t: 'hi'});
    await otherWs.wait(message => message.t === 'all');
    otherWs.send({t: 'me', walking: true, skin: 7, x, y, z: 13});
    await new Promise(resolve => setTimeout(resolve, 100));
    const createdRace = await api('/api/local/action', 'POST', {action: 'race.create'});
    assert.equal(createdRace.status, 200, JSON.stringify(createdRace.body));
    assert.equal(createdRace.body.state.race.stage, 'lobby');
    assert.equal((await api('/api/local/action', 'POST', {action: 'race.start'})).status, 400,
      'one player cannot start a multiplayer race');
    const joinedRace = await otherApi('/api/local/action', 'POST', {action: 'race.join'});
    assert.equal(joinedRace.status, 200, JSON.stringify(joinedRace.body));
    assert.equal((await otherApi('/api/local/action', 'POST', {action: 'race.start'})).status, 400,
      'only the host can start the race');
    const raceStart = await api('/api/local/action', 'POST', {action: 'race.start'});
    assert.equal(raceStart.status, 200, JSON.stringify(raceStart.body));
    const loaners = (await api('/api/world/cars')).body.cars.filter(car =>
      car[0].startsWith('mission-'));
    assert.equal(loaners.length, 2, 'two racers receive loaner cars');
    for (const car of loaners) await ws.wait(message => message.t === 'spawned' && message.v[0] === car[0]);
    otherWs.send({t: 'enter', v: loaners[0][0]});
    assert.equal((await otherWs.wait(message => message.t === 'enter' &&
      message.v === loaners[0][0])).ok, false, 'other player cannot take host loaner');
    assert.equal((await api('/api/local/action', 'POST', {action: 'race.finish'})).status, 400,
      'finish requires checkpoints in order');
    for (let index = 1; index <= 3; index++) {
      const race = (await api('/api/local/state')).body.race;
      assert.equal(race.index, index);
      await moveTo(race.target, true);
      otherWs.send({t: 'me', walking: false, driving: true, skin: 7,
        x: race.target.x, y: race.target.y, z: 13});
      await new Promise(resolve => setTimeout(resolve, 100));
      const action = index === 3 ? 'race.finish' : 'race.checkpoint';
      const first = await api('/api/local/action', 'POST', {action});
      assert.equal(first.status, 200, JSON.stringify(first.body));
      const second = await otherApi('/api/local/action', 'POST', {action});
      assert.equal(second.status, 200, JSON.stringify(second.body));
    }
    const raceResult = await api('/api/local/state');
    assert.equal(raceResult.body.race.stage, 'finished');
    assert.deepEqual(raceResult.body.race.results.map(item => item.pay), [600, 400]);
    assert.equal(raceResult.body.cash, 44600);
    assert.equal(raceResult.body.racesWon, 1);
    assert.equal((await otherApi('/api/local/state')).body.cash, 400);
    assert.equal((await api('/api/world/cars')).body.cars.filter(car =>
      car[0].startsWith('mission-')).length, 0, 'loaner cars disappear after the race');
    const theft = await api('/api/local/action', 'POST', {action: 'job.start', job: 'carthief'});
    assert.equal(theft.status, 200, JSON.stringify(theft.body));
    assert.equal(theft.body.state.job.stage, 'pickup');
    const getaway = await ws.wait(message => message.t === 'spawned' &&
      message.v[2] === '560.52.39.0.');
    assert.equal((await otherWs.wait(message => message.t === 'spawned' &&
      message.v[0] === getaway.v[0])).v[0], getaway.v[0]);
    otherWs.send({t: 'enter', v: getaway.v[0]});
    assert.equal((await otherWs.wait(message => message.t === 'enter' &&
      message.v === getaway.v[0])).ok, false);
    await moveTo(theft.body.state.job.target);
    assert.equal((await api('/api/local/action', 'POST', {action: 'job.pickup'})).status, 400,
      'getaway pickup requires the mission car');
    ws.send({t: 'enter', v: getaway.v[0]});
    assert.equal((await ws.wait(message => message.t === 'enter' &&
      message.v === getaway.v[0])).ok, true);
    ws.send({t: 'me', walking: false, driving: true, skin: 7,
      car: getaway.v[2], vehicle: 'wrong-car', x, y, z: 13});
    await new Promise(resolve => setTimeout(resolve, 100));
    assert.equal((await api('/api/local/action', 'POST', {action: 'job.pickup'})).status, 400);
    ws.send({t: 'me', walking: false, driving: true, skin: 7,
      car: getaway.v[2], vehicle: getaway.v[0], x, y, z: 13});
    await new Promise(resolve => setTimeout(resolve, 100));
    const stolen = await api('/api/local/action', 'POST', {action: 'job.pickup'});
    assert.equal(stolen.status, 200, JSON.stringify(stolen.body));
    assert.equal(stolen.body.state.wanted, 2);
    assert.equal(stolen.body.state.job.stage, 'delivery');
    await moveTo(stolen.body.state.job.target, true);
    ws.send({t: 'me', walking: false, driving: true, skin: 7,
      car: getaway.v[2], vehicle: 'wrong-car', x, y, z: 13});
    await new Promise(resolve => setTimeout(resolve, 100));
    assert.equal((await api('/api/local/action', 'POST', {action: 'job.complete'})).status, 400);
    ws.send({t: 'me', walking: false, driving: true, skin: 7,
      car: getaway.v[2], vehicle: getaway.v[0], x, y, z: 13});
    await new Promise(resolve => setTimeout(resolve, 3100));
    const escaped = await api('/api/local/action', 'POST', {action: 'job.complete'});
    assert.equal(escaped.status, 200, JSON.stringify(escaped.body));
    assert.equal(escaped.body.state.job, null);
    assert.equal(escaped.body.state.cash, 45150);
    await ws.wait(message => message.t === 'vgone' && message.id === getaway.v[0]);
    const secondTheft = await api('/api/local/action', 'POST', {action: 'job.start', job: 'carthief'});
    assert.equal(secondTheft.status, 200, JSON.stringify(secondTheft.body));
    const savedGetaway = await ws.wait(message => message.t === 'spawned' &&
      message.v[2] === '560.52.39.0.' && message.v[0] !== getaway.v[0]);
    otherWs.close(); otherWs = null;
    ws.close(); ws = null;
    child.kill('SIGINT');
    await new Promise(resolve => child.once('exit', resolve));
    child = start();
    await ready();
    assert.equal((await api('/api/local/state')).body.racesWon, 1);
    assert.equal((await otherApi('/api/local/state')).body.racesFinished, 1);
    assert.equal((await api('/api/local/state')).body.race, null,
      'active race state should not survive a server restart');
    assert.equal((await api('/api/local/state')).body.job.id, 'carthief',
      'unfinished getaway must survive a server restart');
    assert((await api('/api/world/cars')).body.cars.some(car => car[0] === savedGetaway.v[0]),
      'unfinished getaway car must return after a server restart');
    console.log('PASS: guest accounts, six world-objective jobs including getaway, garage persistence and repair, two-player race and payouts, home exterior visit');
  } finally {
    otherWs?.close();
    ws?.close();
    if (child && child.exitCode === null) {
      child.kill('SIGINT');
      await new Promise(resolve => child.once('exit', resolve));
    }
    fs.rmSync(temporary, {recursive: true, force: true});
  }
}

main().catch(error => {console.error(error); process.exitCode = 1;});
