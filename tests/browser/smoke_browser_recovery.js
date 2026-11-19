#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Authored coordinator + actual backend, virtual filesystem/clock/transport only.
// No browser, listener, socket, account/save file, or original game data is used.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const assert=require('node:assert/strict'),crypto=require('node:crypto');
const {coordinator,install,TOKEN}=require('../../browser_recovery');
const {EventEmitter}=require('node:events');
const hook=require('../../browser_recovery_hook');
const ROOT=require('node:path').resolve(__dirname, '../..'),OUT=path.join(ROOT,'local-only/research/browser-recovery-116');
const args=process.argv.slice(2);
assert(args.length===0||(args.length===2&&args[0]==='--historical'),'Usage: node tests/browser/smoke_browser_recovery.js [--historical /source/checkout]');
let checks=0;const scenarios=[];
const check=(v,label)=>{checks++;assert(v,label);};
const canonical=v=>v===undefined?v:JSON.parse(JSON.stringify(v));
const same=(v,w,label)=>{checks++;assert.deepEqual(canonical(v),canonical(w),label);};
async function scenario(name,body){const start=checks;await body();scenarios.push({name,checks:checks-start});}
const scope=(revision=0,connection='a'.repeat(24))=>({connection,revision});
const hello=(placement=scope())=>({t:'hello',browserRecovery:1,browserPlacement:placement,life:[73,11]});
const tp=(placement=scope())=>({t:'tp',x:100,y:100,z:20,h:90,g:1,browserPlacement:placement});
const all=()=>({t:'all',protocol:38,number:1,id:'1',cars:[],vehicles:[]});
const foot=()=>({t:'me',walking:true,health:73,armour:11,x:100,y:100,z:20,heading:Math.PI/2,air:false});
function client(){let active=true,now=1000;const sent=[],notes=[];
  const c=coordinator({send:v=>sent.push(v),status:v=>notes.push(v),isCurrent:()=>active,clock:()=>now});
  return{c,sent,notes,advance:ms=>now+=ms,replace:()=>{active=false;},
    begin(){same(c.outgoing({t:'hi'},true),{t:'hi',browserRecovery:1},'Capability negotiation');
      c.receive(hello(),()=>{});c.receive(all(),()=>{});},
    apply(packet=tp()){c.receive(packet,()=>{check(c.didApplyTeleport({x:packet.x,y:packet.y,z:packet.z,
      heading:packet.h,ground:packet.g===1}),'Matching normal callback completion');});}};}
