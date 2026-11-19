#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
// Exercise owner-radio delivery through the actual host's access checks.
'use strict';
const assert = require('node:assert/strict');
const fs = require('node:fs'), path = require('node:path'), os = require('node:os');
const http = require('node:http'), net = require('node:net'), crypto = require('node:crypto');
const {spawn} = require('node:child_process');
const {fixture} = require('./smoke_browser_radio');
const {register} = require('./native_radio_server');

async function main() {
  const root = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'zgta-radio-http-'));
  let child, logs = '', checks = 0;
  const check = (value, message) => {assert(value, message); checks++;};
  const digest = bytes => crypto.createHash('sha256').update(bytes).digest('hex');
  try {
    for (const name of ['serve_local.js','browser_recovery_hook.js','browser_recovery.js','browser_task_policy.js',
      'native_resource_server.js','stock_native_assets.js','stock_img_assets.js','selfhost_backend.js','player_placement.js',
      'local_gameplay.js','native_radio_server.js','radio_streams.js','radio_metadata.js','optional_discord.js',
      'weapon_inventory.js','world_collision.js','local_projectiles.js'])
      fs.copyFileSync(path.join(__dirname,name), path.join(root,name));
    const local = path.join(root,'local-only'), site = path.join(local,'site');
    fs.mkdirSync(path.join(site,'game/world'), {recursive:true});
    fs.writeFileSync(path.join(site,'game/world/index.json'), '{"water":[],"tiles":[]}');
    fs.writeFileSync(path.join(site,'game/world/collision.json'), '{"cells":[]}');
    fs.mkdirSync(path.join(local,'selfhost'), {recursive:true});
    fs.writeFileSync(path.join(local,'selfhost/client-catalog.json'), '{"vehicles":[],"homes":[]}');
    const rows = fixture(path.join(root,'authored-owner'));
    const {configuration} = register(path.join(root,'authored-owner'), {localOnly:local});
    const bankBefore = rows.map(row => [fs.statSync(row.file).mtimeMs,digest(fs.readFileSync(row.file))]);
    const listener = net.createServer();
    await new Promise(resolve => listener.listen(0,'127.0.0.1',resolve));
    const port = listener.address().port;
    await new Promise(resolve => listener.close(resolve));
    const origin = `http://127.0.0.1:${port}`;
    child = spawn(process.execPath,['serve_local.js'], {cwd:root, env:{...process.env,
      ZGTA_SELFHOST:'1', ZGTA_CONNECTED:'0', BIND_HOST:'127.0.0.1', PORT:String(port),
      ZGTA_JOIN_CODE:'authored-radio-access', ZGTA_JOIN_CODE_FILE:'', ZGTA_ALLOWED_HOSTS:'',
      ZGTA_RADIO_CONFIGURATION:configuration, ZGTA_RADIO_CACHE:path.join(local,'native-radio-cache'),
      ZGTA_BROWSER_TASK_POLICY_PLAN:''}});
    child.stdout.on('data',bytes => {logs = (logs+bytes).slice(-16000);});
    child.stderr.on('data',bytes => {logs = (logs+bytes).slice(-16000);});
    const request = (route, options={}) => fetch(origin+route, {...options,signal:AbortSignal.timeout(10000)});
    for (let attempt=0; attempt<60; attempt++) {
      if (child.exitCode!==null) throw Error('Authored radio host exited: '+logs);
      try {if ((await request('/api/local/join',{method:'POST',headers:{'Content-Type':'application/json'},body:'{"code":"wrong"}'})).status===403) break;} catch {}
      if (attempt===59) throw Error('Authored radio host unavailable: '+logs);
      await new Promise(resolve=>setTimeout(resolve,100));
    }
    const remote = {'X-Forwarded-For':'192.0.2.24'};
    for (const route of ['/game/radio/index','/game/radio/track/0','/game/radio/native/index']) {
      check((await request(route,{headers:remote})).status===401, 'Radio routes cannot bypass the remote join gate');
    }
    const joined = await request('/api/local/join',{method:'POST',headers:{...remote,'Content-Type':'application/json'},body:'{"code":"authored-radio-access"}'});
    check(joined.status===200, 'Normal host join succeeds');
    const headers = {...remote,Cookie:joined.headers.get('set-cookie').split(';')[0]};
    let reply = await request('/game/radio/index',{headers});
    check(reply.status===200, 'Authenticated browser index resolves locally');
    const bytes = Buffer.from(await reply.arrayBuffer()), index = JSON.parse(bytes);
    assert.deepEqual(index,{stations:[[],[[1,5],[3,1]],[[0,3]],[],[],[],[],[],[],[],[],[],[]],adverts:[[2,2]]}); checks++;
    check(!bytes.includes(Buffer.from(root)) && reply.headers.get('cache-control')==='no-store', 'Public index reveals no owner path and is not stale cached');
    reply = await request('/game/radio/index',{method:'HEAD',headers});
    check(reply.status===200 && Number(reply.headers.get('content-length'))===bytes.length && (await reply.arrayBuffer()).byteLength===0, 'HTTP index HEAD has matching metadata and no body');
    const native = await request('/game/radio/native/index',{headers});
    check(native.status===200 && (await native.json()).stations[1][0].id===1, 'Native index remains reachable');
    for (const [id,row] of rows.entries()) {
      reply = await request('/game/radio/track/'+id,{headers});
      check(reply.status===200 && reply.headers.get('content-type')==='audio/ogg', 'Compressed track has correct HTTP type');
      check(Buffer.from(await reply.arrayBuffer()).equals(row.bytes), 'HTTP payload matches the full authored Ogg exactly');
    }
    for (const [range,start,end] of [['bytes=7-33',7,33],['bytes=65531-65551',65531,65551],['bytes=-19',rows[1].bytes.length-19,rows[1].bytes.length-1]]) {
      reply = await request('/game/radio/track/1',{headers:{...headers,Range:range}});
      check(reply.status===206 && reply.headers.get('content-range')===`bytes ${start}-${end}/${rows[1].bytes.length}`, 'HTTP byte range preserves exact bounds');
      check(Buffer.from(await reply.arrayBuffer()).equals(rows[1].bytes.subarray(start,end+1)), 'HTTP ranged XOR payload remains exact');
      reply = await request('/game/radio/track/1',{method:'HEAD',headers:{...headers,Range:range}});
      check(reply.status===206 && Number(reply.headers.get('content-length'))===end-start+1 && (await reply.arrayBuffer()).byteLength===0, 'Ranged HEAD opens no response body');
    }
    for (const range of ['bytes=0-1,3-4','bytes=-0','bytes=999999999-'])
      check((await request('/game/radio/track/1',{headers:{...headers,Range:range}})).status===416, 'Invalid range is rejected over actual HTTP');
    check((await request('/game/radio/track/0',{method:'POST',headers})).status===405, 'Track method restriction remains active');
    check((await request('/game/radio/index',{method:'POST',headers})).status===405, 'Index method restriction remains active');
    check((await request('/game/radio/track/01',{headers})).status===404, 'Malformed ID cannot fall through to a copied or remote file');
    const hostStatus = await new Promise((resolve,reject)=>{
      const req = http.get(origin+'/game/radio/index',{headers:{...headers,Host:'unexpected.invalid'}},res=>{res.resume();resolve(res.statusCode);});
      req.on('error',reject);
    });
    check(hostStatus===421, 'Host fence precedes the radio handler');
    check((await request('/game/radio/index',{headers:{...headers,Origin:'https://unexpected.invalid'}})).status===403, 'Origin fence precedes the radio handler');
    check(!fs.existsSync(path.join(local,'native-radio-cache')), 'Browser delivery creates no decoded PCM cache');
    rows.forEach((row,i)=>check(fs.statSync(row.file).mtimeMs===bankBefore[i][0] && digest(fs.readFileSync(row.file))===bankBefore[i][1], 'Original fixture banks remain unchanged'));
    fs.writeFileSync(configuration,'{invalid');
    reply = await request('/game/radio/index',{headers});
    check(reply.status===503 && await reply.text()==='Owner radio audio is unavailable', 'Owner failure is sanitized through the host');
    check((await request('/game/radio/index',{headers:remote})).status===401, 'Failed registration cannot disable authorization');
    console.log(`PASS browser radio HTTP: ${checks} actual host/auth/index/full/range/HEAD/failure checks; authored files only`);
  } finally {
    if (child && child.exitCode===null) {
      child.kill('SIGTERM');
      await Promise.race([new Promise(resolve=>child.once('exit',resolve)),new Promise(resolve=>setTimeout(resolve,3000))]);
      if (child.exitCode===null) {child.kill('SIGKILL');await new Promise(resolve=>child.once('exit',resolve));}
    }
    fs.rmSync(root,{recursive:true,force:true});
  }
}
main().catch(error=>{console.error(error);process.exitCode=1;});
