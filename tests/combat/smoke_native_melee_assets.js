#!/usr/bin/env node
'use strict';
// Exercise the real local HTTP overlay with synthetic metadata and catalogs.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const net=require('node:net'),{spawn}=require('node:child_process'),{once}=require('node:events');
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-melee-assets-'));let child;
async function main() {
  const probe=net.createServer();probe.listen(0,'127.0.0.1');await once(probe,'listening');
  const port=probe.address().port;await new Promise(resolve=>probe.close(resolve));
  const local=path.join(temporary,'local-only');fs.mkdirSync(path.join(local,'selfhost'),{recursive:true});
  for(const file of ['serve_local.js','browser_recovery_hook.js','browser_task_policy.js','browser_recovery.js','native_resource_server.js','stock_native_assets.js','stock_img_assets.js','selfhost_backend.js','player_placement.js','optional_discord.js','weapon_inventory.js','world_collision.js',
    'local_projectiles.js','native_radio_server.js','radio_streams.js', 'radio_metadata.js'])fs.copyFileSync(path.join(require('node:path').resolve(__dirname, '../..'),file),path.join(temporary,file));
  for(const [name,value] of [['client-catalog.json',{vehicles:[],homes:[]}],['weapon-catalog.json',{items:[],shops:[]}]])
    fs.writeFileSync(path.join(local,'selfhost',name),JSON.stringify(value));
  let output='';child=spawn(process.execPath,['serve_local.js'],{cwd:temporary,env:{...process.env,ZGTA_BROWSER_TASK_POLICY_PLAN:'',
    PORT:String(port),BIND_HOST:'127.0.0.1',ZGTA_SELFHOST:'1',ZGTA_CONNECTED:'0',
    ZGTA_JOIN_CODE:'synthetic-test-access',ZGTA_JOIN_CODE_FILE:'',ZGTA_ALLOWED_HOSTS:''},stdio:['ignore','pipe','pipe']});
  child.stdout.on('data',d=>{output+=d});child.stderr.on('data',d=>{output+=d});
  await new Promise((resolve,reject)=>{
    const timeout=setTimeout(()=>reject(Error('Isolated HTTP server did not start: '+output)),10000);
    child.once('exit',()=>{clearTimeout(timeout);reject(Error('Isolated HTTP server exited: '+output));});
    child.stdout.on('data',()=>{if(output.includes('ZGTA:SA local mirror:')){clearTimeout(timeout);resolve();}});
  });
  const url=`http://127.0.0.1:${port}/game/native/melee.json`;
  let response=await fetch(url);assert.equal(response.status,404,'Absent generated data must remain absent');
  const bytes=Buffer.from(JSON.stringify({version:1,weapons:[{synthetic:true}]}));
  fs.mkdirSync(path.join(local,'native'),{recursive:true});fs.writeFileSync(path.join(local,'native/melee.json'),bytes);
  response=await fetch(url);assert.equal(response.status,200);assert.deepEqual(Buffer.from(await response.arrayBuffer()),bytes);
  assert.match(response.headers.get('content-type'),/^application\/json/);
  response=await fetch(url,{method:'HEAD'});assert.equal(response.status,200);assert.equal(await response.text(),'');
  assert.equal(response.headers.get('content-length'),String(bytes.length));
  response=await fetch(url,{method:'POST'});assert.equal(response.status,405);assert.equal(response.headers.get('allow'),'GET, HEAD');
  response=await fetch(url,{headers:{'X-Forwarded-For':'192.0.2.1'}});assert.equal(response.status,401,'Overlay bypassed existing join gate');
  response=await fetch(url,{headers:{Origin:'https://unrelated.invalid'}});assert.equal(response.status,403,'Overlay bypassed origin gate');
  assert(!fs.existsSync(path.join(local,'site/game/native/melee.json')),'Metadata was written into archived/shared site');
  console.log('PASS: actual HTTP melee overlay GET/HEAD, missing-data failure, method/origin/join boundaries, separate local-only data');
}
main().catch(error=>{console.error(error);process.exitCode=1}).finally(async()=>{
  if(child && child.exitCode===null){const exited=once(child,'exit');child.kill('SIGTERM');await exited;}
  fs.rmSync(temporary,{recursive:true,force:true});
});
