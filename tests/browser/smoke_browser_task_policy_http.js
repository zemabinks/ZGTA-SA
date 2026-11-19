// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const net=require('node:net'),http=require('node:http'),{spawn}=require('node:child_process');
const fixture=require('./smoke_browser_task_policy');
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-policy-http-'));
let child,logs='',checks=0;
async function freePort(){const server=net.createServer();await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));const port=server.address().port;await new Promise(resolve=>server.close(resolve));return port;}
async function main(){
 for(const file of ['serve_local.js','browser_recovery_hook.js','browser_recovery.js','browser_task_policy.js',
  'native_resource_server.js','stock_native_assets.js','stock_img_assets.js','selfhost_backend.js','player_placement.js',
  'local_gameplay.js','native_radio_server.js','radio_streams.js', 'radio_metadata.js','optional_discord.js','weapon_inventory.js',
  'world_collision.js','local_projectiles.js'])fs.copyFileSync(path.join(require('node:path').resolve(__dirname, '../..'),file),path.join(temporary,file));
 const site=path.join(temporary,'local-only/site');fs.mkdirSync(path.join(site,'_next/static/chunks'),{recursive:true});
 fs.mkdirSync(path.join(site,'game/world'),{recursive:true});
 fs.writeFileSync(path.join(site,'index.html'),'<!doctype html><html><body>Authored fixture</body></html>');
 fs.writeFileSync(path.join(site,'game/world/index.json'),'{"water":[],"tiles":[]}');
 fs.writeFileSync(path.join(site,'game/world/collision.json'),'{"cells":[]}');
 const state=path.join(temporary,'local-only/selfhost');fs.mkdirSync(state,{recursive:true});
 fs.writeFileSync(path.join(state,'client-catalog.json'),'{"vehicles":[],"homes":[]}');
 const target=path.join(site,'_next/static/chunks/policy-fixture.js');
 const aliasMode=process.argv.includes('--archive-alias');
 if(aliasMode){
  const bank=path.join(temporary,'authored-archive');fs.mkdirSync(bank);
  const physical=path.join(bank,'policy-fixture.js');fs.writeFileSync(physical,fixture.source);fs.symlinkSync(physical,target);
 }else{fs.writeFileSync(target,fixture.source);}
 fs.writeFileSync(path.join(site,'_next/static/chunks/unrelated.js'),'// independently authored unrelated file');
 const plan=JSON.parse(JSON.stringify(fixture.plan));plan.source.path=target;
 if(aliasMode)plan.source.relativePath='_next/static/chunks/policy-fixture.js';
 fs.writeFileSync(path.join(temporary,'local-only/browser-task-policy.json'),JSON.stringify(plan));
 const port=await freePort(),origin=`http://127.0.0.1:${port}`;
 child=spawn(process.execPath,['serve_local.js'],{cwd:temporary,env:{...process.env,ZGTA_SELFHOST:'1',ZGTA_CONNECTED:'0',
  BIND_HOST:'127.0.0.1',PORT:String(port),ZGTA_JOIN_CODE:'authored-policy-test-code',ZGTA_ALLOWED_HOSTS:'',
  ZGTA_BROWSER_TASK_POLICY_PLAN:path.join(temporary,'local-only/browser-task-policy.json')}});
 child.stdout.on('data',data=>logs+=data);child.stderr.on('data',data=>logs+=data);
 for(let i=0;i<60;i++){
  if(child.exitCode!==null)throw Error('Fixture server exited: '+logs);
  try{const r=await fetch(origin+'/api/local/join',{method:'POST',headers:{'Content-Type':'application/json'},body:'{"code":"wrong"}'});if(r.status===403)break;}catch{}
  if(i===59)throw Error('Fixture server unavailable: '+logs);
  await new Promise(resolve=>setTimeout(resolve,100));
 }
 const route='/_next/static/chunks/policy-fixture.js';
 // Exercise the existing remote-client gate through its supported loopback
 // reverse-proxy path. Direct trusted loopback is intentionally authorized.
 const remoteHeaders={'X-Forwarded-For':'192.0.2.24'};
 let r=await fetch(origin+route,{headers:remoteHeaders});checks++;assert.equal(r.status,401,'policy cannot bypass the join gate');
 r=await fetch(origin+'/api/local/join',{method:'POST',headers:{...remoteHeaders,'Content-Type':'application/json'},body:'{"code":"authored-policy-test-code"}'});
 checks++;assert.equal(r.status,200);const cookie=r.headers.get('set-cookie').split(';')[0],headers={...remoteHeaders,Cookie:cookie};
 r=await fetch(origin+route,{headers});checks++;assert.equal(r.status,200);
 checks++;assert(Buffer.from(await r.arrayBuffer()).equals(fixture.output));
 checks++;assert.equal(r.headers.get('cache-control'),'no-store');checks++;assert.equal(r.headers.get('accept-ranges'),'none');
 checks++;assert.equal(Number(r.headers.get('content-length')),fixture.output.length);
 r=await fetch(origin+route,{method:'HEAD',headers});checks++;assert.equal(r.status,200);
 checks++;assert.equal((await r.arrayBuffer()).byteLength,0);checks++;assert.equal(Number(r.headers.get('content-length')),fixture.output.length);
 r=await fetch(origin+route,{headers:{...headers,Range:'bytes=0-3'}});checks++;assert.equal(r.status,200);
 checks++;assert(Buffer.from(await r.arrayBuffer()).equals(fixture.output),'partial unpatched script escaped');
 r=await fetch(origin+route,{method:'POST',headers});checks++;assert.equal(r.status,405);
 const hostStatus=await new Promise((resolve,reject)=>{
  const req=http.get(origin+route,{headers:{...headers,Host:'unexpected.invalid'}},res=>{res.resume();resolve(res.statusCode);});req.on('error',reject);
 });checks++;assert.equal(hostStatus,421);
 r=await fetch(origin+route,{headers:{...headers,Origin:'https://unexpected.invalid'}});checks++;assert.equal(r.status,403);
 r=await fetch(origin+'/_next/static/chunks/unrelated.js',{headers});checks++;assert.equal(r.status,200);
 checks++;assert.equal(await r.text(),'// independently authored unrelated file');
 fs.appendFileSync(target,' ');r=await fetch(origin+route,{headers});checks++;assert.equal(r.status,503);
 checks++;assert.equal(await r.text(),'Local browser gameplay policy unavailable.');
 checks++;assert(fs.readFileSync(target).equals(Buffer.concat([fixture.source,Buffer.from(' ')])),'server modified owner source');
 console.log(`PASS browser task policy HTTP: ${checks} actual server/auth/method/cache/drift checks; no game assets`);
}
main().catch(error=>{console.error(error.stack);process.exitCode=1;}).finally(async()=>{
 if(child&&child.exitCode===null){child.kill('SIGTERM');await Promise.race([new Promise(resolve=>child.once('exit',resolve)),new Promise(resolve=>setTimeout(resolve,3000))]);if(child.exitCode===null)child.kill('SIGKILL');}
 fs.rmSync(temporary,{recursive:true,force:true});
});
