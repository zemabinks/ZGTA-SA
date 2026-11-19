#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Actual backend/HTTP auth/masked Peer/health ACK route. Authored water,
// virtual files/sockets/clock/timers. No listener, save or original game data.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),assert=require('node:assert/strict'),crypto=require('node:crypto');
const ROOT=path.resolve(__dirname,'../..'),OUT=path.join(ROOT,'local-only/research/breath-140');
const args=process.argv.slice(2);assert(args.length===0||(args.length===2&&args[0]==='--before'),'Usage: smoke_selfhost_breath_lifecycle.js [--before /old/backend.js]');
const before=args.length?path.resolve(args[1]):null,backendFile=before||path.join(ROOT,'selfhost_backend.js');
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const fixtureFile=path.join(ROOT,'tests/network/smoke_selfhost_position_resume.js'),source=fs.readFileSync(fixtureFile,'utf8');
const end=source.indexOf('async function main(){');assert(end>0);
const heldHashes=Object.fromEntries([backendFile,fixtureFile,__filename].map(p=>[p,hash(p)]));
const sourceFS={...fs,readFileSync(file,...rest){const requested=path.resolve(String(file));assert(path.dirname(requested)===ROOT,'Source escaped authored checkout');return fs.readFileSync(requested===path.join(ROOT,'selfhost_backend.js')?backendFile:requested,...rest);}};
const {backend,storage,foot}=vm.runInNewContext(source.slice(0,end)+'\n;({backend,storage,foot});',{
 require:id=>id==='node:fs'?sourceFS:require(id),__dirname:path.dirname(fixtureFile),__filename:fixtureFile,
 process:{argv:[]},Buffer,URL,URLSearchParams,TextEncoder,TextDecoder,console,structuredClone},{filename:'authored-breath-fixture',timeout:5000});
let checks=0;const cases=[],healthTrace=[];
function check(value,label){checks++;assert(value,label);}
function same(value,wanted,label){checks++;assert.deepEqual(JSON.parse(JSON.stringify(value)),JSON.parse(JSON.stringify(wanted)),label);}
function near(value,wanted,label){checks++;assert(Number.isFinite(value)&&Math.abs(value-wanted)<1e-8,label+': '+value+' vs '+wanted);}
function world(){const m=storage(),index=JSON.parse(m.readFileSync('/fixture/local-only/site/game/world/index.json','utf8'));
 index.water=[[90,90,24,110,90,24,90,110,24,110,110,24]];m.json('local-only/site/game/world/index.json',index);return m;}
async function actor(){const h=backend(world()),account=await h.auth();account.player.armour=50;const a=h.connect(account,{position:false});
 a.send(foot(a,100,100,{act:14}));near(a.peer.nativeOxygen,1150,'Fresh Peer first report');return{h,a,account};}
function report(f,elapsed,extra={}){const since=f.h.clock.now-f.a.peer.nativeOxygenAt,advance=elapsed-since-20;check(advance>=0,'Authored report clock moved backwards');
 f.h.advance(advance);f.a.send(foot(f.a,100,100,{act:14,...extra}));}
function request(f,s,kind,damage=0){const at=f.a.packets.length;f.a.send({t:'selfHealth',c:f.a.peer.inventoryConnection,s,kind,damage});
 const packet=f.a.packets.slice(at).filter(p=>p.t==='vitals').at(-1);check(!!packet?.healthAck,'Actual Peer omitted health ACK');return packet;}
