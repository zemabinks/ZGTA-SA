#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Actual backend construction, auth, masked Peer packets and flush/reload.
// Reuse the existing independently authored in-memory filesystem/socket/clock
// fixture; never launch a listener or read a real account/catalogue/save.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const assert=require('node:assert/strict'),crypto=require('node:crypto');
const ROOT=__dirname,OUT=path.join(ROOT,'local-only/research/mission-vehicle-persistence-114');
const args=process.argv.slice(2);assert(args.length===0||(args.length===2&&args[0]==='--before'),'Usage: node smoke_selfhost_mission_persistence.js [--before /old/backend.js]');
const before=args.length?path.resolve(args[1]):null,backendFile=before||path.join(ROOT,'selfhost_backend.js');
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
const fixtureFile=path.join(ROOT,'smoke_selfhost_position_resume.js'),fixture=fs.readFileSync(fixtureFile,'utf8');
const end=fixture.indexOf('async function main(){');assert(end>0,'Authored fixture extraction marker changed');
const sourceFS={...fs,readFileSync(file,...rest){return fs.readFileSync(path.resolve(String(file))===path.join(ROOT,'selfhost_backend.js')?backendFile:file,...rest);}};
const {backend,storage,foot}=vm.runInNewContext(fixture.slice(0,end)+'\n;({backend,storage,foot});',{
 require:id=>id==='node:fs'?sourceFS:require(id),process:{argv:process.argv.slice(0,2)},
 __dirname:ROOT,__filename:fixtureFile,Buffer,URL,URLSearchParams,TextEncoder,TextDecoder,console,structuredClone},{filename:'authored-resume-fixture',timeout:5000});