function fixture(){
  const fixtureFile=path.join(ROOT,'tests/network/smoke_selfhost_position_resume.js');
  const source=fs.readFileSync(fixtureFile,'utf8');
  const prefix=source.slice(0,source.indexOf('\nasync function main(){'));
  const sandbox={require,module:{exports:{}},__dirname:path.dirname(fixtureFile),process:{argv:[]},console,Buffer,URL,URLSearchParams,
    TextEncoder,TextDecoder,structuredClone};
  vm.runInNewContext(prefix+'\nglobalThis.fixture={backend,foot,storage,floor};',sandbox,{filename:'authored-backend-fixture.js'});
  return sandbox.fixture;
}
async function main(){
  if(args.length){
    const sourceRoot=path.resolve(args[1]),{backend,foot:bf}=fixture();
    const h=backend(undefined,undefined,sourceRoot),account=await h.auth(),a=h.connect(account);
    a.send(bf(a,125,140));a.close();
    const b=h.connect(account,{hi:{t:'hi',browserRecovery:1}});
    check(b.hello().browserRecovery!==1,'Historical server unexpectedly supports the new capability');
    b.send({t:'me',driving:true,car:'400',x:126,y:140,z:20,heading:0,health:900,life:100});
    check(b.peer.state?.driving===true&&!b.peer.state.vehicle,'Historical ID-less cached driver divergence must reproduce');
    check(!h.game.vehicleClaims.size,'Historical divergence is not regained registry authority');
    const report={expectedHistoricalFailure:true,checks,sourceRoot,backendSHA256:crypto.createHash('sha256')
      .update(fs.readFileSync(path.join(sourceRoot,'selfhost_backend.js'))).digest('hex'),
      observation:'Unnegotiated historical server accepts the cached ID-less driver as genuine freeplay. The old browser demotion/serializer witness is separately private.'};
    h.stop();fs.mkdirSync(OUT,{recursive:true});fs.writeFileSync(path.join(OUT,'historical-report.json'),JSON.stringify(report,null,2)+'\n');
    console.log('Historical browser recovery negative: reproduced',checks,'checks');return;
  }
  await scenario('normal callback witness, real foot report and explicit server ACK are separate barriers',()=>{
    const h=client();h.begin();
    same(h.c.outgoing({...foot(),driving:true,walking:false},true),null,'Cached driver withheld');
    same(h.sent.length,1,'Only genuine report requests normal TP');
    check(!h.c.didApplyTeleport({x:100,y:100,z:20,heading:90,ground:true}),'Outside-delivery witness rejected');
    h.apply();same(h.c.phase,'foot','Witness alone cannot unlock');
    same(h.c.outgoing({t:'exit',v:'cached-car'},true),null,'Old role exit blocked');
    const report=h.c.outgoing(foot(),true);same(report.browserPlacement,scope(),'Real foot tagged');
    same(h.c.phase,'admitting','Report delivery alone cannot unlock');
    h.c.receive({t:'browserPlacement',accepted:true,browserPlacement:scope(0,'b'.repeat(24))},()=>{});
    same(h.c.phase,'admitting','Foreign ACK rejected');
    h.c.receive({t:'browserPlacement',accepted:true,browserPlacement:scope()},()=>{});
    same(h.c.phase,'ready','Server admission unlocks');
    const free={t:'me',driving:true,car:'420',x:101,y:102,z:20,heading:0};
    same(h.c.outgoing(free,true),{...free,browserPlacement:scope()},'Genuine ID-less freeplay remains legal after admission');
  });
  await scenario('inactive/dead/refused/stale/reentrant callbacks fail closed without synthetic reports',()=>{
    const h=client();h.begin();h.c.receive(tp(),()=>{});
    same(h.c.phase,'pending','Ignored normal TP remains pending');
    same(h.c.outgoing(foot(),true),null,'No invented application');same(h.sent.length,1,'Real report triggers one retry');
    h.c.outgoing(foot(),true);same(h.sent.length,1,'Retry bounded to 500ms');
    h.advance(500);h.c.outgoing(foot(),true);same(h.sent.length,2,'No timer is needed for later genuine report');
    h.c.receive(tp(),()=>{check(!h.c.didApplyTeleport({x:101,y:100,z:20,heading:90,ground:true}),'Different callback cannot witness');});
    same(h.c.phase,'pending','Unrelated callback did not apply');
    h.apply();h.c.outgoing(foot(),true);
    h.c.receive({t:'browserPlacement',accepted:false,browserPlacement:scope()},()=>{});
    same(h.c.phase,'failed','Explicit rejection fails closed');same(h.c.outgoing(foot(),true),null,'Refused cannot heal or move');
    const dead=client();dead.c.outgoing({t:'hi'},true);dead.c.receive({...hello(),life:[0,0]},()=>{});
    same(dead.c.phase,'failed','Server death is not revived');same(dead.c.outgoing({...foot(),health:100},true),null,'Client cannot heal pending dead');
    const reentrant=client();reentrant.begin();reentrant.c.receive(tp(),()=>{reentrant.c.close();
      check(!reentrant.c.didApplyTeleport({x:100,y:100,z:20,heading:90,ground:true}),'Disconnected callback cannot apply');});
    same(reentrant.c.phase,'closed','Callback did not reopen closed session');
    const replaced=client();replaced.begin();replaced.replace();replaced.apply();
    same(replaced.c.phase,'pending','Stale transport cannot commit');
  });
  await scenario('same-peer revision fences, duplicate hello, wrong nonce and baseline ordering',()=>{
    const h=client();h.begin();h.apply();h.c.outgoing(foot(),true);
    h.c.receive({t:'browserPlacement',accepted:true,browserPlacement:scope()},()=>{});
    h.apply(tp(scope(1)));same(h.c.phase,'foot','New TP revokes readiness');
    h.c.receive(hello(),()=>{});same(h.c.placement,scope(1),'Duplicate hello cannot rewind');
    h.c.receive(tp(),()=>{throw Error('Stale TP delivered');});same(h.c.placement,scope(1),'Old TP ignored');
    h.c.receive(tp(scope(2,'b'.repeat(24))),()=>{throw Error('Foreign TP delivered');});
    same(h.c.placement,scope(1),'Foreign TP ignored');
    same(h.c.outgoing({t:'shot'},true),null,'Pending shot not replayed');
    h.c.receive({...hello(),browserPlacement:scope(0,'b'.repeat(24))},()=>{});
    same(h.c.phase,'failed','Same socket namespace mutation fails closed');
    for(const bad of [{...scope(),revision:true},{...scope(),revision:NaN},{...scope(),connection:''},null]){
      const b=client();b.c.outgoing({t:'hi'},true);b.c.receive(hello(bad),()=>{});same(b.c.phase,'failed','Malformed hello rejected');
    }
    const legacy=client();same(legacy.c.outgoing({t:'hi'},false),{t:'hi'},'Absent hook cannot negotiate');
    same(legacy.c.outgoing(foot(),false),foot(),'Unhooked legacy remains usable');
    const old=client();old.c.outgoing({t:'hi'},true);old.c.receive({t:'hello'},()=>{});
    same(old.c.outgoing(foot(),true),foot(),'Unadvertising server remains legacy');
    const bool=client();bool.c.outgoing({t:'hi'},true);bool.c.receive({...hello(),browserRecovery:true},()=>{});
    same(bool.c.phase,'failed','Boolean capability is not numeric negotiation');
    const early=client();early.c.outgoing({t:'hi'},true);early.c.receive(hello(),()=>{});
    early.c.receive({t:'all',protocol:38,number:true,id:'true',cars:[],vehicles:[]},()=>{});early.apply();
    same(early.c.phase,'pending','Malformed baseline cannot unlock witnessed placement');
    same(early.c.outgoing(foot(),true),null,'No report until a valid baseline');
    const nested=client();nested.begin();nested.c.receive(tp(),()=>nested.apply(tp(scope(1))));
    same(nested.c.placement,scope(1),'Reentrant newer TP scope wins');same(nested.c.phase,'foot','Outer callback cannot rewind newer witness');

  });
  await scenario('independently authored callback instrumentation sensitivity and input/identity preservation',()=>{
    const original='globalThis.owner={onTeleport:e=>{if(!active||dead)return;driver=false;pose=[e.x,e.y,e.z];health=health}};';
    const body=original.slice(original.indexOf(hook.MARKER),original.lastIndexOf('}'));
    const identity={marker:hook.MARKER,length:body.length,sha256:crypto.createHash('sha256').update(body).digest('hex')};
    const modified=hook.instrument(original,[{...identity,kind:'teleport'}]),h=client();h.begin();
    const sandbox={active:true,dead:false,driver:true,pose:null,health:73,held:true,
      ZGTABrowserRecovery:{registerHook:v=>same(v,TOKEN,'Pinned adapter registration'),didApplyTeleport:v=>h.c.didApplyTeleport(v)}};
    vm.runInNewContext(modified,sandbox);h.c.receive(tp(),()=>sandbox.owner.onTeleport({x:100,y:100,z:20,heading:90,ground:true}));
    same(h.c.phase,'foot','Authored callback reached end');same(sandbox.pose,[100,100,20],'Normal callback applied position');
    check(!sandbox.driver&&sandbox.health===73&&sandbox.held===true,'Adapter changed no health/held input/identity');
    sandbox.dead=true;h.c.receive(tp(scope(1)),()=>sandbox.owner.onTeleport({x:100,y:100,z:20,heading:90,ground:true}));
    same(h.c.phase,'pending','Early return does not fabricate witness');
    for(const source of [original.replace('driver=false','driver=true'),original+original,'', 'x'.repeat(32*1024*1024+1)]){
      checks++;assert.throws(()=>hook.instrument(source,[{...identity,kind:'teleport'}]),'Unsupported source must fail explicitly');}
  });
  await scenario('actual full backend browser admission, restart/checkpoint, native prerequisites and legacy freeplay',async()=>{
    const {backend,foot:backendFoot}=fixture(),h=backend(),account=await h.auth();
    const native=h.connect(account);native.send(backendFoot(native,125,140));native.close();
    const b=h.connect(account,{hi:{t:'hi',browserRecovery:1}});
    check(b.hello().browserRecovery===1&&!b.hello().positionAck&&!b.peer.inventoryAckEnabled,'Separate namespace preserves native prerequisites');
    const env=b.hello().browserPlacement,initial=b.packets.find(p=>p.t==='tp');
    same([initial.x,initial.y,initial.z],[125,140,20],'Server selected admitted foot checkpoint');
    const inv=structuredClone(b.player.inventory),health=b.player.health,carCount=h.game.vehicles.size;
    b.send({t:'me',driving:true,car:'400',x:300,y:300,z:20,heading:0,browserPlacement:env});
    check(!b.peer.state,'Cached driver cannot cross pending barrier');
    b.send({t:'me',walking:true,health:health,x:125,y:140,z:20,heading:0,browserPlacement:{...env,revision:true}});
    check(!b.peer.state,'Bool revision refused');
    b.send({...backendFoot(b,200,200),browserPlacement:env});check(!b.peer.state,'Far-away fabricated arrival refused');
    b.send({...backendFoot(b,125,140),browserPlacement:env});
    check(b.peer.state?.walking&&b.packets.some(p=>p.t==='browserPlacement'&&p.accepted===true),'Actual server ACK follows admitted foot');
    same(b.player.inventory,inv,'Recovery consumed no ammunition');same(b.player.health,health,'Recovery healed no health');
    same(h.game.vehicles.size,carCount,'No vehicle was created or claimed');
    b.send({t:'me',driving:true,car:'400',x:126,y:140,z:20,heading:0,health:100,browserPlacement:env});
    check(b.peer.state?.driving&&!b.peer.state.vehicle,'Genuine ID-less freeplay remains admitted');
    b.send({...backendFoot(b,125,140),browserPlacement:env});b.player.homes.push('authored-home');
    h.game.action(b.player,'home.visit',{home:'authored-home'});
    const next=b.packets.filter(p=>p.t==='tp').at(-1);same(next.browserPlacement.revision,1,'Normal TP advances browser fence');
    check(!b.peer.state,'Normal TP revokes previous role');
    b.send({...backendFoot(b,125,140),say:'/name SHOULD_NOT_EXECUTE',browserPlacement:env});
    check(!b.peer.state&&!b.player.name.includes('SHOULD_NOT'),'Old epoch cannot execute bundled command');
    b.send({...backendFoot(b,110,110),browserPlacement:next.browserPlacement});
    check(b.peer.state?.walking,'New revision normal foot accepted');
    b.send({t:'hi',browserRecovery:1});same(b.hello().browserPlacement,next.browserPlacement,'Duplicate hi retains latest revision');
    const nonce=next.browserPlacement.connection;b.close();
    const c=h.connect(account,{hi:{t:'hi',browserRecovery:1}});
    check(c.hello().browserPlacement.connection!==nonce,'Reconnect creates fresh namespace');
    check(!c.peer.state,'Reconnect does not restore old role');
    c.send({...backendFoot(c,110,110),browserPlacement:next.browserPlacement});check(!c.peer.state,'Old nonce cannot report');
    h.game.flushSync();c.close();const memory=h.memory;h.stop();
    const restarted=backend(memory),again=await restarted.auth(account.cookie);
    const d=restarted.connect(again,{hi:{t:'hi',browserRecovery:1}});
    same([d.hello().spot[0],d.hello().spot[1]],[110,110],'Restart preserves server foot anchor');
    d.close();again.player.health=0;const dead=restarted.connect(again,{hi:{t:'hi',browserRecovery:1}});
    check(!dead.packets.some(p=>p.t==='tp'),'Dead reconnect receives no invented TP');
    dead.send({...backendFoot(dead,110,110),health:100,browserPlacement:dead.hello().browserPlacement});
    same(again.player.health,0,'Dead reconnect cannot heal through me');check(!dead.peer.state,'Dead reconnect remains unadmitted');
    dead.close();again.player.health=100;
    const mixed=restarted.connect(again,{hi:{t:'hi',nativeInventory:true,browserRecovery:1,positionAck:1}});
    check(!mixed.peer.browserRecoveryEnabled&&!mixed.peer.positionAckEnabled,'Mixed request cannot bypass native prerequisite');mixed.close();
    const legacy=restarted.connect(again,{hi:{t:'hi'}});
    check(!legacy.hello().browserRecovery,'Legacy stays unnegotiated');
    legacy.send({t:'me',driving:true,car:'400',x:100,y:100,z:20,heading:0,health:100});
    check(legacy.peer.state?.driving,'Existing legacy freeplay preserved');
    check(!restarted.errors.length,restarted.errors.join('\n'));restarted.stop();
  });
  await scenario('actual hello/TP/baseline order supports active cleanup and inactive first-join genuine retry',async()=>{
    const {backend,storage,floor}=fixture();
    for(const initiallyActive of [false,true]){
      const memory=storage();
      memory.json('local-only/site/game/world/index.json',{water:[],detail:{size:375,grid:16,origin:-3000,cells:[{cell:59},{cell:136}]},inside:{cells:[]}});
      const tile=floor(12.5); // SCL2 vertices are global GTA coordinates, not cell-local.
      for(let i=0;i<4;i++){const offset=16+i*12;tile.writeFloatLE(tile.readFloatLE(offset)+1125,offset);
        tile.writeFloatLE(tile.readFloatLE(offset+4)-1875,offset+4);}
      memory.writeFileSync('/fixture/local-only/site/game/world/c59.col.bin',tile);
      const h=backend(memory),account=await h.auth(),a=h.connect(account,{hi:{t:'hi',browserRecovery:1}});
      const packets=a.packets,helloAt=packets.findIndex(p=>p.t==='hello'),tpAt=packets.findIndex(p=>p.t==='tp'),allAt=packets.findIndex(p=>p.t==='all');
      check(helloAt>=0&&tpAt>helloAt&&allAt>tpAt,'Actual server releases normal old controller before reconciling vehicle baseline');
      let consumed=0,now=1000,active=initiallyActive,callbacks=0,appliedCallbacks=0;
      const c=coordinator({clock:()=>now,isCurrent:()=>!a.peer.closed,send:p=>{a.send(p);drain();}});
      c.outgoing({t:'hi'},true);
      function drain(){while(consumed<a.packets.length){const p=a.packets[consumed++];c.receive(p,()=>{
        if(p.t==='tp'){callbacks++;if(active){appliedCallbacks++;
          check(c.didApplyTeleport({x:p.x,y:p.y,z:p.z,heading:p.h,ground:p.g===1}),'Only actual normal callback completion witnessed');}}
      });}}
      drain();same(c.phase,'pending','Pre-baseline TP never unlocks position, even if its callback completed');
      same(a.peer.state,null,'Initial sequence fabricated no actor report');
      if(initiallyActive)check(appliedCallbacks===1,'Active old controller really completed cleanup before baseline');
      else check(appliedCallbacks===0,'Inactive initial callback really refused the TP');
      check(!c.actionGrant(),'No HTTP grant before the full handshake');
      active=true;now+=500;
      const real={t:'me',walking:true,driving:false,skin:7,x:1480,y:-1738,z:12.5,heading:0,health:100,armour:0,air:false,move:0};
      same(c.outgoing(real,true),null,'Genuine first foot report requests resend rather than inventing ACK');
      check(callbacks===2&&appliedCallbacks>0,'Normal same-revision TP retried after actual baseline/report');
      const forwarded=c.outgoing(real,true);check(!!forwarded,'Subsequent genuine foot report carries applied envelope');a.send(forwarded);drain();
      same(c.phase,'ready','Actual server accepted ordinary new guest foot');
      check(a.peer.state?.walking&&a.peer.state.driving!==true,'No old driver state restored');
      const car={id:'authored-new-entry',row:['authored-new-entry','Authored','400',1481,-1738,12.5,0,0,0,1000,'',null]};h.game.vehicles.set(car.id,car);
      const enter=c.outgoing({t:'enter',v:car.id},true);check(!!enter,'Normal fresh entry may proceed after recovery');a.send(enter);drain();
      check(a.packets.some(p=>p.t==='enter'&&p.v===car.id&&p.ok===true),'Actual server grants only the ordinary fresh request');
      a.send(c.outgoing({t:'me',driving:true,car:'400',vehicle:car.id,x:1481,y:-1738,z:12.5,heading:0,health:1000,life:100},true));drain();
      check(h.game.vehicleClaim(car)?.driving&&a.peer.state.vehicle===car.id,'Ordinary fresh driver keeps real registry identity');
      h.stop();
    }
  });
  await scenario('actual server role revocation, no cached claim and old queued cleanup fences',async()=>{
    const {backend,foot:bf}=fixture(),h=backend(),a=h.connect(await h.auth());a.send(bf(a,125,140));a.close();
    const account=await h.auth(a.cookie),b=h.connect(account,{hi:{t:'hi',browserRecovery:1}}),env=b.hello().browserPlacement;
    b.send({...bf(b,125,140),browserPlacement:env});
    const car={id:'authored-mission',missionOwner:b.player,row:['authored-mission','Authored','400',126,140,20,0,0,0,900,'',null]};
    h.game.vehicles.set(car.id,car);b.send({t:'enter',v:car.id});
    check(h.game.vehicleClaim(car)?.peer===b.peer,'Normal driver reservation');
    b.send({t:'me',driving:true,car:'400',vehicle:car.id,x:126,y:140,z:20,heading:0,health:900,life:100,browserPlacement:env});
    check(h.game.vehicleClaim(car)?.driving,'Normal admitted driver');
    const savedRow=[...car.row];b.close();
    check(!h.game.vehicleClaim(car),'Disconnect drops claim');
    const c=h.connect(account,{hi:{t:'hi',browserRecovery:1}}),next=c.hello().browserPlacement;
    same([c.hello().spot[0],c.hello().spot[1]],[125,140],'Driver reconnect uses foot anchor, not body');
    c.send({t:'enter',v:car.id});check(!h.game.vehicleClaim(car),'Pending reconnect cannot reacquire');
    c.send({t:'exit',v:car.id,parked:{x:200,y:200,z:20,health:0}});
    same(car.row.slice(3,11),savedRow.slice(3,11),'Old cleanup cannot alter parked body/condition');
    c.send({t:'me',driving:true,car:'400',vehicle:car.id,x:126,y:140,z:20,heading:0,health:900,browserPlacement:next});
    check(!c.peer.state&&!h.game.vehicleClaim(car),'Even new nonce cannot certify a cached driver');
    c.send({...bf(c,125,140),browserPlacement:next});
    check(!h.game.vehicleClaim(car)&&c.peer.state.walking,'Foot admission grants no vehicle authority');
    c.send({t:'enter',v:car.id});check(h.game.vehicleClaim(car)?.peer===c.peer,'Only a new ordinary entry grants reservation');
    c.close();h.stop();
  });
  await scenario('actual HTTP action admission rejects captured old generations and peer replacement',async()=>{
    const {backend,foot:bf}=fixture(),h=backend(),account=await h.auth();
    const a=h.connect(account);a.send(bf(a,125,140));a.close();
    const b=h.connect(account,{hi:{t:'hi',browserRecovery:1}}),e0=b.hello().browserPlacement;
    const headers=e=>({'x-zgta-browser-connection':e.connection,'x-zgta-browser-revision':String(e.revision)});
    function post(extra={},body={action:'explore.track',id:null},delayed=false){
      const req=Object.assign(new EventEmitter(),{url:'/api/local/action',method:'POST',
        headers:{host:'127.0.0.1:1',cookie:account.cookie,...extra},socket:{remoteAddress:'127.0.0.1'},destroy(){}});
      const res={setHeader(){},writeHead(code){this.code=code;},end(bytes){this.body=JSON.parse(bytes);}};
      const promise=h.game.http(req,res).then(()=>res);
      const finish=()=>{req.emit('data',Buffer.from(JSON.stringify(body)));req.emit('end');};
      if(!delayed)finish();return{promise,finish};
    }
    same((await post(headers(e0)).promise).code,409,'Tagged pending action rejected');
    same((await post().promise).code,409,'Cookie-only pending mutation rejected');
    b.send({...bf(b,125,140),browserPlacement:e0});
    b.player.trackedDiscovery='authored-marker';
    same((await post(headers(e0)).promise).code,200,'New ready action succeeds');
    same(b.player.trackedDiscovery,null,'Actual action executed once');
    same((await post().promise).code,409,'Negotiated ready peer still requires header');
    for(const invalid of [
      {'x-zgta-browser-connection':e0.connection},
      {'x-zgta-browser-revision':'0'},
      {...headers(e0),'x-zgta-browser-revision':'true'},
      {...headers(e0),'x-zgta-browser-revision':'00'},
      {...headers(e0),'x-zgta-browser-revision':'9007199254740992'},
      {...headers(e0),'x-zgta-browser-revision':['0']},
      headers({...e0,connection:'b'.repeat(24)}),
      {...headers(e0),'x-zgta-inventory-connection':'foreign'},
    ])same((await post(invalid).promise).code,409,'Wrong/malformed HTTP placement rejected');
    const pending=post(headers(e0),undefined,true);
    b.player.homes.push('authored-home');h.game.action(b.player,'home.visit',{home:'authored-home'});
    const e1=b.packets.filter(p=>p.t==='tp').at(-1).browserPlacement;
    pending.finish();same((await pending.promise).code,409,'TP during HTTP body invalidates old action');
    same((await post(headers(e0)).promise).code,409,'Old action rejected while pending');
    b.send({...bf(b,110,110),browserPlacement:e1});
    b.player.trackedDiscovery='keep';same((await post(headers(e0)).promise).code,409,'Captured old POST rejected even after fresh readiness');
    same(b.player.trackedDiscovery,'keep','Old action has no mutation');
    const replacement=post(headers(e1),undefined,true),c=h.connect(account,{hi:{t:'hi',browserRecovery:1}});
    const e2=c.hello().browserPlacement;c.send({...bf(c,110,110),browserPlacement:e2});
    replacement.finish();same((await replacement.promise).code,409,'Duplicate tab/replacement invalidates captured body');
    const closed=post(headers(e2),undefined,true);c.close();closed.finish();
    same((await closed.promise).code,409,'Close during body cannot mutate');
    h.game.flushSync();const memory=h.memory;h.stop();
    const restart=backend(memory),again=await restart.auth(account.cookie);
    const req=Object.assign(new EventEmitter(),{url:'/api/local/action',method:'POST',
      headers:{host:'127.0.0.1:1',cookie:again.cookie,...headers(e2)},socket:{remoteAddress:'127.0.0.1'},destroy(){}});
    const res={setHeader(){},writeHead(code){this.code=code;},end(bytes){this.body=JSON.parse(bytes);}};
    await restart.game.http(req,res);same(res.code,409,'Captured explicitly tagged POST rejected before fresh hello after restart');
    check(!restart.game.peers.size,'Fixture did not invent a fresh peer');restart.stop();
  });
  await scenario('actual authored F6 action producer tags only current grant and never replays stale response',async()=>{
    const source=fs.readFileSync(path.join(ROOT,'local_gameplay.js'),'utf8');
    const start=source.indexOf('  async function perform(action, payload) {'),end=source.indexOf('\n  function toggle(',start);
    check(start>0&&end>start,'Actual F6 action extraction');
    function producer(h){const calls=[],deferred=[];
      const context={busy:false,state:{baseline:true},result:'baseline',error:false,partyDraft:'keep',render(){},renderObjective(){},
        ZGTABrowserRecovery:{captureActionGrant:()=>h.c.actionGrant(),isActionGrantCurrent:g=>h.c.ownsActionGrant(g)},
        fetch:(url,options)=>{calls.push({url,options});return new Promise(resolve=>deferred.push(resolve));}};
      vm.runInNewContext(source.slice(start,end)+'\nglobalThis.performAction=perform;',context);
      return{context,calls,deferred};}
    const h=client();h.begin();const p=producer(h);await p.context.performAction('party.chat',{text:'ignored'});
    same(p.calls.length,0,'Pending F6 does not send');check(!p.context.busy&&p.context.error,'Pending is visible and not stuck busy');
    h.apply();h.c.outgoing(foot(),true);h.c.receive({t:'browserPlacement',accepted:true,browserPlacement:scope()},()=>{});
    const work=p.context.performAction('party.chat',{text:'hello'});
    same(p.calls.length,1,'One user action, one HTTP request');
    same(p.calls[0].options.headers,{'Content-Type':'application/json','X-ZGTA-Browser-Connection':'a'.repeat(24),
      'X-ZGTA-Browser-Revision':'0'},'Actual producer includes captured current fence');
    h.c.close();p.deferred[0]({ok:true,json:async()=>({state:{old:true},message:'obsolete'})});await work;
    same(p.context.state,{baseline:true},'Old completion cannot rewind current UI');
    check(!p.context.busy&&p.calls.length===1,'No action replay; busy released after suppression');
    const fresh=client();fresh.begin();fresh.apply();fresh.c.outgoing(foot(),true);
    fresh.c.receive({t:'browserPlacement',accepted:true,browserPlacement:scope()},()=>{});
    const q=producer(fresh),current=q.context.performAction('party.chat',{text:'ok'});
    q.deferred[0]({ok:true,json:async()=>({state:{current:true},message:'accepted'})});await current;
    same(q.context.state,{current:true},'Normal current action response applied');same(q.context.partyDraft,'','Accepted chat clears current draft');
    const legacy=client(),l=producer(legacy),old=l.context.performAction('party.chat',{text:'legacy'});
    same(l.calls[0].options.headers,{'Content-Type':'application/json'},'Genuine legacy producer remains untagged');
    l.deferred[0]({ok:true,json:async()=>({state:{legacy:true},message:'ok'})});await old;
    same(l.context.state,{legacy:true},'Legacy normal result unchanged');
    const r=client();r.begin();r.apply();r.c.outgoing(foot(),true);
    r.c.receive({t:'browserPlacement',accepted:true,browserPlacement:scope()},()=>{});
    const reentrant=producer(r);reentrant.context.fetch=()=>{r.c.close();return Promise.resolve({ok:true,
      json:async()=>({state:{obsolete:true},message:'obsolete'})});};
    await reentrant.context.performAction('party.chat',{text:'close inside dispatch'});
    same(reentrant.context.state,{baseline:true},'Synchronous reentrant close cannot apply response');
    check(!reentrant.context.busy,'Reentrant close leaves no busy ownership');

  });
  await scenario('actual WebSocket wrapper routes only same-origin live owner and forwards original message object',()=>{
    class Socket{
      static OPEN=1;constructor(url){this.url=url;this.readyState=1;this.sent=[];this.listeners={};}
      addEventListener(name,fn){(this.listeners[name]||=[]).push(fn);}
      send(data){this.sent.push(JSON.parse(data));}
      emit(value){const event={data:JSON.stringify(value),sentinel:7};
        for(const fn of this.listeners.message||[])fn(event);return event;}
    }
    const root={WebSocket:Socket,location:{href:'http://localhost:1/',host:'localhost:1',protocol:'http:'}};install(root);
    root.ZGTABrowserRecovery.registerHook(TOKEN);
    const other=new root.WebSocket('ws://elsewhere:1/api/world/live');other.send(JSON.stringify({t:'hi'}));
    same(other.sent,[{t:'hi'}],'Foreign socket untouched');
    const a=new root.WebSocket('ws://localhost:1/api/world/live');let seen;
    a.onmessage=e=>{seen=e;const p=JSON.parse(e.data);if(p.t==='tp'){
      a.send(JSON.stringify({t:'exit',v:'old'}));root.ZGTABrowserRecovery.didApplyTeleport({x:p.x,y:p.y,z:p.z,heading:p.h,ground:p.g===1});}};
    a.send(JSON.stringify({t:'hi'}));same(a.sent.at(-1),{t:'hi',browserRecovery:1},'Actual wrapper decorates hi');
    a.emit(hello());a.emit(all());const event=a.emit(tp());check(seen===event,'Original MessageEvent identity retained');
    check(!a.sent.some(p=>p.t==='exit'),'Normal callback cannot leak obsolete park/exit write');
    a.send(JSON.stringify(foot()));same(a.sent.at(-1).browserPlacement,scope(),'Actual send stamps applied foot');
    const b=new root.WebSocket('ws://localhost:1/api/world/live');a.send(JSON.stringify({t:'me',driving:true}));
    check(!a.sent.some(p=>p.driving),'Replaced wrapper cannot replay old role');
    b.send(JSON.stringify({t:'hi'}));check(b.sent.at(-1).browserRecovery===1,'Replacement uses normal game transport');
  });
  await scenario('actual serve owner integration is bounded, ordered, no-store and retains access gates',()=>{
    const source=fs.readFileSync(path.join(ROOT,'serve_local.js'),'utf8');
    const begin=source.indexOf('function serve(req, res) {'),end=source.indexOf('\nconst server =',begin);
    check(begin>0&&end>begin,'Actual serve extraction');
    const main='globalThis.owner={onTeleport:e=>{globalThis.last=e}};';
    const callback=main.slice(main.indexOf(hook.MARKER),main.lastIndexOf('}'));
    const identity={marker:hook.MARKER,length:callback.length,sha256:crypto.createHash('sha256').update(callback).digest('hex')};
    const files=new Map([['/fixture/site/index.html','<html><head><script async src="/_next/static/chunks/9737.abcd.js"></script></head><body>Authored</body></html>'],
      ['/fixture/site/_next/static/chunks/9737.abcd.js',main],['/fixture/browser_recovery.js','independent adapter bytes']]);
    const context={path,Buffer,URL,SELFHOST:true,ROOT:'/fixture/site',LOCAL_ONLY:'/fixture',__dirname:'/fixture',
      PUBLIC_ORIGIN:'http://localhost:1',allowedHosts:new Set(['localhost:1']),
      preparedResources:{matches:()=>false},stockNative:{matches:()=>false},nativeRadio:null,
      browserTaskPolicy:{matches:()=>false},
      localGame:{requiresJoinCode:false,authorized:()=>false,ensurePlayer(){}},
      MIME:{'.html':'text/html','.js':'text/javascript'},SELFHOST_TIPS_SCRIPT:'',COMMUNITY_SCRIPT:'',GAMEPLAY_SCRIPT:'',
      process:{env:{}},console,fs:{readFileSync(file){check(files.has(file),'Only selected authored file is read');return files.get(file);},
        stat(file,done){const value=files.get(file);done(value===undefined?Error('ENOENT'):null,{isFile:()=>true,size:Buffer.byteLength(value||'')});},
        writeFileSync(){throw Error('Owner archive mutation forbidden');}},
      browserRecoveryHook:{instrument:value=>hook.instrument(value,[{...identity,kind:'teleport'}])}};
    const security=source.slice(source.indexOf('function securityHeaders(res) {'),source.indexOf('\nfunction proxyHeaders('));
    vm.runInNewContext(security+'\n'+source.slice(begin,end)+'\nglobalThis.request=serve;',context);
    function request(url,headers={},method='GET'){
      const res={statusCode:200,headers:{},setHeader(k,v){this.headers[k]=v;},writeHead(c,h){this.statusCode=c;Object.assign(this.headers,h);},end(v){this.body=v;}};
      context.request({url,method,headers:{host:'localhost:1',...headers}},res);return res;
    }
    const page=request('/');same(page.statusCode,200,'Normal page served');
    check(page.body.toString().indexOf('/local-browser-recovery.js')<page.body.toString().indexOf('<script async'),'Adapter executes before owner async scripts');
    const script=request('/local-browser-recovery.js');same(script.headers['Cache-Control'],'no-store','Adapter cannot remain stale');
    const target='/_next/static/chunks/9737.abcd.js',result=request(target);
    same(result.statusCode,200,'Verified callback is transformed');same(result.headers['Cache-Control'],'no-store','Transformed owner response is no-store');
    check(result.body.toString().includes('didApplyTeleport(e)'),'Actual serve uses the witness transformation');
    same(files.get('/fixture/site'+target),main,'Owner archive remains unchanged');
    same(request(target,{},'HEAD').body,undefined,'HEAD does not leak a body');
    files.set('/fixture/site'+target,main.replace('last=e','last=null'));
    const mismatch=request(target);same(mismatch.statusCode,503,'Mismatched callback does not negotiate unsafe recovery');
    check(mismatch.body.includes('differs from the verified archive'),'Useful source mismatch status');
    same(request('/local-browser-recovery.js',{host:'foreign:1'}).statusCode,421,'Adapter retains Host gate');
    same(request('/local-browser-recovery.js',{origin:'http://foreign:1'}).statusCode,403,'Adapter retains Origin gate');
    context.localGame.requiresJoinCode=true;
    same(request('/local-browser-recovery.js').statusCode,401,'Adapter retains join gate');
    same(request(target).statusCode,401,'Owner transformation retains join gate');
  });
  await scenario('ordinary pointer-lock loss is limited to previously established active game owner',()=>{
    class Socket{
      static OPEN=1;constructor(){this.readyState=1;this.sent=[];this.listeners={};}
      addEventListener(n,f){(this.listeners[n]||=[]).push(f);}
      send(data){this.sent.push(JSON.parse(data));}
      emit(v){for(const f of this.listeners.message||[])f({data:JSON.stringify(v)});}
      closeEvent(){this.readyState=3;for(const f of this.listeners.close||[])f({});}
    }
    function owner(){let exits=0;const game={tagName:'CANVAS'},foreign={tagName:'CANVAS'};
      const doc={pointerLockElement:game,getElementById:()=>({}),exitPointerLock(){exits++;this.pointerLockElement=null;}};
      const root={document:doc,WebSocket:Socket,location:{href:'http://localhost:1/',host:'localhost:1',protocol:'http:'},
        dispatchEvent(){throw Error('Synthetic input is forbidden');}};install(root);root.ZGTABrowserRecovery.registerHook(TOKEN);
      function open(){const s=new root.WebSocket('ws://localhost:1/api/world/live');
        s.onmessage=e=>{const p=JSON.parse(e.data);if(p.t==='tp')root.ZGTABrowserRecovery.didApplyTeleport({x:p.x,y:p.y,z:p.z,heading:p.h,ground:p.g===1});};
        s.send(JSON.stringify({t:'hi'}));return s;}
      function admit(s,revision=0,paused=false){s.emit(hello(scope(revision)));s.emit(all());s.emit(tp(scope(revision)));
        s.send(JSON.stringify({...foot(),paused}));s.emit({t:'browserPlacement',accepted:true,browserPlacement:scope(revision)});}
      return{root,doc,game,foreign,open,admit,exits:()=>exits};}
    const first=owner(),initial=first.open();initial.closeEvent();same(first.exits(),0,'Fresh unestablished join never pauses');
    const normal=owner(),a=normal.open();normal.admit(a);a.emit(tp(scope(1)));
    same(normal.exits(),0,'Ordinary same-peer live TP never exits pointer lock');
    a.closeEvent();same(normal.exits(),1,'Actual established active close uses ordinary pointer-lock exit');
    a.closeEvent();same(normal.exits(),1,'Duplicate close does not pause twice');
    const replaced=owner(),old=replaced.open();replaced.admit(old);const fresh=replaced.open();
    old.closeEvent();same(replaced.exits(),0,'Old close cannot pause replacement');replaced.admit(fresh);
    replaced.doc.pointerLockElement=replaced.foreign;fresh.closeEvent();same(replaced.exits(),0,'Another canvas owns its own pointer lock');
    const paused=owner(),p=paused.open();paused.admit(p,0,true);p.closeEvent();
    same(paused.exits(),0,'Paused report does not claim an unrelated pointer lock');
    const waiting=owner(),w=waiting.open();waiting.admit(w,0,true);
    same(waiting.root.ZGTABrowserRecovery.captureActionGrant(),scope(),'Normal TP/foot may be admitted while paused');
    same(waiting.exits(),0,'Adapter never requests reactivation or synthetic input');
  });
  fs.mkdirSync(OUT,{recursive:true});const names=['browser_recovery.js','browser_recovery_hook.js','browser_task_policy.js','player_placement.js','selfhost_backend.js','serve_local.js','local_gameplay.js','tests/browser/smoke_browser_recovery.js'];
  const report={passed:true,checks,scenarios,scope:'authored virtual transport/full backend; no live browser or sockets',
    hashes:Object.fromEntries(names.map(n=>[n,crypto.createHash('sha256').update(fs.readFileSync(path.join(ROOT,n))).digest('hex')]))};
  fs.writeFileSync(path.join(OUT,'report.json'),JSON.stringify(report,null,2)+'\n');
  console.log(`Browser recovery: PASS ${checks} checks / ${scenarios.length} scenarios (virtual transport only)`);
}
main().catch(e=>{console.error(e);process.exitCode=1;});
