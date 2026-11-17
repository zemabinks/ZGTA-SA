#!/usr/bin/env node
'use strict';
// Independent server authority and actual backend handlers. All catalog values
// below are invented test geometry; no original scripts/assets or listener.
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),crypto=require('node:crypto');
const {EventEmitter}=require('node:events');
const args=process.argv.slice(2);let baselineModule=null,reportDirectory=null;
for(let i=0;i<args.length;i++){
  if(args[i]==='--baseline-module'&&args[i+1])baselineModule=path.resolve(args[++i]);
  else if(args[i]==='--report-dir'&&args[i+1])reportDirectory=path.resolve(args[++i]);
  else throw Error(`Unknown or incomplete argument: ${args[i]}`);
}
const files=['selfhost_backend.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js','vehicle_coupling.js'];
const hash=bytes=>crypto.createHash('sha256').update(bytes).digest('hex');
const sourcePaths=Object.fromEntries(files.map(file=>[file,file==='vehicle_coupling.js'&&baselineModule?baselineModule:path.join(__dirname,file)]));
const captured=Object.fromEntries(files.map(file=>[file,fs.readFileSync(sourcePaths[file])]));
const hashes=Object.fromEntries(files.map(file=>[file,hash(captured[file])]));
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-coupling-server-'));
const originalNow=Date.now,games=[],failures=[],scenarios=[];
let now=1_700_000_000_000,checks=0,current='setup';
function check(value,label,details){checks++;if(!value)throw Error(`${label}${details===undefined?'':`: ${JSON.stringify(details)}`}`);}
function equal(a,b,label){check(JSON.stringify(a)===JSON.stringify(b),label,{actual:a,expected:b});}
function scenario(name,body){current=name;const before=checks;try{body();scenarios.push({name,checks:checks-before,passed:true});}catch(error){failures.push({scenario:name,error:error.message});scenarios.push({name,checks:checks-before,passed:false});}}
const definition=(id,kind,extra={})=>({id,kind,minimum:[-1,-2,-1],frontAnchor:[0,.5,-2],rearAnchor:null,trailerAnchor:null,targets:[],...extra});
const catalog={version:1,models:{
  8001:definition(8001,'car',{rearAnchor:[0,.5,3],targets:[8002]}),
  8002:definition(8002,'trailer',{rearAnchor:[0,.5,3],trailerAnchor:[0,.5,-2],targets:[8002]}),
  8003:definition(8003,'car',{working:{tow:true,available:true}}),
  8004:definition(8004,'car'),
  8005:definition(8005,'car',{working:{tow:true,available:false}}),
}};
function vehicle(id,model,x=100,y=100,z=20,h=0,p=0,r=0,work=0){return{id,row:[id,'Synthetic',`${model}.0`,x,y,z,h,p,r,1000,'',null,null,null,null,null,work]};}
function direct(model=8001){
  const authority=Coupling.create(catalog),vehicles=new Map(),peers=new Set();
  const root=vehicle('root',model,100,100,20,0,0,0,model===8003?2500:0),target=vehicle('a',8002,100,95,20);
  vehicles.set(root.id,root);vehicles.set(target.id,target);
  const peer={ready:true,player:{health:100,insideHome:null},state:{driving:true,vehicle:root.id,car:root.row[2]}};peers.add(peer);
  const request=(parent='root',trailer='a',kind='trailer',at=now)=>authority.request({peer,parent,trailer,kind,vehicles,peers,now:at});
  return{authority,vehicles,peers,peer,root,target,request};
}
function fixture(name,withMetadata=true){
  const folder=path.join(temporary,name),local=path.join(folder,'local-only/selfhost');fs.mkdirSync(local,{recursive:true});
  for(const file of files)if(withMetadata||file!=='vehicle_coupling.js')fs.writeFileSync(path.join(folder,file),captured[file]);
  fs.writeFileSync(path.join(local,'client-catalog.json'),JSON.stringify({vehicles:[],homes:[]}));
  fs.writeFileSync(path.join(local,'weapon-catalog.json'),JSON.stringify({items:[],shops:[]}));
  if(withMetadata)fs.writeFileSync(path.join(local,'coupling-catalog.json'),JSON.stringify(catalog));
  const game=require(path.join(folder,'selfhost_backend.js'));games.push(game);
  // No timer should mutate a controlled scenario or survive this fixture.
  clearInterval(game.tick);clearInterval(game.projectileTimer);return{game,folder,local};
}
function peer(game,mode='native',handshake=true){
  const account=game.ensurePlayer({headers:{}},{setHeader(){}}),packets=[];
  const p={player:account.player,ready:false,closed:false,lastSeen:now,state:{walking:true,x:100,y:100,z:20},
    send:message=>packets.push(structuredClone(message)),packets};game.peers.add(p);
  if(handshake)game.onMessage(p,{t:'hi',...(mode==='native'?{nativeInventory:true,inventoryAck:1,couplingAck:1}:mode==='inventory-only'?{nativeInventory:true,inventoryAck:1}:{})});
  return p;
}
function drive(game,p,root){
  p.player.health=100;p.player.insideHome=null;
  game.onMessage(p,{t:'me',walking:true,x:root.row[3],y:root.row[4],z:root.row[5]});
  game.onMessage(p,{t:'enter',v:root.id});
  check(game.vehicleClaim(root)?.peer===p,'Real enter denied coupling fixture');
  game.onMessage(p,{t:'me',driving:true,vehicle:root.id,car:root.row[2],x:root.row[3],y:root.row[4],z:root.row[5],heading:root.row[6],pitch:root.row[7],roll:root.row[8]});
  check(game.vehicleDriver(root)===p,'Real first drive did not establish coupling fixture');
}
function reset(game,mode='native'){
  for(const p of [...game.peers])game.remove(p);game.vehicles.clear();game.coupling=Coupling.create(catalog);now+=10_000;
  const p=peer(game,mode),root=vehicle('root',8001),a=vehicle('a',8002,100,95),b=vehicle('b',8002,100,90),c=vehicle('c',8002,100,85);
  for(const v of[root,a,b,c])game.vehicles.set(v.id,v);drive(game,p,root);return{p,root,a,b,c};
}
function hitch(game,p,s,parent='root',trailer='a',kind='trailer',connection=p.inventoryConnection){game.onMessage(p,{t:'hitch',v:parent,tr:trailer,kind,c:connection,s});}
const ack=p=>p.packets.filter(m=>m.t==='couplings'&&m.ack).at(-1);
function me(game,p,changes={}){game.onMessage(p,{t:'me',...p.state,...changes});}
function move(game,p,id,changes={}){const v=game.vehicles.get(id);game.onMessage(p,{t:'vmove',v:id,x:v.row[3],y:v.row[4],z:v.row[5],h:v.row[6],p:v.row[7],r:v.row[8],hp:v.row[9],...changes});}
let Coupling,main;
try{
  Date.now=()=>now;
  const moduleFolder=path.join(temporary,'module');fs.mkdirSync(moduleFolder);fs.writeFileSync(path.join(moduleFolder,'vehicle_coupling.js'),captured['vehicle_coupling.js']);
  Coupling=require(path.join(moduleFolder,'vehicle_coupling.js'));
  scenario('catalog validation and empty initial state',()=>{
    for(const value of[{}, {version:2,models:catalog.models}, {version:1,models:{x:{...catalog.models[8001],frontAnchor:[NaN,0,0]}}}])check(!Coupling.create(value).enabled,'malformed or absent geometry enabled authority');
    const f=direct();check(f.authority.enabled,'valid synthetic catalog disabled');equal(f.authority.snapshot(),{revision:0,links:[]},'initial topology differs');
  });
  scenario('driver, source and target authority rejections leave topology unchanged',()=>{
    const cases=[
      ['not-ready',f=>{f.peer.ready=false;}],['unregistered-peer',f=>f.peers.delete(f.peer)],
      ['dead-driver',f=>{f.peer.player.health=0;}],['inside-home',f=>{f.peer.player.insideHome='interior';}],
      ['not-driving',f=>{f.peer.state.driving=false;}],['different-root',f=>{f.peer.state.vehicle='other';}],
      ['wrong-model',f=>{f.peer.state.car='8999.0';}],['missing-parent',f=>f.vehicles.delete('root')],
      ['dead-parent',f=>{f.root.row[9]=0;}],['unknown-parent-model',f=>{f.root.row[2]='8999.0';f.peer.state.car='8999.0';}],
      ['foreign-mission-root',f=>{f.root.missionOwner={};}],['missing-target',f=>f.vehicles.delete('a')],
      ['dead-target',f=>{f.target.row[9]=0;}],['foreign-mission-target',f=>{f.target.missionOwner={};}],
      ['unknown-target-model',f=>{f.target.row[2]='8999.0';}],['nonfinite-source-position',f=>{f.root.row[3]=NaN;}],
      ['nonfinite-source-angle',f=>{f.root.row[6]=NaN;}],['nonfinite-target-angle',f=>{f.target.row[7]=Infinity;}],
      ['driven-target',f=>f.peers.add({ready:true,state:{vehicle:'a',driving:true}})],
      ['passenger-target',f=>f.peers.add({ready:true,state:{vehicle:'a',passenger:true}})],
      ['horizontal-distance',f=>{f.target.row[3]+=.421;}],['vertical-distance',f=>{f.target.row[5]+=1.021;}],
    ];
    for(const[name,mutate]of cases){const f=direct();mutate(f);check(!f.request().accepted,`accepted ${name}`);equal(f.authority.snapshot(),{revision:0,links:[]},`${name} changed topology`);}
    for(const[parent,trailer,kind,clock]of[[null,'a','trailer',now],['root',{},'trailer',now],['x'.repeat(65),'a','trailer',now],['root','x'.repeat(65),'trailer',now],['root','a','bogus',now],['root','root','trailer',now],['root','a','trailer',NaN],['root','a','trailer',Infinity]]){
      const f=direct();check(!f.request(parent,trailer,kind,clock).accepted,'malformed request accepted');check(f.authority.snapshot().revision===0,'malformed request advanced revision');
    }
    const own=direct();own.root.missionOwner=own.peer.player;own.target.missionOwner=own.peer.player;check(own.request().accepted,'same-player mission rejected');
  });
  scenario('two trailer links, duplicates, claim ownership and cycle/third limits',()=>{
    const f=direct();f.vehicles.set('b',vehicle('b',8002,100,90));f.vehicles.set('c',vehicle('c',8002,100,85));
    check(f.request().accepted,'first link rejected');check(f.request().accepted,'same legacy refresh rejected');check(f.authority.snapshot().revision===1,'duplicate changed revision');
    check(!f.request('root','b').accepted,'parent acquired another target without release');
    check(f.request('a','b').accepted,'second trailer link rejected');check(f.authority.snapshot().revision===2,'second link did not revise');
    check(!f.request('b','c').accepted,'third link accepted');check(!f.request('b','root').accepted,'cycle/root target accepted');check(!f.request('a','a').accepted,'self link accepted');
    check(f.authority.rootOf('b')==='root','root traversal differs');check(f.authority.canMove(f.peer,'a'),'owner cannot move claimed child');
    check(!f.authority.canMove({},'a'),'foreign peer can move claimed child');check(f.authority.canMove({},'unclaimed'),'unclaimed movement blocked');
    const foreign={ready:true,player:{health:100},state:{driving:true,vehicle:'other',car:'8001.0'}};f.peers.add(foreign);f.vehicles.set('other',vehicle('other',8001));
    check(!f.authority.request({peer:foreign,parent:'other',trailer:'b',kind:'trailer',vehicles:f.vehicles,peers:f.peers,now}).accepted,'foreign root stole target');
    check(f.request('a',null).accepted,'partial chain release rejected');equal(f.authority.snapshot().links,[{parent:'root',trailer:'a',kind:'trailer'}],'partial release removed wrong link');
    check(f.request('root',null).accepted,'root release rejected');equal(f.authority.snapshot().links,[],'root release retained descendant');
  });
  scenario('tow bar state, target kinds, tow release and mixed-chain rejection',()=>{
    for(const work of[0,2499,2501,NaN]){const f=direct(8003);f.target.row[2]='8004.0';f.target.row[4]=94.95;f.root.row[16]=work;check(!f.request('root','a','tow').accepted,`tow attached with work ${work}`);}
    const f=direct(8003);f.target.row[2]='8001.0';f.target.row[4]=94.95;f.vehicles.set('b',vehicle('b',8002,100,89.95));
    check(f.request('root','a','tow').accepted,'lowered tow bar rejected');check(f.request('root','a','tow').accepted,'tow refresh rejected');
    check(!f.request('a','b','trailer').accepted,'mixed tow-to-tractor-to-trailer topology accepted');
    equal(f.authority.snapshot().links,[{parent:'root',trailer:'a',kind:'tow'}],'mixed rejection changed valid tow');
    check(f.request('root',null,'tow').accepted,'tow release failed');check(f.request('root','a','tow').accepted,'tow incorrectly acquired trailer cooldown');
    for(const setup of[f=>{f.target.row[2]='8002.0';},f=>{f.root.row[2]='8005.0';f.peer.state.car='8005.0';}]){const t=direct(8003);t.target.row[4]=94.95;setup(t);check(!t.request('root','a','tow').accepted,'invalid tow source/target accepted');}
  });
  scenario('same-target 2500ms cooldown allows a different target immediately',()=>{
    const f=direct();f.vehicles.set('b',vehicle('b',8002,100,95));check(f.request().accepted,'initial attach failed');check(f.request('root',null).accepted,'release failed');
    check(!f.request('root','a','trailer',now+2499).accepted,'same target bypassed release cooldown');
    check(f.request('root','b','trailer',now+2499).accepted,'different target was blocked by parent-wide cooldown');
    check(f.request('root',null,'trailer',now+2499).accepted,'second release failed');
    check(f.request('root','a','trailer',now+2500).accepted,'different last-released target still blocked');
    const exact=direct();check(exact.request().accepted,'exact-boundary attach failed');check(exact.request('root',null).accepted,'exact-boundary release failed');check(exact.request('root','a','trailer',now+2500).accepted,'cooldown did not expire at 2500ms');
  });
  scenario('pruning death, exit, occupant, disconnect and subtree removal',()=>{
    for(const[label,mutate]of[
      ['driver-death',f=>{f.peer.player.health=0;}],['driver-exit',f=>{f.peer.state.driving=false;}],['driver-disconnect',f=>f.peers.delete(f.peer)],
      ['target-death',f=>{f.target.row[9]=0;}],['root-despawn',f=>f.vehicles.delete('root')],['target-despawn',f=>f.vehicles.delete('a')],
      ['target-occupant',f=>f.peers.add({ready:true,state:{vehicle:'a',passenger:true}})],
    ]){const f=direct();check(f.request().accepted,`${label} setup failed`);mutate(f);check(f.authority.prune(f.vehicles,f.peers,now),`${label} was not pruned`);equal(f.authority.snapshot().links,[],`${label} left a link`);check(f.authority.canMove({},'a'),`${label} leaked movement claim`);}
    for(const method of['releasePeer','removeVehicle']){const f=direct();f.vehicles.set('b',vehicle('b',8002,100,90));check(f.request().accepted,'lifecycle setup first failed');check(f.request('a','b').accepted,'lifecycle setup second failed');check(f.authority[method](method==='releasePeer'?f.peer:'a',now),`${method} reported no mutation`);equal(f.authority.snapshot().links,[],`${method} left descendants`);check(!f.authority[method](method==='releasePeer'?f.peer:'a',now),`${method} non-idempotent`);}
  });
  scenario('rotated and tilted BODY anchor geometry uses wire YXZ signs',()=>{
    const independent=(a,h,p,r)=>{const rz=[Math.cos(r)*a[0]-Math.sin(r)*a[1],Math.sin(r)*a[0]+Math.cos(r)*a[1],a[2]];const rx=[rz[0],Math.cos(p)*rz[1]-Math.sin(p)*rz[2],Math.sin(p)*rz[1]+Math.cos(p)*rz[2]];return[Math.cos(h)*rx[0]+Math.sin(h)*rx[2],rx[1],-Math.sin(h)*rx[0]+Math.cos(h)*rx[2]];};
    for(const h of[0,Math.PI/2,-Math.PI/2,Math.PI,.731])for(const p of[0,.13,-.29])for(const r of[0,.22,-.17]){
      const f=direct(),rootAngle=[h,p,r],targetAngle=[h+.11,p-.04,r+.03];f.root.row.splice(6,3,...rootAngle);f.target.row.splice(6,3,...targetAngle);
      const rear=independent(catalog.models[8001].rearAnchor,...rootAngle),front=independent(catalog.models[8002].trailerAnchor,...targetAngle);
      const anchor=[100+rear[0],20+rear[1],-100+rear[2]];
      f.target.row.splice(3,3,anchor[0]-front[0],-(anchor[2]-front[2]),anchor[1]-front[1]);
      const actual=Coupling.worldAnchor(f.root,catalog.models[8001].rearAnchor);
      check(Math.max(...actual.map((v,i)=>Math.abs(v-anchor[i])))<1e-12,'world anchor did not use wire BODY coordinates');
      check(f.request().accepted,'coincident rotated anchors rejected');
    }
  });
  scenario('wire quantization allowance is bounded at original threshold plus 20mm',()=>{
    for(const kind of['trailer','tow'])for(const axis of['horizontal','vertical']){
      const original=axis==='vertical'?1:kind==='tow'?.5:.4;
      for(const[distance,expected]of[[original,true],[original+.019999,true],[original+.02,true],[original+.020001,false],[original+.05,false]]){
        const f=direct(kind==='tow'?8003:8001);f.root.row.splice(3,3,0,0,0);
        if(kind==='tow')f.target.row[2]='8004.0';
        f.target.row.splice(3,3,axis==='horizontal'?distance:0,kind==='tow'?-5.05:-5,axis==='vertical'?distance:0);
        check(f.request('root','a',kind).accepted===expected,`${kind} ${axis} ${distance} violated bounded allowance`);
      }
    }
  });
  main=fixture('actual-backend');const game=main.game;
  scenario('actual hello negotiates capability and immediately sends empty baseline',()=>{
    const{p}=reset(game);const i=p.packets.findIndex(m=>m.t==='hello');check(i>=0,'no hello');check(p.packets[i].couplingAck===1,'capability absent');
    check(typeof p.inventoryConnection==='string'&&p.inventoryConnection.length>0,'connection nonce absent');equal(p.packets[i+1],{t:'couplings',state:{revision:0,links:[]}},'baseline not immediately after hello');
    const unready=peer(game,'native',false);hitch(game,unready,1);check(unready.processedCouplingSequence===undefined,'unready request consumed sequence');
  });
  scenario('actual ordered ACKs accept/reject/duplicate, nonce and sequence gaps',()=>{
    const{p}=reset(game);const observer=peer(game);observer.packets.length=0;
    for(const[s,c]of[[1,'old-nonce'],[2,p.inventoryConnection],[0,p.inventoryConnection],[1.5,p.inventoryConnection],[Number.MAX_SAFE_INTEGER+1,p.inventoryConnection]]){const count=p.packets.length;hitch(game,p,s,'root','a','trailer',c);check(p.packets.length===count,'invalid nonce/sequence got reply');check(p.processedCouplingSequence===0,'invalid nonce/sequence consumed state');}
    hitch(game,p,1);equal(ack(p),{t:'couplings',state:{revision:1,links:[{parent:'root',trailer:'a',kind:'trailer'}]},ack:{connection:p.inventoryConnection,sequence:1,processed:1,accepted:true}},'first ACK differs');
    check(observer.packets.some(m=>m.t==='couplings'&&m.state.revision===1&&!m.ack),'topology update was not broadcast without owner ACK');
    const revision=game.coupling.snapshot().revision,observerCount=observer.packets.length;hitch(game,p,1,'root',null);
    check(game.coupling.snapshot().revision===revision&&game.coupling.snapshot().links.length===1,'duplicate sequence applied changed payload');check(ack(p).ack.accepted&&ack(p).ack.processed===1,'duplicate accepted result was not memoized');check(observer.packets.length===observerCount,'duplicate re-broadcast topology');
    hitch(game,p,2,'a','missing');check(ack(p).ack.accepted===false&&ack(p).ack.processed===2,'rejection did not consume ordered sequence');
    hitch(game,p,4,'a','b');check(p.processedCouplingSequence===2,'gap following rejection consumed state');
    hitch(game,p,3,'a','b');check(ack(p).ack.accepted&&p.processedCouplingSequence===3,'next contiguous request after rejection failed');
    hitch(game,p,2,'a','b');check(ack(p).ack.accepted===false&&ack(p).ack.processed===3,'duplicate rejected result changed or watermark regressed');
    const nonce=p.inventoryConnection;game.onMessage(p,{t:'hi',nativeInventory:true,inventoryAck:1,couplingAck:1});check(p.inventoryConnection===nonce&&p.processedCouplingSequence===3,'duplicate hello reset namespace');
  });
  scenario('actual memo bounded to 32 and expired duplicate cannot reapply',()=>{
    const{p}=reset(game);hitch(game,p,1);for(let s=2;s<=36;s++)hitch(game,p,s,'root','missing');
    check(p.couplingResults.size===32,'result memo grew beyond 32');check(!p.couplingResults.has(1),'old result was not evicted');const revision=game.coupling.snapshot().revision;
    hitch(game,p,1,'root',null);check(game.coupling.snapshot().revision===revision&&game.coupling.snapshot().links.length===1,'evicted duplicate reapplied');check(ack(p).ack.processed===36&&ack(p).ack.accepted===false,'expired duplicate claimed retained result');
  });
  scenario('actual native unnegotiated inventory cannot bypass ACK authority',()=>{
    const{p}=reset(game,'inventory-only');check(!p.couplingAckEnabled,'unrequested capability enabled');hitch(game,p,1);check(game.coupling.snapshot().revision===0,'inventory-only peer used legacy raw hitch');
    const fresh=peer(game);check(fresh.inventoryConnection!==p.inventoryConnection,'new peer shared nonce');
  });
  scenario('actual handlers reject foreign/dead/missing/occupied mission targets',()=>{
    for(const[label,mutate]of[
      ['dead',f=>{f.p.player.health=0;}],['foreign-root',f=>{f.root.missionOwner={};}],['foreign-target',f=>{f.a.missionOwner={};}],
      ['missing',f=>game.vehicles.delete('a')],['passenger',f=>{const other=peer(game);other.state={passenger:true,vehicle:'a',x:100,y:95,z:20};}],
    ]){const f=reset(game);mutate(f);hitch(game,f.p,1);check(ack(f.p)?.ack.accepted===false,`${label} was not explicitly rejected`);check(f.p.processedCouplingSequence===1,`${label} did not consume request`);check(game.coupling.snapshot().links.length===0,`${label} attached`);}
  });
  scenario('actual chain, third link and mixed tow branch boundaries',()=>{
    const{p}=reset(game);hitch(game,p,1);hitch(game,p,2,'a','b');check(game.coupling.snapshot().links.length===2,'actual second chain rejected');hitch(game,p,3,'b','c');check(!ack(p).ack.accepted&&game.coupling.snapshot().links.length===2,'actual third link accepted');
    const f=reset(game);f.root.row[2]='8003.0';f.root.row[16]=2500;drive(game,f.p,f.root);f.a.row[2]='8001.0';f.a.row[4]=94.95;f.b.row[4]=89.95;
    hitch(game,f.p,1,'root','a','tow');check(ack(f.p).ack.accepted,'actual tow setup rejected');hitch(game,f.p,2,'a','b');check(!ack(f.p).ack.accepted&&game.coupling.snapshot().links.length===1,'actual backend emitted mixed chain');
  });
  scenario('actual claimed vmove only owner; unclaimed remains legacy-compatible',()=>{
    const{p,a}=reset(game);const other=peer(game);hitch(game,p,1);const original=a.row[3];move(game,other,'a',{x:original+1});check(a.row[3]===original,'foreign vmove moved claimed trailer');
    move(game,p,'a',{x:original+1});check(a.row[3]===original+1,'owner vmove did not move claimed trailer');
    const row=game.vehicles.get('c').row;move(game,other,'c',{x:102});check(row[3]===102,'unclaimed nearby legacy move blocked');
    move(game,p,'a',{x:9000});check(a.row[3]===original+1,'bounds check bypassed for owner');
    move(game,p,'a',{hp:500,w:1500,p:.2,r:-.3});check(a.row[9]===500&&a.row[16]===1500&&a.row[7]===.2&&a.row[8]===-.3,'working/angle/health fields lost');
    move(game,p,'a',{hp:1000});check(a.row[9]===500,'vmove healed target');
  });
  scenario('actual owned/mission pose and parked working values survive optional omission',()=>{
    for(const owner of['owned','mission']){
      const{p,root}=reset(game);root.row[16]=1250;
      if(owner==='owned'){
        root.owner=p.player;root.slot=0;root.lastGarageSave=now;
        p.player.garage[0]={position:root.row.slice(3,7),health:1000,damage:'',pitch:0,roll:0,work:1250};
      }else root.missionOwner=p.player;
      me(game,p,{w:2500,pitch:.12,roll:-.23});check(root.row[16]===2500&&root.row[7]===.12&&root.row[8]===-.23,`${owner} driving work/pose lost`);
      me(game,p,{w:undefined,pitch:.2,roll:-.3});check(root.row[16]===2500,`${owner} omitted driving work reset state`);
      me(game,p,{w:-25});check(root.row[16]===0,`${owner} work lower bound not enforced`);
      me(game,p,{w:9999});check(root.row[16]===2500,`${owner} work upper bound not enforced`);
      me(game,p,{walking:true,driving:false,parked:{x:101,y:100,z:20,heading:.7,pitch:.08,roll:.09,w:777}});
      check(root.row[16]===777&&root.row[3]===101&&root.row[6]===.7,`${owner} parked work/pose lost`);
      if(owner==='owned')check(p.player.garage[0].work===777,'owned parked work not persisted in garage');
    }
  });
  scenario('actual ACK detach cooldown rejects only the last target then accepts expiry',()=>{
    const{p,b}=reset(game);b.row[4]=95;hitch(game,p,1);hitch(game,p,2,'root',null);hitch(game,p,3);
    check(ack(p).ack.accepted===false&&p.processedCouplingSequence===3,'same-target cooldown did not reject/consume ACK');
    hitch(game,p,4,'root','b');check(ack(p).ack.accepted,'different target could not attach during cooldown');hitch(game,p,5,'root',null);
    hitch(game,p,6,'root','b');check(!ack(p).ack.accepted,'new last-target cooldown was bypassed');now+=2500;hitch(game,p,7,'root','b');check(ack(p).ack.accepted,'same-target cooldown did not expire');
  });
  scenario('actual me exit/death/occupant, disconnect and deletion release claims',()=>{
    for(const kind of['exit','death','occupant','disconnect','despawn-root','despawn-target']){
      const{p}=reset(game);const observer=peer(game),legacy=peer(game,'legacy');hitch(game,p,1);hitch(game,p,2,'a','b');check(game.coupling.snapshot().links.length===2,`${kind} setup failed`);observer.packets.length=0;legacy.packets.length=0;
      if(kind==='exit')me(game,p,{driving:false,walking:true,vehicle:null});
      if(kind==='death'){p.player.health=0;me(game,p);}
      if(kind==='occupant')me(game,observer,{walking:false,passenger:true,vehicle:'a',x:100,y:95,z:20});
      if(kind==='disconnect')game.remove(p);
      if(kind==='despawn-root')check(game.deleteVehicle('root'),'root delete failed');
      if(kind==='despawn-target')check(game.deleteVehicle('a'),'target delete failed');
      check(game.coupling.snapshot().links.length===0,`${kind} retained topology`);check(game.coupling.canMove(observer,'a')&&game.coupling.canMove(observer,'b'),`${kind} retained claim`);
      check(observer.packets.some(m=>m.t==='couplings'&&m.state.links.length===0),`${kind} did not publish empty topology`);
      equal(legacy.packets.filter(m=>m.t==='unhitch').map(m=>m.v).sort(),['a','b'],`${kind} did not release both legacy physical joints`);
    }
  });
  scenario('actual Peer.close path releases couplings without opening a listener',()=>{
    reset(game);for(const p of [...game.peers])game.remove(p);
    class Socket extends EventEmitter{constructor(){super();this.writable=true;this.writableLength=0;this.output=[];}write(bytes){this.output.push(Buffer.from(bytes));return true;}end(){this.ended=true;}destroy(){this.destroyed=true;}}
    const socket=new Socket(),req={url:'/api/world/live',headers:{host:'localhost:12345',upgrade:'websocket','sec-websocket-key':Buffer.alloc(16,7).toString('base64')},socket:{remoteAddress:'127.0.0.1'}};
    game.upgrade(req,socket,Buffer.alloc(0));const p=[...game.peers][0];check(p&&typeof p.close==='function','real Peer was not constructed');
    game.onMessage(p,{t:'hi',nativeInventory:true,inventoryAck:1,couplingAck:1});drive(game,p,game.vehicles.get('root'));hitch(game,p,1);check(game.coupling.snapshot().links.length===1,'real Peer setup failed');
    p.close();check(p.closed&&socket.ended&&!game.peers.has(p),'real close did not detach peer');check(game.coupling.snapshot().links.length===0,'real close retained coupling');p.close();check(game.coupling.snapshot().links.length===0,'repeated real close changed topology');
  });
  scenario('legacy browser refresh and rejection roll back its speculative joint',()=>{
    const{p}=reset(game,'legacy');check(!p.inventoryEnabled&&!p.couplingAckEnabled,'browser negotiated native capability');
    game.onMessage(p,{t:'hitch',v:'root',tr:'a',kind:'trailer'});check(game.coupling.snapshot().links.length===1,'legacy hitch rejected');
    const rev=game.coupling.snapshot().revision;now+=4000;game.onMessage(p,{t:'hitch',v:'root',tr:'a',kind:'trailer'});check(game.coupling.snapshot().revision===rev,'legacy 4-second refresh reapplied link');
    game.onMessage(p,{t:'hitch',v:'a',tr:'b',kind:'trailer'});check(game.coupling.snapshot().links.length===2,'legacy second trailer rejected');
    const secondRevision=game.coupling.snapshot().revision;now+=4000;game.onMessage(p,{t:'hitch',v:'a',tr:'b',kind:'trailer'});check(game.coupling.snapshot().revision===secondRevision,'legacy second-link 4-second refresh reapplied link');
    p.packets.length=0;game.onMessage(p,{t:'hitch',v:'b',tr:'c',kind:'trailer'});check(p.packets.some(m=>m.t==='unhitch'&&m.v==='c'),'rejected legacy speculative target was not rolled back');
    game.onMessage(p,{t:'hitch',v:'root',tr:null,kind:'trailer'});check(game.coupling.snapshot().links.length===0,'legacy detach retained chain');
    check(!p.packets.some(m=>m.t==='couplings'),'unnegotiated browser received native topology packets');
  });
  scenario('absent optional metadata and module preserve legacy backend startup',()=>{
    const{game:old}=fixture('without-metadata',false),p=peer(old);check(!old.coupling,'missing metadata enabled authority');check(!p.packets.find(m=>m.t==='hello').couplingAck,'missing catalog advertised ACK');check(!p.packets.some(m=>m.t==='couplings'),'missing catalog sent baseline');
    hitch(old,p,1);check(p.processedCouplingSequence===undefined,'unsupported hitch consumed sequence');
    const legacy=peer(old,'legacy');old.onMessage(legacy,{t:'me',walking:true,x:100,y:100,z:20,health:63});check(legacy.player.health===63,'legacy pose no longer works without coupling module');
  });
  scenario('ephemeral topology and ACK namespace never enter account saves',()=>{
    game.flushSync();const saved=fs.readFileSync(path.join(main.local,'players.json'),'utf8');
    for(const key of['couplingResults','processedCouplingSequence','inventoryConnection','"links"'])check(!saved.includes(key),`ephemeral ${key} persisted`);
  });
}finally{
  Date.now=originalNow;
  for(const game of games){clearInterval(game.tick);clearInterval(game.projectileTimer);game.flushSync();}
  fs.rmSync(temporary,{recursive:true,force:true});
}
const unchanged=files.every(file=>hash(fs.readFileSync(sourcePaths[file]))===hashes[file]);
if(!unchanged)failures.push({scenario:'provenance',error:'Production sources changed during this run; rerun after the final freeze.'});
const report={passed:failures.length===0,checks,scenarios,failures,sourceHashes:hashes,sourcesUnchanged:unchanged,
  evidence:'Actual copied independent module/backend handlers; synthetic accounts, catalogs and poses; no listener, original assets or retail engine.',
  ...(baselineModule?{baselineModule,note:'Historical module with the current copied backend; this is boundary regression sensitivity, not a complete historical server binary.'}:{}),
  testHash:hash(fs.readFileSync(__filename))};
const output=reportDirectory||path.resolve(__dirname,'local-only/native-physics/tests/coupling-server',baselineModule?'baseline':'current');fs.mkdirSync(output,{recursive:true});
const snapshots=path.join(output,'source-snapshot');fs.mkdirSync(snapshots,{recursive:true});for(const file of files)fs.writeFileSync(path.join(snapshots,file),captured[file]);
fs.writeFileSync(path.join(output,'report.json'),JSON.stringify(report,null,2)+'\n');
console.log(`${report.passed?'PASS':'FAIL'} coupling server: ${checks} checks across ${scenarios.length} actual-module/backend scenarios; source snapshot ${unchanged?'unchanged':'changed'}`);
for(const failure of failures)console.error(`${failure.scenario}: ${failure.error}`);
process.exitCode=report.passed?0:1;
