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
  for (const file of ['serve_local.js', 'selfhost_backend.js', 'local_gameplay.js'])
    fs.copyFileSync(path.join(__dirname, file), path.join(temporary, file));
  const port = await freePort();
  let child, ws;
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
    const first = await fetch(root + '/api/auth/me');
    const cookie = first.headers.get('set-cookie')?.split(';')[0];
    assert(cookie);
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
    const earlyBuy = await api('/api/local/action', 'POST', {action: 'car.buy', model: 410});
    assert.equal(earlyBuy.status, 400);
    let x = 1480;
    async function travel(goal) {
      for (let travelled = 0; travelled < goal; travelled += 5) {
        const step = Math.min(5, goal - travelled);
        x += step;
        ws.send({t: 'me', walking: true, skin: 7, x, y: -1738, z: 13});
      }
      await new Promise(resolve => setTimeout(resolve, 100));
      const state = await api('/api/local/state');
      assert.equal(state.body.job.remaining, 0, JSON.stringify(state.body.job));
    }

    for (const job of ['courier', 'taxi', 'mechanic', 'medic', 'trial', 'courier']) {
      const startJob = await api('/api/local/action', 'POST', {action: 'job.start', job});
      assert.equal(startJob.status, 200, JSON.stringify(startJob.body));
      const tooEarly = await api('/api/local/action', 'POST', {action: 'job.complete'});
      assert.equal(tooEarly.status, 400);
      await travel(startJob.body.state.job.goal);
      await new Promise(resolve => setTimeout(resolve, 3100));
      const paid = await api('/api/local/action', 'POST', {action: 'job.complete'});
      assert.equal(paid.status, 200, JSON.stringify(paid.body));
      assert.equal(paid.body.state.job, null);
    }
    const money = await api('/api/local/state');
    assert.equal(money.body.cash, 1950);
    assert.equal(money.body.jobsDone, 6);
    const buyCar = await api('/api/local/action', 'POST', {action: 'car.buy', model: 410});
    assert.equal(buyCar.status, 200);
    assert.equal(buyCar.body.state.cash, 1450);
    const spawnCar = await api('/api/local/action', 'POST', {action: 'car.spawn', slot: 0});
    assert.equal(spawnCar.status, 200, JSON.stringify(spawnCar.body));
    const vehicle = await ws.wait(message => message.t === 'spawned');
    assert.equal(vehicle.v[2], '410.52.39.0.');
    assert.equal(vehicle.v[5], 14.1, 'vehicle origin must clear the ground');
    ws.send({t: 'enter', v: vehicle.v[0]});
    assert.equal((await ws.wait(message => message.t === 'enter')).ok, true);
    const noHome = await api('/api/local/action', 'POST', {action: 'home.buy', home: 'starter'});
    assert.equal(noHome.status, 400);
    const extra = await api('/api/local/action', 'POST', {action: 'job.start', job: 'courier'});
    assert.equal(extra.status, 200);
    await travel(extra.body.state.job.goal);
    await new Promise(resolve => setTimeout(resolve, 3100));
    assert.equal((await api('/api/local/action', 'POST', {action: 'job.complete'})).status, 200);
    const buyHome = await api('/api/local/action', 'POST', {action: 'home.buy', home: 'starter'});
    assert.equal(buyHome.status, 200, JSON.stringify(buyHome.body));
    assert.equal(buyHome.body.state.cash, 200);
    ws.close(); ws = null;
    child.kill('SIGINT');
    await new Promise(resolve => child.once('exit', resolve));
    child = start();
    await ready();
    const saved = await api('/api/local/state');
    assert.equal(saved.body.cash, 200);
    assert.equal(saved.body.jobsDone, 7);
    assert.equal(saved.body.cars[0].model, 410);
    assert.equal(saved.body.homes[0].id, 'starter');
    ws = await connect(port, cookie);
    ws.send({t: 'hi'});
    const owned = await ws.wait(message => message.t === 'owned');
    assert.deepEqual(owned.cars, ['410.52.39.0.']);
    console.log('PASS: shared account, job travel and payout, cash, car ownership and spawn, home purchase, persistence and reconnect');
  } finally {
    ws?.close();
    if (child && child.exitCode === null) {
      child.kill('SIGINT');
      await new Promise(resolve => child.once('exit', resolve));
    }
    fs.rmSync(temporary, {recursive: true, force: true});
  }
}

main().catch(error => {console.error(error); process.exitCode = 1;});
