#!/usr/bin/env node
// End-to-end check of the local multiplayer wire format; no game assets or
// player accounts are copied into this repository.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const net = require('node:net');
const os = require('node:os');
const path = require('node:path');
const {spawn} = require('node:child_process');

function openSocket(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url);
    ws.addEventListener('open', () => resolve(ws), {once: true});
    ws.addEventListener('error', reject, {once: true});
  });
}

function inbox(ws) {
  const messages = [];
  const waiting = [];
  ws.addEventListener('message', event => {
    const message = JSON.parse(event.data);
    messages.push(message);
    for (const wait of [...waiting]) {
      if (!wait.match(message)) continue;
      clearTimeout(wait.timer);
      waiting.splice(waiting.indexOf(wait), 1);
      wait.resolve(message);
    }
  });
  return (match, timeout = 5000) => {
    const found = messages.find(match);
    if (found) return Promise.resolve(found);
    return new Promise((resolve, reject) => {
      const wait = {match, resolve, timer: setTimeout(() => {
        waiting.splice(waiting.indexOf(wait), 1);
        reject(new Error('Timed out waiting for a multiplayer message: '+String(match)));
      }, timeout)};
      waiting.push(wait);
    });
  };
}

async function freePort() {
  const server = net.createServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  const port = server.address().port;
  await new Promise(resolve => server.close(resolve));
  return port;
}