async function scenario(name,body){const start=checks;await body();cases.push({name,checks:checks-start,passed:true});}
async function main(){
 await scenario('accepted respawn retires prior life oxygen clock; rejected and duplicate requests do not grant air',async()=>{
  for(const [action,elapsed,consumed]of[[14,20,100/60],[14,100,10],[15,100,5],[0,100,0]]){
   const f=await actor();try{
    const old=f.a.peer.nativeOxygenAt;
    request(f,1,'hurt',100);same(f.a.player.health,0,'Actual fatal request');
    request(f,2,'respawn');same(f.a.player.health,0,'Cooldown rejection revived');same(f.a.peer.nativeOxygenAt,old,'Rejected respawn reset breath clock');
    f.h.advance(2200);request(f,3,'respawn');same(f.a.player.health,100,'Accepted respawn failed');
    const respawnedAt=f.h.clock.now;
    if(before){same(f.a.peer.nativeOxygenAt,old,'Historical timestamp defect not present');}
    else same(f.a.peer.nativeOxygenAt,respawnedAt,'Accepted respawn retained prior life oxygen clock');
    // Report after a concrete amount of new-life time, independent of the old timestamp.
    f.h.advance(elapsed-20);f.a.send(foot(f.a,100,100,{act:action}));
    if(before&&action!==0){check(f.a.peer.nativeOxygen<1150-consumed-1,'Historical dead-time charge absent');}
    else near(f.a.peer.nativeOxygen,1150-consumed,'New-life breath charged outside new-life interval');
    const oxygen=f.a.peer.nativeOxygen,at=f.a.peer.nativeOxygenAt;
    request(f,3,'respawn');near(f.a.peer.nativeOxygen,oxygen,'Duplicate respawn granted air');same(f.a.peer.nativeOxygenAt,at,'Duplicate respawn reset clock');
   }finally{f.h.stop()}
  }
 });
 if(!before){
 await scenario('real Peer drowning ACKs preserve armour and pending fall/impact sequence ownership',async()=>{
  const f=await actor();try{
   const hello=f.a.hello();healthTrace.push({stage:'begin',packet:hello});
   // Explicit near-exhaustion authored boundary; no real client state is injected.
   f.a.peer.nativeOxygen=0;f.a.peer.nativeOxygenTime=0;f.a.peer.nativeDrownFraction=0;
   let at=f.a.packets.length;report(f,100);let drown=f.a.packets.slice(at).filter(p=>p.t==='vitals').at(-1);
   check(!!drown?.healthAck,'Drowning bypassed actual Peer ACK owner');same([drown.health,drown.armour,drown.healthAck.processed],[96,50,0],'Drowning changed local loss watermark/armour');healthTrace.push({stage:'drown-before-fall',packet:drown});
   const fall=request(f,1,'hurt',9);same([fall.health,fall.armour,fall.healthAck.processed],[87,50,1],'Fall applied more than once');healthTrace.push({stage:'fall-ack',packet:fall});
   at=f.a.packets.length;report(f,100);drown=f.a.packets.slice(at).filter(p=>p.t==='vitals').at(-1);
   same([drown.health,drown.armour,drown.healthAck.processed],[82,50,1],'Interleaved drowning changed impact/loss authority');healthTrace.push({stage:'drown-before-impact',packet:drown});
   const impact=request(f,2,'impact',20);same([impact.health,impact.armour,impact.healthAck.processed],[82,30,2],'Impact armour absorption duplicated');healthTrace.push({stage:'impact-ack',packet:impact});
   const count=f.a.packets.length;request(f,2,'impact',20);same([f.a.player.health,f.a.player.armour],[82,30],'Duplicate impact reapplied');check(f.a.packets.length>count,'Duplicate request not acknowledged');
   let lastRevision=impact.healthAck.revision;
   for(let i=0;i<25;i++){
    at=f.a.packets.length;report(f,100);
    for(const packet of f.a.packets.slice(at).filter(p=>p.t==='vitals')){
     check(packet.healthAck.revision>lastRevision,'Drowning health revision did not advance');lastRevision=packet.healthAck.revision;
     same(packet.healthAck.processed,2,'Drown consumed a local health sequence');same(packet.armour,30,'Drown consumed armour');
    }
   }
   same([f.a.player.health,f.a.player.deaths],[0,1],'Drowning did not produce exactly one death');
   report(f,100);same(f.a.player.deaths,1,'Dead reports duplicated death');
  }finally{f.h.stop()}
 });
 await scenario('normal depletion, recovery and reconnect share one authoritative physiological lifetime',async()=>{
  const f=await actor();try{
   for(let i=0;i<20;i++)report(f,100);
   near(f.a.peer.nativeOxygen,950,'Normal under rate');same(f.a.player.health,100,'Damage before exhaustion');
   report(f,100,{act:15});near(f.a.peer.nativeOxygen,945,'Glide effort rate');
   report(f,100,{act:0});near(f.a.peer.nativeOxygen,955,'Recovery rate');
   const nonce=f.a.peer.inventoryConnection,health=f.a.player.health;f.a.close();
   const next=f.h.connect(await f.h.auth(f.account.cookie),{position:false});
   check(next.peer.inventoryConnection!==nonce,'New Peer reused physiological namespace');next.send(foot(next,100,100,{act:14}));
   near(next.peer.nativeOxygen,1150,'Fresh Peer retained prior breath');same(next.player.health,health,'Breath lifetime healed health');
  }finally{f.h.stop()}
 });
 }
 fs.mkdirSync(OUT,{recursive:true});check(Object.entries(heldHashes).every(([p,h])=>hash(p)===h),'Source changed while actual Peer test ran');
 const result={status:before?'HISTORICAL_DEAD_TIME_CHARGE_REPRODUCED':'PASS',checks,cases,healthTrace,sourceHashes:heldHashes,sourceUnchanged:true,backendSHA256:hash(backendFile),fixtureSHA256:hash(fixtureFile),scope:'Actual backend and Peer with authored geometry/virtual clock/files/sockets; no native scene, browser runtime, hardware or retail acceptance.'};
 fs.writeFileSync(path.join(OUT,before?'server-historical.json':'server-lifecycle.json'),JSON.stringify(result,null,2)+'\n');
 console.log(JSON.stringify({status:result.status,checks,scenarios:cases.length}));
}
main().catch(e=>{console.error(e.stack||e);process.exitCode=1});