let checks=0;const cases=[];
function check(value,label){checks++;assert(value,label);}
function same(value,wanted,label){checks++;assert.deepEqual(JSON.parse(JSON.stringify(value)),JSON.parse(JSON.stringify(wanted)),label);}
async function scenario(name,body){const start=checks;await body();cases.push({name,checks:checks-start,passed:true});}
function catalogue(){const m=storage(),p='/fixture/local-only/selfhost/client-catalog.json';
 const value=JSON.parse(m.readFileSync(p,'utf8'));
 for(const [key,x,y]of[['b',400,100],['c',700,100],['d',100,500]])value.homes.push({key:'authored-'+key,name:'Authored '+key,price:100,kind:'authored-room',out:[x,y,20,90]});
 m.json('local-only/selfhost/client-catalog.json',value);return m;
}
function rowState(v){return{id:v.id,code:v.row[2],pose:v.row.slice(3,9),health:v.row[9],damage:v.row[10],work:v.row[16]??0};}
function snapshot(h,account){h.game.flushSync();return JSON.parse(h.memory.readFileSync('/fixture/local-only/selfhost/players.json','utf8')).players[account.id];}
async function begin(job='taxi',native=true){
 const h=backend(catalogue()),account=await h.auth(),a=h.connect(account,native?{}:{hi:{t:'hi'}});
 a.send(foot(a));a.player.health=73;a.player.armour=11;
 if(job==='patrol')h.game.action(a.player,'police.duty',{});
 h.game.action(a.player,'job.start',{job});
 const v=h.game.vehicles.get(a.player.job.vehicleId);check(!!v,'Actual '+job+' start failed to create vehicle');
 return{h,account,a,v};
}
function enterAndMove({h,a,v},{health=Math.max(1,v.row[9]-25),pose=null,work=731}={}){
 a.send(foot(a,v.row[3]-2,v.row[4],{z:v.row[5]}));a.send({t:'enter',v:v.id});
 check(a.packets.filter(p=>p.t==='enter').at(-1)?.ok,'Ordinary mission entry rejected');
 const target=pose||[v.row[3]+11.375,v.row[4]+9.625,v.row[5]-0.2,1.094,-0.005,0.125];
 a.send({t:'me',driving:true,skin:7,vehicle:v.id,car:v.row[2],x:target[0],y:target[1],z:target[2],
  heading:target[3],pitch:target[4],roll:target[5],health,life:a.player.health,damage:'authored-body-v1',w:work,
  ...(a.peer.positionAckEnabled?{placement:a.envelope()}:{} )});
 same(v.row.slice(3,9),target.map(n=>Math.round(n*1000)/1000),'Admitted driver pose not recorded');
 check(h.game.vehicleDriver(v)===a.peer||health===0,'Driver role was not admitted');return target;
}
function park({a,v}){
 const state=rowState(v);
 a.send({...foot(a,v.row[3]+2,v.row[4],{z:v.row[5],heading:0.3}),vehicle:v.id,car:v.row[2],
  parked:{x:state.pose[0],y:state.pose[1],z:state.pose[2],heading:state.pose[3],pitch:state.pose[4],roll:state.pose[5],health:state.health,damage:state.damage,w:state.work}});
}
async function restart(f){f.a.close();f.h.stop();const h=backend(f.h.memory,f.h.clock),a=h.connect(await h.auth(f.account.cookie),f.a.peer.inventoryEnabled?{}:{hi:{t:'hi'}});return{h,a,account:{...f.account,player:a.player},v:h.game.vehicles.get(f.v.id)};}
async function historical(){
 const f=await begin();enterAndMove(f);park(f);const expected=rowState(f.v),saved=snapshot(f.h,f.account),originalFactory=[104,103,21.1,0,0,0];
 check(!Object.hasOwn(saved,'missionVehicle'),'Selected before-source already serializes mission bodies');
 const r=await restart(f);check(!!r.v,'Historical task lost identity entirely');same(r.v.id,expected.id,'Historical vehicle ID changed');
 same(r.v.row.slice(3,9),originalFactory,'Historical station-based body recreation not reproduced');
 check(JSON.stringify(r.v.row.slice(3,9))!==JSON.stringify(expected.pose),'Historical pose loss absent');
 same([r.v.row[9],r.v.row[10],r.v.row[16]??0],[1000,'',0],'Historical condition/work reset absent');
 same([r.a.player.health,r.a.player.armour],[73,11],'Historical witness changed actor vitals');
 same(r.h.game.vehicleClaims.size,0,'Historical restart created authority');r.h.stop();
}
async function main(){
 if(before){await scenario('actual pre-change backend loses admitted mission body pose/condition on restart',historical);}
 else{
 await scenario('all ten actual mission factories preserve admitted native and browser bodies across two restarts',async()=>{
  for(const job of ['taxi','medic','trucker','pilot','fire','heist','carthief','mechanic','patrol','pizza'])for(const native of [true,false]){
   const f=await begin(job,native);enterAndMove(f);park(f);check(!f.h.game.vehicleClaim(f.v),job+' exit retained authority');
   const expected=rowState(f.v),saved=snapshot(f.h,f.account),inventory=structuredClone(f.a.player.inventory);
   same(saved.missionVehicle.pose,expected.pose,job+' serialization changed body origin');
   same(Object.keys(saved.missionVehicle).sort(),['code','damage','health','id','job','pose','version','work'],job+' serialized occupant/velocity/action fields');
   const r=await restart(f);check(!!r.v,job+' body missing after restart');same(rowState(r.v),expected,job+' restart changed admitted body');
   same(r.v.row[11],null,job+' restored occupied driver marker');same(r.h.game.vehicleClaims.size,0,job+' restored a driver grant');
   same(r.h.game.passengerClaims.size,0,job+' restored seat grant');same([r.a.player.health,r.a.player.armour],[73,11],job+' body resume changed actor vitals');
   same(r.a.player.inventory,inventory,job+' resume changed inventory');same(r.a.player.job.id,job,job+' lost task');
   const r2=await restart(r);check(!!r2.v,job+' missing after second restart');same(rowState(r2.v),expected,job+' second restart reapplied initial offsets');
   check(!r2.h.errors.length,r2.h.errors.join('\n'));r2.h.stop();
  }
 });
 await scenario('flushed live-driver snapshot restores parked body with no active role and preserves strict foot anchor',async()=>{
  const f=await begin();enterAndMove(f);const expected=rowState(f.v),anchor=structuredClone(f.a.player.reconnectPlacement.foot);
  // Flush while actually driving; no exit packet or invented egress is needed.
  f.h.game.flushSync();f.h.stop();const h=backend(f.h.memory,f.h.clock),a=h.connect(await h.auth(f.account.cookie));
  const v=h.game.vehicles.get(f.v.id);same(rowState(v),expected,'Driving restart moved/repaired hull');
  same(v.row[11],null,'Driving restart retained occupant');same(h.game.vehicleClaims.size,0,'Driving restart granted authority');
  same(a.hello().spot,anchor.spot,'Body snapshot rewrote strict foot checkpoint');same(a.player.reconnectPlacement.foot,anchor,'Body load changed foot record');
  same([a.player.health,a.player.armour],[73,11],'Body checkpoint healed actor');check(!h.errors.length,h.errors.join('\n'));h.stop();
 });
 await scenario('zero-health wreck is preserved and cannot become a driveable mission vehicle after restart',async()=>{
  const f=await begin();enterAndMove(f,{health:0,work:2500});f.a.send(foot(f.a,105,105));
  const expected=rowState(f.v);same(expected.health,0,'Fatal body health not accepted');
  const r=await restart(f);same(rowState(r.v),expected,'Restart healed wreck');
  r.a.send(foot(r.a,r.v.row[3],r.v.row[4],{z:r.v.row[5]}));r.a.send({t:'enter',v:r.v.id});
  check(!r.a.packets.filter(p=>p.t==='enter').at(-1).ok,'Restored wreck granted entry');r.h.stop();
 });
 await scenario('admitted unattended updates persist while malformed, remote-owner and stale-peer reports cannot replace snapshot',async()=>{
  const f=await begin();const other=f.h.connect(await f.h.auth());
  const original=rowState(f.v);other.send(foot(other,100,100));
  const update={t:'vmove',v:f.v.id,x:110,y:115,z:20.5,h:0.4,p:-0.005,r:0.1,hp:920,d:'authored-vmove',w:999};
  other.send(update);same(rowState(f.v),original,'Another account moved private mission vehicle');
  other.send({t:'me',driving:true,vehicle:f.v.id,car:f.v.row[2],x:110,y:115,z:20.5,health:1,placement:other.envelope()});
  same(rowState(f.v),original,'Unclaimed driver changed body');
  for(const bad of [null,true,'x',Infinity])f.a.send({...update,x:bad});
  same(rowState(f.v),original,'Malformed unattended report was admitted');
  f.a.send(update);const expected=rowState(f.v);same(expected.pose,[110,115,20.5,0.4,-0.005,0.1],'Valid unattended update missing');
  check(!!f.h.game.saveTimer,'First admitted unattended update did not schedule persistence');
  f.h.game.flushSync();f.h.advance(100);f.a.send({...update,hp:0});check(!!f.h.game.saveTimer,'Unattended fatal condition did not schedule save');
  const wreck=rowState(f.v);const old=f.a.peer;f.a.close();
  f.h.game.onMessage(old,{...update,hp:1000,x:150});same(rowState(f.v),wreck,'Closed peer changed saved mission body');
  const r=await restart(f);same(rowState(r.v),wreck,'Unattended wreck state lost on restart');other.close();r.h.stop();
 });
 await scenario('cancelled, replaced and expired tasks cannot resurrect a saved mission occurrence',async()=>{
  const f=await begin();enterAndMove(f);park(f);const old=f.v.id;
  f.h.game.action(f.a.player,'job.cancel',{});snapshot(f.h,f.account);
  check(!f.h.game.vehicles.has(old),'Cancel retained mission vehicle');
  let r=await restart(f);same(r.a.player.job,null,'Cancelled task restored');check(!r.h.game.vehicles.has(old),'Cancelled occurrence resurrected');
  r.a.send(foot(r.a));r.h.game.action(r.a.player,'job.start',{job:'taxi'});
  const next=r.a.player.job.vehicleId;check(next!==old,'Replacement reused task vehicle ID');
  const nextVehicle=r.h.game.vehicles.get(next);same(nextVehicle.row.slice(3,9),[104,103,21.1,0,0,0],'Replacement reused old body pose');
  same(nextVehicle.row[9],1000,'Replacement inherited prior body condition');
  r.v=nextVehicle;const second=await restart(r);check(second.h.game.vehicles.has(next)&&!second.h.game.vehicles.has(old),'Restart changed replacement membership');
  second.h.advance(86400001);const expired=await restart(second);same(expired.a.player.job,null,'Expired task survived');
  check(!expired.h.game.vehicles.has(next),'Expired task vehicle resurrected');expired.h.stop();
 });
 await scenario('owned garage pose and strict dead-health/foot admission remain independent',async()=>{
  const f=await begin();f.a.player.cars=[400];f.a.player.garage=[{active:true,position:[90,90,20,0.2],pitch:0.1,roll:-0.2,health:543,damage:'authored-owned',work:123,paint:null,parkedHome:null}];
  const owned=f.h.game.addOwnedVehicle(f.a.player,0),expectedOwned=rowState(owned);enterAndMove(f);park(f);
  const expectedMission=rowState(f.v),anchor=structuredClone(f.a.player.reconnectPlacement.foot);
  f.a.player.health=0;f.a.player.lastDeath=f.h.clock.now;
  const r=await restart(f);same(rowState(r.h.game.ownedVehicle(r.a.player,0)),expectedOwned,'Mission persistence changed owned garage');
  same(rowState(r.v),expectedMission,'Mission body changed beside owned garage');same(r.a.player.health,0,'Mission restart healed dead actor');
  same(r.a.player.reconnectPlacement.foot,anchor,'Mission persistence changed placement checkpoint');r.h.stop();
 });
 await scenario('snapshot schema rejects malformed scalars and mismatched task, occurrence or model',async()=>{
  const f=await begin();enterAndMove(f);park(f);const saved=snapshot(f.h,f.account),record=saved.missionVehicle;
  f.a.close();f.h.stop();
  const mutants=[null,{}, {...record,version:2},{...record,id:'mission-ffffffffffffffff'}, {...record,job:'medic'},
   {...record,code:'438.6.1.0.'},{...record,pose:[1,2,3]},{...record,damage:'x'.repeat(513)}];
  for(const value of [null,true,'1',[],{},-1,0.5,1001,Infinity])mutants.push({...record,health:value});
  for(const value of [null,true,'1',-1,0.5,2501,Infinity])mutants.push({...record,work:value});
  for(const [index,value]of [[0,6001],[1,-6001],[2,-201],[2,1001],[3,1e300],[4,Infinity],[5,true]]){const pose=[...record.pose];pose[index]=value;mutants.push({...record,pose});}
  for(const mutant of mutants){
   const m=catalogue();m.files=new Map([...f.h.memory.files].map(([k,v])=>[k,Buffer.from(v)]));
   const data=JSON.parse(m.readFileSync('/fixture/local-only/selfhost/players.json','utf8'));data.players[f.account.id].missionVehicle=mutant;
   m.json('local-only/selfhost/players.json',data);const h=backend(m),a=h.connect(await h.auth(f.account.cookie)),v=h.game.vehicles.get(record.id);
   same(v.row.slice(3,9),[104,103,21.1,0,0,0],'Invalid snapshot supplied body pose');
   same(v.row[9],1000,'Invalid snapshot supplied body health');same(h.game.vehicleClaims.size,0,'Invalid snapshot granted authority');
   h.stop();
  }
  // Same task/ID with a changed factory model cannot reuse the old model's pose.
  const m=catalogue();m.files=new Map([...f.h.memory.files].map(([k,v])=>[k,Buffer.from(v)]));
  const data=JSON.parse(m.readFileSync('/fixture/local-only/selfhost/players.json','utf8'));data.players[f.account.id].job.model=438;
  m.json('local-only/selfhost/players.json',data);const h=backend(m),a=h.connect(await h.auth(f.account.cookie)),v=h.game.vehicles.get(record.id);
  check(v.row[2].startsWith('438.'),'Authored changed-model control not loaded');same(v.row.slice(3,9),[104,103,21.1,0,0,0],'Changed model borrowed prior pose');h.stop();
 });
 await scenario('older saves without a snapshot retain existing factory fallback and ignore injected actor state',async()=>{
  const f=await begin();enterAndMove(f);park(f);snapshot(f.h,f.account);f.a.close();f.h.stop();
  const state=JSON.parse(f.h.memory.readFileSync('/fixture/local-only/selfhost/players.json','utf8'));const player=state.players[f.account.id];
  delete player.missionVehicle;f.h.memory.json('local-only/selfhost/players.json',state);
  let h=backend(f.h.memory,f.h.clock),a=h.connect(await h.auth(f.account.cookie)),v=h.game.vehicles.get(f.v.id);
  same(v.row.slice(3,9),[104,103,21.1,0,0,0],'Legacy save fallback offsets changed');h.stop();
  const modified=JSON.parse(f.h.memory.readFileSync('/fixture/local-only/selfhost/players.json','utf8'));
  Object.assign(modified.players[f.account.id].missionVehicle,{driver:'FORGED',velocity:[9,9,9],pendingCouplings:[1],owner:'FORGED',claimed:true});
  f.h.memory.json('local-only/selfhost/players.json',modified);h=backend(f.h.memory,f.h.clock);a=h.connect(await h.auth(f.account.cookie));
  const clean=snapshot(h,f.account).missionVehicle;
  same(Object.keys(clean).sort(),['code','damage','health','id','job','pose','version','work'],'Authority/action/velocity state was retained');
  same(h.game.vehicleClaims.size,0,'Injected occupancy restored');same(h.game.passengerClaims.size,0,'Injected seat restored');h.stop();
 });
 }
 fs.mkdirSync(OUT,{recursive:true});const report={status:before?'ACTUAL_PRECHANGE_RESTART_LOSS_REPRODUCED':'PASS',checks,cases,
  backendSHA256:hash(backendFile),fixtureSHA256:hash(fixtureFile),testSHA256:hash(__filename),beforeSource:before,
  limits:['Actual backend/HTTP/Peer/actions/persistence with authored catalogs/geometry and virtual files/sockets/clock/timers; no listener/service/device.',
   'Authored me packets model accepted protocol reports; this does not prove physical travel, suspension, egress or retail behavior.',
   'No original assets, live account/save or QA snapshot is read; only independent source and authored bytes.',
   'Legacy snapshots lack prior body pose; preexisting initial factory offsets are preserved, not certified.']};
 fs.writeFileSync(path.join(OUT,before?'historical-report.json':'report.json'),JSON.stringify(report,null,2)+'\n');
 console.log(JSON.stringify({status:report.status,checks,scenarios:cases.length,backendSHA256:report.backendSHA256}));
}
main().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