async function main() {
  const temporary = fs.mkdtempSync(path.join(os.tmpdir(), 'zgta-smoke-'));
  const local = path.join(temporary, 'local-only');
  fs.mkdirSync(local);
  fs.symlinkSync(path.join(__dirname, 'local-only', 'site'), path.join(local, 'site'));
  fs.mkdirSync(path.join(local,'selfhost'));
  fs.copyFileSync(path.join(__dirname,'local-only/selfhost/client-catalog.json'),path.join(local,'selfhost/client-catalog.json'));
  for (const file of ['serve_local.js','browser_recovery_hook.js','browser_task_policy.js','browser_recovery.js', 'native_resource_server.js', 'stock_native_assets.js', 'stock_img_assets.js', 'native_radio_server.js', 'radio_streams.js', 'prepare_native_radio_audio.py', 'selfhost_backend.js','player_placement.js', 'optional_discord.js', 'weapon_inventory.js', 'world_collision.js', 'local_projectiles.js'])
    fs.copyFileSync(path.join(__dirname, file), path.join(temporary, file));
  const port = await freePort();
  const child = spawn(process.execPath, ['serve_local.js'], {
    cwd: temporary, env: {...process.env,ZGTA_BROWSER_TASK_POLICY_PLAN:'', ZGTA_SELFHOST: '1', PORT: String(port),
      BIND_HOST: '127.0.0.1', ZGTA_JOIN_CODE: '', ZGTA_JOIN_CODE_FILE: '', ZGTA_ALLOWED_HOSTS: ''},
    stdio: ['ignore', 'pipe', 'pipe'],
  });
  let errors = '';
  child.stderr.on('data', bytes => { errors += bytes.toString(); });
  const clients = [];
  try {
    let ready = false;
    for (let attempt = 0; attempt < 40; attempt++) {
      try {
        const response = await fetch(`http://127.0.0.1:${port}/api/local/status`);
        if (response.ok) { ready = true; break; }
      } catch {}
      if (child.exitCode !== null) break;
      await new Promise(resolve => setTimeout(resolve, 100));
    }
    assert(ready, `Local test server did not start: ${errors}`);
    const duplicatePort = await freePort();
    const duplicate = spawn(process.execPath, ['serve_local.js'], {
      cwd: temporary, env: {...process.env,ZGTA_BROWSER_TASK_POLICY_PLAN:'', ZGTA_SELFHOST: '1', PORT: String(duplicatePort),
        BIND_HOST: '127.0.0.1', ZGTA_JOIN_CODE: '', ZGTA_JOIN_CODE_FILE: '', ZGTA_ALLOWED_HOSTS: ''},
      stdio: ['ignore', 'ignore', 'pipe'],
    });
    let duplicateError = '';
    duplicate.stderr.on('data', bytes => {duplicateError += bytes.toString();});
    const duplicateExit = await new Promise(resolve => {
      const timer = setTimeout(() => duplicate.kill('SIGTERM'), 3000);
      duplicate.once('exit', code => {clearTimeout(timer); resolve(code);});
    });
    assert.notEqual(duplicateExit, 0, 'A second server must not write the same player file');
    assert.match(duplicateError, /Local player state is already in use/);
    const firstApi = await fetch(`http://127.0.0.1:${port}/api/auth/me`);
    assert.equal(firstApi.status, 200);
    assert.match(firstApi.headers.get('set-cookie') || '', /^zgta_local=/);
    assert.match(firstApi.headers.get('set-cookie') || '', /Max-Age=31536000/,
      'The guest account cookie must survive an app restart');
    const auth = await firstApi.json();
    assert.equal(auth.loggedIn, true, 'The browser must see a playable account');
    assert.equal(auth.available, true);
    assert.match(auth.username, /^Local /);
    const existingApi = await fetch(`http://127.0.0.1:${port}/api/auth/me`, {
      headers: {Cookie: firstApi.headers.get('set-cookie').split(';')[0]},
    });
    assert.equal((await existingApi.json()).username, auth.username,
      'Reconnecting with the guest cookie must keep the same player');
    assert.match(existingApi.headers.get('set-cookie') || '', /Max-Age=31536000/,
      'Existing guest accounts must have their persistent cookie renewed');
    await new Promise(resolve => setTimeout(resolve, 400));
    const saved = JSON.parse(fs.readFileSync(path.join(local, 'selfhost', 'players.json')));
    assert.equal(Object.keys(saved.players).length, 1, 'An API-first visit must create one account');
    const a = await openSocket(`ws://127.0.0.1:${port}/api/world/live`);
    const b = await openSocket(`ws://127.0.0.1:${port}/api/world/live`);
    clients.push(a, b);
    const fromA = inbox(a), fromB = inbox(b);
    a.send(JSON.stringify({t: 'hi'}));
    b.send(JSON.stringify({t: 'hi'}));
    const allA = await fromA(message => message.t === 'all');
    const allB = await fromB(message => message.t === 'all');
    assert.notEqual(allA.id, allB.id);
    a.send(JSON.stringify({t: 'me', walking: true, skin: 7, x: 1480.5,
      y: -1738.25, z: 13, health: 86, armour: 25,
      on: {v: 'test-object', x: 1, y: 2, z: 3},
      anim: 'ped/walk/l/1', say: 'smoke hello'}));
    const walking = await fromB(message => message.t === 'cars' &&
      message.c.some(row => row[0] === allA.id && row[2] === 's7'));
    const foot = walking.c.find(row => row[0] === allA.id);
    assert.equal(foot.length, 50);
    assert.equal(foot[18], 86);
    assert.deepEqual(foot[39], ['test-object', 1, 2, 3]);
    assert.equal(foot[41], 'ped/walk/l/1');
    await fromB(message => message.t === 'chat' &&
      message.lines.some(line => line[2] === 'smoke hello'));
    b.send(JSON.stringify({t: 'me', walking: true, skin: 23,
      x: 1482, y: -1738, z: 13}));
    b.send(JSON.stringify({t: 'me', walking: true, skin: 23,
      x: 1482, y: -1738, z: 13, riding: 'car-1', seat: 1}));
    assert.equal((await fromB(message=>message.t==='enter'&&message.v==='car-1'&&message.seat===1)).ok,
      false,'A nonexistent vehicle cannot grant passenger authority');
    const passenger = await fromA(message => message.t === 'cars' &&
      message.c.some(row => row[0] === allB.id && row[2] === 's23'));
    assert.equal(passenger.c.find(row => row[0] === allB.id)[34], null);
    a.send(JSON.stringify({t:'me',walking:true,skin:7,x:1480.5,y:-1738.25,z:13,health:86,say:'/job taxi'}));
    const loaner=(await fromA(message=>message.t==='spawned'&&message.v[2]==='420.6.1.0.')).v;
    b.send(JSON.stringify({t:'me',walking:true,driving:false,skin:23,
      x:loaner[3],y:loaner[4],z:loaner[5],riding:loaner[0],seat:1}));
    const aboard=await fromA(message=>message.t==='cars'&&
      message.c.some(row=>row[0]===allB.id&&row[34]?.[0]===loaner[0]));
    assert.deepEqual(aboard.c.find(row=>row[0]===allB.id)[34],[loaner[0],1]);
    a.send(JSON.stringify({t:'enter',v:loaner[0]}));
    assert.equal((await fromA(message=>message.t==='enter'&&message.v===loaner[0])).ok,true,'Driver must enter an actual nearby server vehicle');
    a.send(JSON.stringify({t: 'me', driving: true, car: loaner[2], vehicle:loaner[0], skin: 7,
      x: 1485, y: -1738, z: 13, health: 910, life: 75, smoke: 0.5, kit: [1, 2]}));
    const driving = await fromB(message => message.t === 'cars' &&
      message.c.some(row => row[0] === allA.id && row[2] === loaner[2]));
    const car = driving.c.find(row => row[0] === allA.id);
    assert.equal(car[18], 910);
    assert.equal(car[43], 75);
    b.send(JSON.stringify({t: 'board'}));
    const board = await fromB(message => message.t === 'board');
    assert.equal(board.rows.length, 2);
    a.send(JSON.stringify({t: 'me', walking: true, skin: 7,
      x: 1485, y: -1738, z: 13, health: 75, weapon: 0,say:'/canceljob'}));
    await fromA(message=>message.t==='vgone'&&message.id===loaner[0]);
    b.send(JSON.stringify({t: 'me', walking: true, skin: 23,
      x: 1482, y: -1738, z: 13, health: 100, weapon: 0}));
    await new Promise(resolve => setTimeout(resolve, 100));
    b.send(JSON.stringify({t: 'hit', to: allA.id, n: 1}));
    const melee = await fromA(message => message.t === 'hit' &&
      message.from === allB.id);
    assert.equal(melee.d, 8);
    assert.equal((await fromB(message => message.t === 'wanted' && message.l === 1)).l, 1);
    b.send(JSON.stringify({t: 'me', walking: true, skin: 23,
      x: 1482, y: -1738, z: 13, health: 100, weapon: 22,
      say: '/passive'}));
    await fromB(message => message.t === 'note' && message.text.includes('Clear your wanted'));
    b.send(JSON.stringify({t: 'shot', w: 22, o: [9999, 9999, 9999],
      h: [1485, -1738, 13], ht: 1}));
    b.send(JSON.stringify({t: 'hit', to: allA.id, n: 1}));
    await new Promise(resolve => setTimeout(resolve, 400));
    const rejectedOrigin = JSON.parse(fs.readFileSync(path.join(local, 'selfhost', 'players.json')));
    assert.equal(Object.values(rejectedOrigin.players).find(player => player.name === allA.you).health,
      67, 'a shot from outside the shooter position cannot damage another player');
    b.send(JSON.stringify({t: 'shot', w: 22, o: [1482, -1738, 13],
      h: [1485, -1738, 13], ht: 1}));
    const gunfire = await fromA(message => message.t === 'shot' &&
      message.from === allB.id);
    assert.equal(gunfire.w, 22);
    await new Promise(resolve => setTimeout(resolve, 150));
    b.send(JSON.stringify({t: 'hit', to: allA.id, n: 1}));
    const gunHit = await fromA(message => message.t === 'hit' &&
      message.from === allB.id && message.w === 22);
    assert.equal(gunHit.d, 18);
    assert.equal((await fromB(message => message.t === 'wanted' && message.l === 2)).l, 2);
    b.send(JSON.stringify({t: 'shot', w: 22, o: [1482, -1738, 13],
      h: [1500, -1738, 13], ht: 1}));
    await fromA(message => message.t === 'shot' && message.h[0] === 1500);
    await new Promise(resolve => setTimeout(resolve, 120));
    b.send(JSON.stringify({t: 'hit', to: allA.id, n: 1}));
    await new Promise(resolve => setTimeout(resolve, 400));
    const missedTarget = JSON.parse(fs.readFileSync(path.join(local, 'selfhost', 'players.json')));
    assert.equal(Object.values(missedTarget.players).find(player => player.name === allA.you).health,
      49, 'a shot ending away from the target cannot damage the target');
    a.send(JSON.stringify({t: 'me', walking: true, skin: 7,
      x: 1485, y: -1738, z: 13, health: 49, weapon: 0,
      say: '/police'}));
    await fromA(message => message.t === 'note' && message.text.includes('Police duty on'));
    a.send(JSON.stringify({t: 'me', walking: true, skin: 7,
      x: 1485, y: -1738, z: 13, health: 49, weapon: 0,
      say: `/arrest ${allB.id}`}));
    await fromA(message => message.t === 'note' && message.text.includes('Arrested'));
    assert.equal((await fromB(message => message.t === 'wanted' && message.l === 0)).l, 0);
    b.send(JSON.stringify({t: 'me', walking: true, skin: 23,
      x: 1482, y: -1738, z: 13, health: 100, weapon: 0,
      say: '/passive'}));
    assert.equal((await fromB(message => message.t === 'passive' && message.on === true)).on, true);
    a.send(JSON.stringify({t: 'hit', to: allB.id, n: 1}));
    await new Promise(resolve => setTimeout(resolve, 450));
    const combatSave = JSON.parse(fs.readFileSync(path.join(local, 'selfhost', 'players.json')));
    const officer = Object.values(combatSave.players).find(player => player.name === allA.you);
    const suspect = Object.values(combatSave.players).find(player => player.name === allB.you);
    assert.equal(officer.health, 49);
    assert.equal(officer.arrests, 1);
    assert.equal(officer.cash, 100);
    assert.equal(suspect.health, 100, 'passive mode prevents player damage');
    assert.equal(suspect.wanted, 0);
    assert.equal(suspect.passive, true);
    b.send(JSON.stringify({t: 'me', walking: true, skin: 23,
      x: 1482, y: -1738, z: 13, health: 100, weapon: 34,
      say: '/passive'}));
    await fromB(message => message.t === 'note' && message.text.includes('Passive mode off'));
    b.send(JSON.stringify({t: 'shot', w: 34, o: [1482, -1738, 13],
      h: [1485, -1738, 13], ht: 1}));
    await fromA(message => message.t === 'shot' && message.w === 34);
    b.send(JSON.stringify({t: 'hit', to: allA.id, n: 1}));
    await fromA(message => message.t === 'kill' && message.vn === allA.you);
    await new Promise(resolve => setTimeout(resolve, 400));
    const defeated = JSON.parse(fs.readFileSync(path.join(local, 'selfhost', 'players.json')));
    const deadOfficer = Object.values(defeated.players).find(player => player.name === allA.you);
    const killer = Object.values(defeated.players).find(player => player.name === allB.you);
    assert.equal(deadOfficer.health, 0);
    assert.equal(deadOfficer.deaths, 1);
    assert.equal(killer.kills, 1);
    assert.equal(killer.wanted, 1);
    await new Promise(resolve => setTimeout(resolve, 1800));
    a.send(JSON.stringify({t: 'me', walking: true, skin: 7,
      x: 1485, y: -1738, z: 13, health: 100, weapon: 0}));
    await new Promise(resolve => setTimeout(resolve, 400));
    const recovered = JSON.parse(fs.readFileSync(path.join(local, 'selfhost', 'players.json')));
    assert.equal(Object.values(recovered.players).find(player =>
      player.name === allA.you).health, 100, 'client respawn restores local health');
    const c = await openSocket(`ws://127.0.0.1:${port}/api/world/live`);
    clients.push(c);
    const fromC = inbox(c);
    c.send(JSON.stringify({t: 'hi'}));
    const allC = await fromC(message => message.t === 'all');
    assert.notEqual(allC.id, allA.id);
    a.send(JSON.stringify({t: 'me', walking: true, skin: 7,
      x: 1485, y: -1738, z: 13, health: 100,
      say: `/party invite ${allB.id}`}));
    await fromB(message => message.t === 'note' && message.text.includes('invited you'));
    b.send(JSON.stringify({t: 'me', walking: true, skin: 23,
      x: 1482, y: -1738, z: 13, health: 100, say: '/party accept'}));
    await fromA(message => message.t === 'note' && message.text.includes('joined the group'));
    a.send(JSON.stringify({t: 'me', walking: true, skin: 7,
      x: 1485, y: -1738, z: 13, health: 100, say: '/p private hello'}));
    await fromB(message => message.t === 'note' && message.text.includes('[Group]') &&
      message.text.includes('private hello'));
    await assert.rejects(fromC(message => message.t === 'note' &&
      message.text.includes('private hello'), 400), /Timed out/,
    'a third player must not receive private group chat');
    a.send(JSON.stringify({t: 'me', walking: true, skin: 7,
      x: 1485, y: -1738, z: 13, health: 100, say: '/party leave'}));
    await fromB(message => message.t === 'note' && message.text.includes('left the group'));
    b.send(JSON.stringify({t: 'me', walking: true, skin: 23,
      x: 1482, y: -1738, z: 13, health: 100, say: '/p new leader'}));
    await fromB(message => message.t === 'note' && message.text.includes('[Group]') &&
      message.text.includes('new leader'));
    b.close();
    await fromA(message => message.t === 'gone' && message.id === allB.id);
    console.log('PASS: accounts, movement, chat, combat, wanted level, arrest, respawn, group invites and private chat');
  } finally {
    for (const ws of clients) if (ws.readyState === WebSocket.OPEN) ws.close();
    child.kill('SIGINT');
    if (child.exitCode === null) await new Promise(resolve => child.once('exit', resolve));
    fs.rmSync(temporary, {recursive: true, force: true});
  }
}

main().catch(error => {console.error(error); process.exitCode = 1;});
