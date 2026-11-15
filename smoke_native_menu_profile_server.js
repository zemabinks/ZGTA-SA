#!/usr/bin/env node
'use strict';
// Only temporary copies of the real server and synthetic account data are used.
const http=require('node:http'),path=require('node:path'),assert=require('node:assert/strict');
const {spawn}=require('node:child_process');
// Fixture-only code; real authorization handlers see a synthetic remote visitor.
process.env.ZGTA_JOIN_CODE='native83-fixture-join-code';
const game=require(path.join(process.argv[2],'selfhost_backend.js'));
let mode='',calls=[],child,finished=false;
function json(res,status,body){res.writeHead(status,{'Content-Type':'application/json'});res.end(JSON.stringify(body));}
const listeners=[];
const handler=(req,res)=>{
  const url=new URL(req.url,'http://local');
  if(url.pathname==='/test/control'){
    mode=url.searchParams.get('mode')||'';
    if(mode==='seed-existing'){
      const player=[...game.players.values()][0];assert(player);
      Object.assign(player,{cash:12345,xp:2700,jobsDone:6,cars:[410],homes:['starter']});
    }
    json(res,200,{players:game.players.size,calls,names:[...game.players.values()].map(p=>p.name)});return;
  }
  if(url.pathname==='/test/report'){
    json(res,200,{players:game.players.size,calls,names:[...game.players.values()].map(p=>p.name)});return;
  }
  calls.push({path:url.pathname,method:req.method,cookie:req.headers.cookie||'',mode});
  assert.equal(req.headers['x-zgta-inventory-connection'],undefined,'Menu sent a game inventory peer header');
  if(mode==='stats-error' && url.pathname==='/api/local/state')return json(res,409,{error:'Synthetic unavailable state'});
  if(mode==='name-error' && req.method==='PUT')return json(res,400,{error:'Synthetic name rejection'});
  if(mode==='invalid-status' && url.pathname==='/api/local/status')return json(res,200,{players:true,selfhost:true});
  if(mode==='not-selfhost' && url.pathname==='/api/local/status')return json(res,200,{selfhost:false,players:0});
  if(mode==='missing-selfhost' && url.pathname==='/api/local/status')return json(res,200,{players:0});
  if(mode==='invalid-json-status' && url.pathname==='/api/local/status'){
    res.writeHead(200,{'Content-Type':'application/json'});res.end('{malformed');return;
  }
  if((mode==='redirect-status' && url.pathname==='/api/local/status') ||
     (mode==='redirect-auth' && url.pathname==='/api/auth/me') ||
     (mode==='redirect-join' && url.pathname==='/api/local/join')){
    res.writeHead(302,{Location:'http://127.0.0.1:'+listeners[1].address().port+'/test/redirect-leak'});res.end();return;
  }
  const gated=mode==='join-gate'||mode==='join-no-cookie'||mode==='redirect-join';
  if(gated && url.pathname==='/api/local/join'){
    if(mode==='join-no-cookie')return json(res,200,{joined:true});
    Promise.resolve(game.join(req,res)).catch(error=>json(res,500,{error:error.message}));return;
  }
  if(gated){
    req.headers['x-forwarded-for']='192.0.2.83';
    if(!game.authorized(req))return json(res,401,{error:'Fixture join code required'});
  }
  if(mode==='invalid-auth' && url.pathname==='/api/auth/me')return json(res,200,{local:false,loggedIn:true,id:'a'.repeat(32)});
  assert.notEqual(url.pathname,'/test/redirect-leak','Client followed a credential API redirect');
  if((mode==='slow-auth' && url.pathname==='/api/auth/me') ||
     (mode==='slow-status' && url.pathname==='/api/local/status') ||
     (mode==='slow-profile' && url.pathname==='/api/local/profile')){
    const end=res.end.bind(res);res.end=(...args)=>{setTimeout(()=>end(...args),650);return res;};
  }
  Promise.resolve(game.http(req,res)).catch(error=>{console.error(error);json(res,500,{error:error.message});});
};
async function main(){
  for(let i=0;i<2;i++){
    const server=http.createServer(handler);listeners.push(server);
    await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  }
  child=spawn(process.argv[3],listeners.map(s=>'http://127.0.0.1:'+s.address().port),{stdio:'inherit'});
  const code=await new Promise(resolve=>child.once('exit',resolve));
  assert.equal(code,0);assert.equal(game.players.size,2,'Menu created extra anonymous players');
  const names=[...game.players.values()].map(p=>p.name).sort();assert.deepEqual(names,['Menu Alice','Menu Bob']);
  const alice=[...game.players.values()].find(p=>p.name==='Menu Alice');
  assert.equal(alice.cash,12345);assert.equal(alice.xp,2700);assert.equal(alice.jobsDone,6);
  assert.deepEqual(alice.cars,[410]);assert.deepEqual(alice.homes,['starter']);
  assert(calls.filter(c=>c.path==='/api/local/state').length>=3);
  assert(calls.some(c=>c.method==='PUT'));
  for(const forbidden of ['invalid-status','not-selfhost','missing-selfhost','invalid-json-status','redirect-status','slow-status']){
    assert(!calls.some(c=>c.mode===forbidden && c.path==='/api/auth/me'),'Invalid/cancelled status reached auth: '+forbidden);
  }
  assert(calls.some(c=>c.mode==='join-gate' && c.path==='/api/local/join' && c.method==='POST'));
  assert(calls.some(c=>c.mode==='join-gate' && c.path==='/api/auth/me' && c.cookie.includes('zgta_access=')));
  finished=true;
  console.log('PASS real menu HTTP: original management checks plus connect/guest reuse, real join/auth gate, malformed status, redirect blocking and status/auth cancellation');
}
main().catch(error=>{console.error(error);process.exitCode=1;}).finally(async()=>{
  if(child && child.exitCode===null)child.kill();
  await Promise.all(listeners.map(s=>new Promise(resolve=>s.close(resolve))));
  clearInterval(game.tick);clearInterval(game.projectileTimer);clearTimeout(game.saveTimer);
});
setTimeout(()=>{if(!finished){child?.kill();throw Error('Menu HTTP fixture timed out');}},45000).unref();
