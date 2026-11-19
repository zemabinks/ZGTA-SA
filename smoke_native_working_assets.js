#!/usr/bin/env node
'use strict';
// Exercise the production HTTP overlay with synthetic, owner-independent data.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const net=require('node:net'),{spawn}=require('node:child_process'),{once}=require('node:events');
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-working-assets-'));let child,checks=0;
function equal(a,b,message){checks++;assert.deepEqual(a,b,message)}
async function main(){
  const probe=net.createServer();probe.listen(0,'127.0.0.1');await once(probe,'listening');
  const port=probe.address().port;await new Promise(resolve=>probe.close(resolve));
  const local=path.join(temporary,'local-only'),catalog=path.join(local,'selfhost/coupling-catalog.json');
  const archive=path.join(local,'site/game/native/models'),stage=path.join(local,'native-working/models');
  for(const directory of [path.dirname(catalog),archive,stage])fs.mkdirSync(directory,{recursive:true});
  for(const file of ['serve_local.js','browser_recovery_hook.js','browser_task_policy.js','browser_recovery.js','native_resource_server.js','stock_native_assets.js','stock_img_assets.js','selfhost_backend.js','player_placement.js','vehicle_coupling.js','optional_discord.js',
    'weapon_inventory.js','world_collision.js','local_projectiles.js','native_radio_server.js','radio_streams.js'])
    fs.copyFileSync(path.join(__dirname,file),path.join(temporary,file));
  for(const [name,value]of[['client-catalog.json',{vehicles:[],homes:[]}],['weapon-catalog.json',{items:[],shops:[]}]])
    fs.writeFileSync(path.join(local,'selfhost',name),JSON.stringify(value));
  let output='';child=spawn(process.execPath,['serve_local.js'],{cwd:temporary,env:{...process.env,ZGTA_BROWSER_TASK_POLICY_PLAN:'',
    PORT:String(port),BIND_HOST:'127.0.0.1',ZGTA_SELFHOST:'1',ZGTA_CONNECTED:'0',
    ZGTA_JOIN_CODE:'synthetic-test-access',ZGTA_JOIN_CODE_FILE:'',ZGTA_ALLOWED_HOSTS:''},stdio:['ignore','pipe','pipe']});
  child.stdout.on('data',d=>{output+=d});child.stderr.on('data',d=>{output+=d});
  await new Promise((resolve,reject)=>{
    const timeout=setTimeout(()=>reject(Error('Isolated HTTP server did not start: '+output)),10000);
    child.once('exit',()=>{clearTimeout(timeout);reject(Error('Isolated HTTP server exited: '+output))});
    child.stdout.on('data',()=>{if(output.includes('ZGTA:SA local mirror:')){clearTimeout(timeout);resolve()}});
  });
  const origin=`http://127.0.0.1:${port}`,suffixes=['.rig.bin','.rig.normals.bin','.rig.png','.rig.json'];
  const url=suffix=>origin+'/game/native/models/synthetic'+suffix;
  const old=Buffer.from('synthetic archived family'),fresh=s=>Buffer.from('synthetic staged '+s);
  for(const suffix of suffixes)fs.writeFileSync(path.join(archive,'synthetic'+suffix),old);
  for(const suffix of suffixes){
    const response=await fetch(url(suffix));equal(response.status,200);equal(Buffer.from(await response.arrayBuffer()),old,'Unstaged family must use archive');
  }
  // Each intermediate export must fail closed rather than mix old and new files.
  for(let count=1;count<suffixes.length;count++){
    fs.writeFileSync(path.join(stage,'synthetic'+suffixes[count-1]),fresh(suffixes[count-1]));
    for(const suffix of suffixes){const response=await fetch(url(suffix));equal(response.status,503);equal(response.headers.get('cache-control'),'no-store')}
  }
  fs.writeFileSync(path.join(stage,'synthetic'+suffixes.at(-1)),fresh(suffixes.at(-1)));
  for(const suffix of suffixes){
    let response=await fetch(url(suffix));equal(response.status,200);equal(Buffer.from(await response.arrayBuffer()),fresh(suffix));
    equal(response.headers.get('cache-control'),'no-cache');
    equal(response.headers.get('content-type'),suffix.endsWith('.json')?'application/json; charset=utf-8':suffix.endsWith('.png')?'image/png':'application/octet-stream');
    response=await fetch(url(suffix),{method:'HEAD'});equal(response.status,200);equal(await response.text(),'');equal(response.headers.get('content-length'),String(fresh(suffix).length));
    response=await fetch(url(suffix),{method:'POST'});equal(response.status,405);equal(response.headers.get('allow'),'GET, HEAD');
    response=await fetch(url(suffix),{headers:{'X-Forwarded-For':'192.0.2.1'}});equal(response.status,401,'Working overlay bypassed join gate');
    response=await fetch(url(suffix),{headers:{Origin:'https://unrelated.invalid'}});equal(response.status,403,'Working overlay bypassed origin gate');
  }
  for(const [endpoint,filename] of [['vehicle-coupling.json','coupling-catalog.json'],['vehicle-treads.json','tread-catalog.json']]) {
  const metadata=origin+'/game/native/'+endpoint;
  equal((await fetch(metadata)).status,404);
  const bytes=Buffer.from(JSON.stringify({version:1,models:{synthetic:true}}));fs.writeFileSync(path.join(local,'selfhost',filename),bytes);
  let response=await fetch(metadata);equal(response.status,200);equal(Buffer.from(await response.arrayBuffer()),bytes);
  equal(response.headers.get('content-type'),'application/json; charset=utf-8');
  response=await fetch(metadata,{method:'HEAD'});equal(response.status,200);equal(await response.text(),'');equal(response.headers.get('content-length'),String(bytes.length));
  equal((await fetch(metadata,{method:'POST'})).status,405);
  equal((await fetch(metadata,{headers:{'X-Forwarded-For':'192.0.2.1'}})).status,401);
  equal((await fetch(metadata,{headers:{Origin:'https://unrelated.invalid'}})).status,403);
  }
  for(const suffix of suffixes)equal(fs.readFileSync(path.join(archive,'synthetic'+suffix)),old,'Archive was modified');
  // Encoded separators cannot turn an allowed model name into a private path.
  fs.writeFileSync(path.join(local,'private.rig.json'),'synthetic private canary');
  let response=await fetch(origin+'/game/native/models/%2e%2e%2f%2e%2e%2f%2e%2e%2fprivate.rig.json');
  equal(response.status,404);equal((await response.text()).includes('synthetic private canary'),false);
  console.log(`PASS: ${checks} actual HTTP working-family/metadata checks; complete-family overlay, partial-export rejection, archive fallback, GET/HEAD, access boundaries`);
}
main().catch(error=>{console.error(error);process.exitCode=1}).finally(async()=>{
  if(child&&child.exitCode===null){const exited=once(child,'exit');child.kill('SIGTERM');await exited}
  fs.rmSync(temporary,{recursive:true,force:true});
});
