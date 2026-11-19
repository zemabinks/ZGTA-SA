#!/usr/bin/env node
'use strict';
// SPDX-License-Identifier: AGPL-3.0-only
// Authored full-backend fixture. Actual module construction, HTTP auth,
// upgrade/Peer framing, actions, persistence and reload use an in-memory fs,
// fake clock/timers and fake sockets. No listener, OS process or player file.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const assert=require('node:assert/strict'),crypto=require('node:crypto');
const {EventEmitter}=require('node:events');
const ROOT=require('node:path').resolve(__dirname, '../..'),OUT=path.join(ROOT,'local-only/research/position-resume-114');
const args=process.argv.slice(2);
assert(args.length===0||(args.length===2&&args[0]==='--baseline'),'Usage: node tests/network/smoke_selfhost_position_resume.js [--baseline /source/checkout]');
const baseline=args.length?path.resolve(args[1]):null;
const SOURCES=['selfhost_backend.js','optional_discord.js','weapon_inventory.js',
  'world_collision.js','local_projectiles.js','vehicle_coupling.js','player_placement.js'];
const hash=file=>crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex');
let checks=0;const scenarios=[];
function check(value,label){checks++;assert(value,label);}
function same(value,wanted,label){checks++;assert.deepEqual(JSON.parse(JSON.stringify(value)),JSON.parse(JSON.stringify(wanted)),label);}
function near(value,wanted,label){checks++;assert(Number.isFinite(value)&&Math.abs(value-wanted)<1e-9,label);}
async function scenario(name,body){const first=checks;await body();scenarios.push({name,checks:checks-first,passed:true});}
const virtual=file=>path.posix.normalize(String(file));
class MemoryFS {
  constructor(){this.files=new Map();this.fds=new Map();this.nextFD=10;this.writes=0;}
  key(file){if(typeof file==='number')file=this.fds.get(file);const p=virtual(file);
    assert(p.startsWith('/fixture/'),'Backend tried to access outside virtual filesystem');return p;}
  error(code,file){return Object.assign(Error(code+':'+file),{code});}
  readFileSync(file,encoding){const key=this.key(file),bytes=this.files.get(key);
    if(!bytes)throw this.error('ENOENT',key);return encoding?bytes.toString(encoding):Buffer.from(bytes);}
  writeFileSync(file,value){this.files.set(this.key(file),Buffer.isBuffer(value)?Buffer.from(value):Buffer.from(String(value)));this.writes++;}
  mkdirSync(){}
  existsSync(file){return this.files.has(this.key(file));}
  statSync(file){const key=this.key(file),bytes=this.files.get(key);if(!bytes)throw this.error('ENOENT',key);
    return{size:bytes.length,isFile:()=>true,isDirectory:()=>false};}
  openSync(file,flags){const key=this.key(file);assert.equal(flags,'wx');
    if(this.files.has(key))throw this.error('EEXIST',key);this.files.set(key,Buffer.alloc(0));
    const fd=this.nextFD++;this.fds.set(fd,key);return fd;}
  closeSync(fd){this.fds.delete(fd);}
  unlinkSync(file){const key=this.key(file);if(!this.files.delete(key))throw this.error('ENOENT',key);}
  renameSync(from,to){const a=this.key(from),b=this.key(to);const value=this.files.get(a);
    if(!value)throw this.error('ENOENT',a);this.files.set(b,value);this.files.delete(a);}
  json(file,value){this.writeFileSync('/fixture/'+file,JSON.stringify(value));}
}
function floor(z){
  const points=[[0,0,z],[375,0,z],[375,375,z],[0,375,z]],indices=[0,1,2,0,2,3];
  const b=Buffer.alloc(16+points.length*12+indices.length*4);
  [0x324c4353,points.length,indices.length/3,0].forEach((n,i)=>b.writeUInt32LE(n,i*4));
  points.forEach((p,i)=>p.forEach((n,j)=>b.writeFloatLE(n,16+i*12+j*4)));
  indices.forEach((n,i)=>b.writeUInt32LE(n,16+points.length*12+i*4));return b;
}
function storage(){
  const m=new MemoryFS();
  m.json('local-only/selfhost/client-catalog.json',{vehicles:[],
    homes:[{key:'authored-home',name:'Authored home',price:100,kind:'authored-room',out:[110,110,20,90]}],
    interior_spawns:{'authored-room':[110,110,900,180]},
    dealers:[{key:'a',name:'Authored A',air:'ls',stand:[120,120,20],sells:[593]},
      {key:'b',name:'Authored B',air:'sf',stand:[500,500,20],sells:[593]}]});
  m.json('local-only/selfhost/weapon-catalog.json',{items:[{id:22,name:'Authored gun',slot:2,
    capacity:17,ammo:30,price:0,fire:'INSTANT_HIT',stats:{loop:[0,9,0],range:40}}],shops:[]});
  m.json('local-only/site/game/native/riders.json',{version:2,models:{400:{seats:[{at:[0,0,0]},{at:[1,0,0]}]}}});
  m.json('local-only/site/game/world/index.json',{water:[],
    detail:{size:375,grid:16,origin:-3000,cells:[{cell:136}]},inside:{cells:[{cell:136}]}});
  m.writeFileSync('/fixture/local-only/site/game/world/c136.col.bin',floor(20));
  m.writeFileSync('/fixture/local-only/site/game/world/i136.col.bin',floor(900));
  return m;
}
let nextPID=10000;
function backend(memory=storage(),clock={now:1_700_000_000_000},sourceRoot=ROOT){
  const cache=new Map(),timers=new Set(),errors=[],handlers=new Map();
  const processFake={pid:nextPID++,env:{},on(name,fn){const list=handlers.get(name)||[];list.push(fn);handlers.set(name,list);},
    kill(){throw Object.assign(Error('Virtual process is gone'),{code:'ESRCH'});},
    exit(){for(const f of handlers.get('exit')||[])f();}};
  class ClockDate extends Date{constructor(...args){super(...(args.length?args:[clock.now]));}static now(){return clock.now;}}
  const timer=fn=>{const t={fn,unref(){return this;}};timers.add(t);return t;};
  function load(name){
    const filename=name.endsWith('.js')?name:name+'.js';
    assert(/^[a-z_]+\.js$/.test(filename),'Unexpected source dependency');
    if(cache.has(filename))return cache.get(filename).exports;
    const mod={exports:{}};cache.set(filename,mod);
    const sandbox={module:mod,exports:mod.exports,__dirname:'/fixture',__filename:'/fixture/'+filename,
      Buffer,URL,URLSearchParams,TextEncoder,TextDecoder,Date:ClockDate,
      process:processFake,console:{log(){},error(...v){errors.push(v.map(String).join(' '));}},
      setTimeout:timer,setInterval:timer,clearTimeout:t=>timers.delete(t),clearInterval:t=>timers.delete(t),
      fetch(){throw Error('Network access forbidden in authored fixture');},
      require(id){if(id==='fs'||id==='node:fs')return memory;
        if(id==='path'||id==='node:path')return path;
        if(id==='crypto'||id==='node:crypto')return crypto;
        if(id.startsWith('./'))return load(id.slice(2));throw Error('Unexpected dependency:'+id);}};
    vm.runInNewContext(fs.readFileSync(path.join(sourceRoot,filename),'utf8'),sandbox,{filename,timeout:5000});
    return mod.exports;
  }
  const game=load('selfhost_backend');
  return{game,memory,clock,errors,timers,
    advance(ms){clock.now+=ms;},
    stop(){game.flushSync();processFake.exit();timers.clear();},
    async auth(cookie=''){
      const res={headers:{},setHeader(k,v){this.headers[k.toLowerCase()]=v;},
        writeHead(code,headers){this.code=code;Object.assign(this.headers,headers);},end(bytes){this.bytes=bytes;}};
      await game.http({url:'/api/auth/me',method:'GET',headers:{cookie,host:'127.0.0.1:1'},
        socket:{remoteAddress:'127.0.0.1'}},res);
      assert.equal(res.code,200);const body=JSON.parse(res.bytes);
      return{cookie:cookie||res.headers['set-cookie'].split(';')[0],id:body.id,player:game.players.get(body.id)};
    },
    connect(account,opts={}){
      const socket=new FakeSocket();const prior=new Set(game.peers);
      game.upgrade({url:'/api/world/live',headers:{cookie:account.cookie,upgrade:'websocket',
        'sec-websocket-key':Buffer.alloc(16,7).toString('base64'),host:'127.0.0.1:1'},
        socket:{remoteAddress:'127.0.0.1'}},socket,Buffer.alloc(0));
      const peer=[...game.peers].find(p=>!prior.has(p));assert(peer,'Actual upgrade did not create peer');
      const actor={...account,peer,socket,packets:socket.packets,
        send(value){clock.now+=20;socket.emit('data',frame(value));},
        envelope(){return game.placement?.envelope(peer);},
        hello(){return socket.packets.filter(m=>m.t==='hello').at(-1);},
        close(){socket.destroy();}};
      actor.send(opts.hi||{t:'hi',nativeInventory:true,inventoryAck:1,healthAck:1,
        ...(opts.position===false?{}:{positionAck:1})});
      return actor;
    }};
}
class FakeSocket extends EventEmitter{
  constructor(){super();this.writable=true;this.writableLength=0;this.packets=[];this.upgrade='';}
  write(value){
    const bytes=Buffer.from(value);
    if(bytes.subarray(0,5).toString()==='HTTP/'){this.upgrade=bytes.toString();return true;}
    const opcode=bytes[0]&15;if(opcode!==1)return true;
    let n=bytes[1]&127,offset=2;if(n===126){n=bytes.readUInt16BE(2);offset=4;}
    else if(n===127){n=Number(bytes.readBigUInt64BE(2));offset=10;}
    assert.equal(bytes.length,offset+n);this.packets.push(JSON.parse(bytes.subarray(offset).toString()));return true;
  }
  end(){if(!this.writable)return;this.writable=false;this.emit('close');}
  destroy(){this.end();}
}
function frame(value){const bytes=Buffer.from(JSON.stringify(value));assert(bytes.length<65536);
  const mask=Buffer.from([1,2,3,4]),head=Buffer.alloc(bytes.length<126?6:8);head[0]=0x81;
  if(bytes.length<126)head[1]=0x80|bytes.length;else{head[1]=0xfe;head.writeUInt16BE(bytes.length,2);}
  mask.copy(head,head.length-4);const payload=Buffer.from(bytes);for(let i=0;i<payload.length;i++)payload[i]^=mask[i&3];
  return Buffer.concat([head,payload]);}
const foot=(actor,x=100,y=100,extra={})=>({t:'me',walking:true,skin:7,x,y,z:20,heading:.75,
  health:actor.player.health,armour:actor.player.armour,move:0,air:false,act:0,
  ...(actor.peer.positionAckEnabled?{placement:actor.envelope()}:{}),...extra});

async function main(){
  await scenario('actual new guest negotiates, admits grounded foot and reconnects with fresh baseline',async()=>{
    const h=backend(),account=await h.auth(),a=h.connect(account);
    same(a.hello().spot,[1480,-1738,13,0],'New guest spawn changed');
    same(a.hello().placement,{connection:a.peer.inventoryConnection,revision:0},'Initial position namespace');
    check(a.packets.some(p=>p.t==='all')&&a.packets.some(p=>p.t==='inventory'),'Fresh baselines absent');
    const nonce=a.peer.inventoryConnection;a.send(foot(a,125,140));
    same(account.player.reconnectPlacement.foot.spot,[125,140,20,.75],'Grounded actual SCL2 checkpoint absent');
    h.game.flushSync();check(!h.game.saveTimer,'Flush did not settle save timer');
    a.send(foot(a,125,140));check(!h.game.saveTimer,'Idle position unnecessarily schedules disk writes');
    a.close();same(h.game.position(account.player),null,'Closed actor remains live');
    const b=h.connect(await h.auth(account.cookie));
    same(b.hello().spot,[125,140,20,.75],'Authoritative foot position not resumed');
    check(b.peer.inventoryConnection!==nonce,'Connection nonce reused');same(b.peer.processedShotSequence,0,'Shot counter reused');
    same([b.player.health,b.player.armour],[100,0],'Reconnect changed vitals');
    check(!b.peer.state,'Reconnect manufactured occupied/old actor state');
    check(!h.errors.length,h.errors.join('\n'));h.stop();
  });
  await scenario('legacy path preserves old behavior and reproduces same-peer old-me ambiguity',async()=>{
    const h=backend(),account=await h.auth(),a=h.connect(account,{position:false});
    check(!a.hello().positionAck&&!a.peer.positionAckEnabled,'Legacy was silently opted in');
    a.send(foot(a));a.player.homes.push('authored-home');
    const old=foot(a,100,100);h.game.action(a.player,'home.visit',{home:'authored-home'});
    check(a.packets.some(p=>p.t==='tp'&&!p.placement),'Legacy TP altered');
    a.send(old);same([a.peer.state.x,a.peer.state.y],[100,100],'Legacy ambiguity not reproduced');
    a.close();const b=h.connect(await h.auth(account.cookie),{position:false});
    same(b.hello().spot,[1480,-1738,13,0],'Legacy initial-spawn policy changed');
    h.stop();
  });
  await scenario('strict TP fences queued old me before position, commands or terminal-report effects',async()=>{
    const h=backend(),a=h.connect(await h.auth());a.send(foot(a));a.player.homes.push('authored-home');
    a.player.health=73;a.player.armour=11;
    a.player.inventory={version:1,revision:4,selected:22,weapons:{22:{clip:5,rest:10}}};
    h.game.sendInventory(a.peer);
    const inventory=structuredClone(a.player.inventory),name=a.player.name;
    const old=foot(a,105,105,{say:'/name SHOULD_NOT_RUN'});
    h.game.action(a.player,'home.visit',{home:'authored-home'});
    const tp=a.packets.filter(p=>p.t==='tp').at(-1);
    same(tp.placement,{connection:a.peer.inventoryConnection,revision:1},'TP epoch did not advance');
    same([tp.x,tp.y,tp.z,tp.h],[110,110,20,90],'TP coordinates/degree contract changed');
    check(!a.peer.state,'Prior actor pose retained during placement');
    const sentinel={until:h.clock.now+10000};h.game.terminalVehicleReports.set(a.peer,sentinel);
    a.send(old);check(!a.peer.state,'Queued old me undid authoritative TP');
    same(a.player.name,name,'Queued old me replayed chat command');
    check(h.game.terminalVehicleReports.get(a.peer)===sentinel,'Old me reached terminal pruning');
    same([a.player.health,a.player.armour],[73,11],'TP/old me changed vitals');
    same(a.player.inventory,inventory,'TP/old me changed ammunition');
    same(a.player.reconnectPlacement.intent.spot,[110,110,20,Math.PI/2],'Pending authoritative target lost');
    h.game.terminalVehicleReports.delete(a.peer);
    a.send(foot(a,110,110,{heading:Math.PI/2}));
    same(a.player.reconnectPlacement.foot.spot,[110,110,20,Math.PI/2],'Current epoch report not admitted');
    same(a.player.reconnectPlacement.intent,null,'Acknowledged verified foot did not clear intent');
    check(!h.errors.length,h.errors.join('\n'));h.stop();
  });
  await scenario('wrong nonce, malformed/future revisions and removed peers cannot rewrite a fresh session',async()=>{
    const h=backend(),account=await h.auth(),a=h.connect(account);a.send(foot(a,125,140));
    const oldFrame=foot(a,140,150),oldNonce=a.peer.inventoryConnection;a.close();
    const b=h.connect(await h.auth(account.cookie));b.send(foot(b,125,140));
    const state=structuredClone(b.peer.state),saved=structuredClone(b.player.reconnectPlacement);
    const values=[undefined,null,[],{},true,{connection:oldNonce,revision:0},
      {connection:b.peer.inventoryConnection,revision:-1},{connection:b.peer.inventoryConnection,revision:.5},
      {connection:b.peer.inventoryConnection,revision:1},{connection:b.peer.inventoryConnection,revision:NaN},
      {connection:b.peer.inventoryConnection,revision:Number.MAX_SAFE_INTEGER+1}];
    for(const placement of values)b.send(foot(b,160,170,{placement,say:'/name SHOULD_NOT_RUN'}));
    same(b.peer.state,state,'Malformed placement mutated current actor');
    same(b.player.reconnectPlacement,saved,'Malformed placement mutated checkpoint');
    a.socket.emit('data',frame(oldFrame));
    same(b.peer.state,state,'Removed peer callback overwrote fresh state');
    same(b.player.reconnectPlacement,saved,'Removed peer callback changed account checkpoint');
    check(!h.errors.length,h.errors.join('\n'));h.stop();
  });
  await scenario('duplicate hello never resets/downgrades current placement epoch or pending intent',async()=>{
    const h=backend(),a=h.connect(await h.auth());a.send(foot(a,110,110));a.player.homes.push('authored-home');
    h.game.action(a.player,'home.enter',{home:'authored-home'});
    const nonce=a.peer.inventoryConnection,initial=structuredClone(a.peer.placementSession.hello);
    a.peer.processedShotSequence=7;a.peer.processedHealthSequence=3;
    a.send({t:'hi'});
    same(a.peer.inventoryConnection,nonce,'Duplicate hello changed nonce');
    same(a.envelope(),{connection:nonce,revision:1},'Duplicate hello rewound epoch');
    same(a.peer.placementSession.hello,initial,'Duplicate hello replaced original baseline');
    same(a.player.insideHome,'authored-home','Duplicate hello reset home dimension');
    same([a.peer.processedShotSequence,a.peer.processedHealthSequence],[7,3],'Duplicate hello rewound action ACKs');
    check(a.peer.positionAckEnabled,'Duplicate hello downgraded strict capability');
    a.send({...foot(a),placement:undefined});check(!a.peer.state,'Downgrade accepted unacknowledged me');
    check(!h.errors.length,h.errors.join('\n'));h.stop();
  });
  await scenario('pending home command survives disconnect/restart and restores matching dimension',async()=>{
    const h=backend(),account=await h.auth(),a=h.connect(account);a.send(foot(a,110,110));a.player.homes.push('authored-home');
    h.game.action(a.player,'home.enter',{home:'authored-home'});
    const old=foot(a,100,100,{placement:{connection:a.peer.inventoryConnection,revision:0}});a.send(old);
    const inventory=structuredClone(a.player.inventory);a.close();h.stop();
    const restarted=backend(h.memory,h.clock),b=restarted.connect(await restarted.auth(account.cookie));
    same(restarted.game.players.size,1,'Restart/reconnect created another account');
    same(b.hello().spot,[110,110,900,Math.PI],'Pending home target did not survive restart');
    same(b.player.insideHome,'authored-home','Resume restored interior without matching dimension');
    same(b.player.inventory,inventory,'Restart position changed inventory');
    same(b.envelope(),{connection:b.peer.inventoryConnection,revision:0},'Restart epoch/nonce not fresh');
    b.send(foot(b,110,110,{z:900,heading:Math.PI}));
    same(b.player.reconnectPlacement.intent,null,'Verified interior foot failed to settle intent');
    restarted.game.action(b.player,'home.exit',{});
    const tp=b.packets.filter(p=>p.t==='tp').at(-1);
    same([tp.x,tp.y,tp.z,tp.h],[110,110,20,90],'Home exit semantics changed');
    same(b.player.insideHome,null,'Home exit retained dimension');
    b.send(foot(b,110,110,{z:900,placement:{connection:b.peer.inventoryConnection,revision:0}}));
    check(!b.peer.state,'Stale interior frame crossed exterior placement fence');
    b.send(foot(b,110,110,{heading:Math.PI/2}));
    same(b.player.reconnectPlacement.foot.home,null,'New outdoor checkpoint retained interior');
    check(!restarted.errors.length,restarted.errors.join('\n'));restarted.stop();
  });
  await scenario('dead account restart preserves zero health/cooldown; explicit respawn places before ACK once',async()=>{
    const h=backend(),account=await h.auth(),a=h.connect(account);a.send(foot(a,125,140));
    a.player.health=0;a.player.armour=11;a.player.lastDeath=h.clock.now-1000;
    const inventory=structuredClone(a.player.inventory);a.close();h.stop();
    const r=backend(h.memory,h.clock),b=r.connect(await r.auth(account.cookie));
    same(b.hello().life,[0,11],'Restart hello healed dead account');
    same(b.player.lastDeath,a.player.lastDeath,'Restart lost respawn cooldown');
    const request=s=>({t:'selfHealth',c:b.peer.inventoryConnection,s,kind:'respawn',damage:0});
    b.send(request(1));same(b.player.health,0,'Early respawn accepted');
    same(b.packets.filter(p=>p.t==='tp').length,0,'Rejected respawn placed actor');
    r.advance(2001);b.send(request(2));same([b.player.health,b.player.armour],[100,0],'Valid respawn rejected');
    const tpIndex=b.packets.findLastIndex(p=>p.t==='tp'),ackIndex=b.packets.findLastIndex(p=>p.t==='vitals');
    check(tpIndex>=0&&tpIndex<ackIndex,'Respawn ACK preceded authoritative placement');
    same(b.packets[tpIndex].placement,{connection:b.peer.inventoryConnection,revision:1},'Respawn placement epoch');
    same(b.player.reconnectPlacement.intent.spot,[1480,-1738,13,0],'Respawn did not supersede old resume point');
    b.send(foot(b,125,140,{placement:{connection:b.peer.inventoryConnection,revision:0},health:0}));
    check(!b.peer.state,'Queued pre-respawn position was accepted');same(b.player.health,100,'Old frame undid respawn health');
    const count=b.packets.filter(p=>p.t==='tp').length;b.send(request(2));
    same(b.packets.filter(p=>p.t==='tp').length,count,'Duplicate respawn replayed teleport');
    same(b.player.inventory,inventory,'Respawn position minted/replayed ammunition');
    check(!r.errors.length,r.errors.join('\n'));r.stop();
  });
  await scenario('position capability requires native inventory ACK and cannot upgrade mid-session',async()=>{
    const h=backend(),a=h.connect(await h.auth(),{hi:{t:'hi',positionAck:1}});
    check(!a.peer.positionAckEnabled&&!a.hello().positionAck,'Unacknowledged browser opted into resume');
    a.send(foot(a,125,140));check(!!a.peer.state,'Existing browser foot path broke');a.close();
    const b=h.connect(await h.auth(),{position:false});b.send({t:'hi',positionAck:1});
    check(!b.peer.positionAckEnabled&&!b.hello().positionAck,'Late hi silently upgraded existing position namespace');
    b.send(foot(b,125,140));check(!!b.peer.state,'Legacy native me unexpectedly needs envelope');
    const c=h.connect(await h.auth(),{hi:{t:'hi',nativeInventory:true,inventoryAck:1,positionAck:1}});
    check(!c.peer.positionAckEnabled&&!c.hello().positionAck,'Unsequenced health client entered strict no-heal mode');
    check(!h.errors.length,h.errors.join('\n'));h.stop();
  });
  await scenario('only grounded ordinary foot reports replace the conservative checkpoint',async()=>{
    const h=backend(),account=await h.auth(),a=h.connect(account);a.send(foot(a,125,140));
    const saved=structuredClone(a.player.reconnectPlacement);
    const cases=[{air:true},{crouch:true},{act:14},{act:61},{act:65},
      {on:{v:'moving-platform',x:0,y:0,z:0}},{x:6001},{x:500,y:500},
      {z:22},{z:19.9},{z:10000},{heading:NaN},{x:NaN}];
    for(const extra of cases){a.send(foot(a,160,170,extra));same(a.player.reconnectPlacement,saved,'Unsafe/unknown-ground state became checkpoint');}
    a.close();const b=h.connect(await h.auth(account.cookie));
    same(b.hello().spot,[125,140,20,.75],'Unsafe last packet replaced verified foot anchor');
    check(!h.errors.length,h.errors.join('\n'));h.stop();
  });
  await scenario('driver reconnect uses last foot anchor and never restores registry grants or moves hull',async()=>{
    const h=backend(),account=await h.auth(),a=h.connect(account);a.send(foot(a));
    // Explicit authored seed of owned catalogue/garage data; no user save or
    // purchase bypass in the application is used or claimed by this fixture.
    a.player.cars=[400];a.player.garage=[{active:true,position:[100,105,20,0],health:930,
      damage:'',paint:null,pitch:0,roll:0,work:1234,parkedHome:null}];
    const car=h.game.addOwnedVehicle(a.player,0);check(!!car,'Authored owned vehicle not created');
    a.send({t:'enter',v:car.id});check(a.packets.some(p=>p.t==='enter'&&p.ok),'Actual driver reservation denied');
    const drive=(x,y)=>({t:'me',driving:true,skin:7,vehicle:car.id,car:car.row[2],x,y,z:20,
      heading:.25,pitch:0,roll:0,health:900,life:100,w:1234,placement:a.envelope()});
    a.send(drive(100,105));check(h.game.vehicleDriver(car)===a.peer,'Actual claim did not become driver');
    a.send(drive(300,300));same(car.row.slice(3,6),[300,300,20],'Driver hull update rejected');
    same(a.player.reconnectPlacement.foot.spot,[100,100,20,.75],'Driving overwrote foot anchor');
    const old=drive(350,350),id=car.id;a.close();
    check(!h.game.vehicleClaim(car),'Disconnect retained driving rights');same(car.row[11],null,'Disconnect did not park');
    const b=h.connect(await h.auth(account.cookie));same(b.hello().spot,[100,100,20,.75],'Driver restored unsafe hull centre');
    check(h.game.vehicles.get(id)===car,'Reconnect replaced vehicle occurrence');
    b.send({...old,placement:{connection:b.peer.inventoryConnection,revision:0}});
    same(car.row.slice(3,6),[300,300,20],'Fresh peer gained old driver authority');
    check(!h.game.vehicleClaim(car),'Fresh hello implicitly granted driver');
    b.send(foot(b));b.send({t:'enter',v:id});check(!b.packets.filter(p=>p.t==='enter').at(-1).ok,'Far fallback bypassed ordinary8m entry rule');
    h.stop();const r=backend(h.memory,h.clock),c=r.connect(await r.auth(account.cookie));
    same(c.player.cars,[400],'Restart lost owned vehicle entitlement');
    const restored=r.game.ownedVehicle(c.player,0);check(!!restored,'Restart lost parked vehicle');
    same(restored.row.slice(3,6),[300,300,20],'Restart moved parked hull to foot checkpoint');
    same(restored.row[16],1234,'Restart lost working-part value');check(!r.game.vehicleClaim(restored),'Restart restored stale driver grant');
    check(!r.errors.length,r.errors.join('\n'));r.stop();
  });
  await scenario('server placement revokes current driver while preserving parked condition and job progress',async()=>{
    const h=backend(),a=h.connect(await h.auth());a.send(foot(a));a.player.homes.push('authored-home');
    a.player.cars=[400];a.player.garage=[{active:true,position:[100,105,20,0],health:930,
      damage:'',paint:null,pitch:0,roll:0,work:1200,parkedHome:null}];
    const car=h.game.addOwnedVehicle(a.player,0);a.send({t:'enter',v:car.id});
    a.send({t:'me',driving:true,skin:7,vehicle:car.id,car:car.row[2],x:100,y:105,z:20,
      heading:.2,health:800,life:100,w:1200,placement:a.envelope()});
    a.player.job={id:'courier',goal:38,progress:0,started:h.clock.now};
    const queued=foot(a,105,105,{say:'/name SHOULD_NOT_RUN'});
    h.game.action(a.player,'home.visit',{home:'authored-home'});
    check(!h.game.vehicleClaim(car),'Authoritative teleport retained driving role');
    same(car.row.slice(3,6),[100,105,20],'Teleport moved or hid parked hull');same(car.row[9],800,'Teleport repaired hull');
    same(car.row[16],1200,'Teleport reset physical work value');
    a.send(queued);same(a.player.job.progress,0,'Old me replayed job movement');
    a.send(foot(a,110,110,{heading:Math.PI/2}));same(a.player.job.progress,0,'Placement counted as job distance');
    a.send(foot(a,111,110,{heading:Math.PI/2}));same(a.player.job.progress,1,'Ordinary new movement stopped counting');
    check(!h.errors.length,h.errors.join('\n'));h.stop();
  });
  await scenario('accepted shot persists once; old shot/hit and in-flight pre-TP fire never replay on resume',async()=>{
    const h=backend(),account=await h.auth(),a=h.connect(account);a.send(foot(a));
    a.player.inventory={version:1,revision:1,selected:22,weapons:{22:{clip:5,rest:10}}};h.game.sendInventory(a.peer);
    const shot={t:'shot',c:a.peer.inventoryConnection,s:1,w:22,o:[100,100,21],h:[110,100,21]};
    a.send(shot);same(a.player.inventory.weapons['22'],{clip:4,rest:10},'Actual accepted shot not consumed once');
    check(a.packets.filter(p=>p.t==='inventory').at(-1).result.accepted,'Shot baseline was rejected');
    const inventory=structuredClone(a.player.inventory);a.close();h.stop();
    const r=backend(h.memory,h.clock),b=r.connect(await r.auth(account.cookie));
    same(b.player.inventory,inventory,'Fresh hello replayed or refunded accepted shot');
    same(b.peer.processedShotSequence,0,'Reconnect reused shot namespace');
    b.send(shot);same(b.player.inventory,inventory,'Old-nonce shot consumed ammunition');
    b.send({t:'hit',c:shot.c,s:1,w:22,to:String(b.player.number)});same(b.player.health,100,'Old-nonce hit replayed damage');
    b.send(foot(b));b.player.homes.push('authored-home');r.game.action(b.player,'home.visit',{home:'authored-home'});
    b.send({...shot,c:b.peer.inventoryConnection});same(b.player.inventory,inventory,'Pre-TP pending fire consumed ammo without current actor baseline');
    check(!b.packets.filter(p=>p.t==='inventory').at(-1).result.accepted,'Pending fire incorrectly accepted during placement');
    check(!r.errors.length,r.errors.join('\n'));r.stop();
  });
  await scenario('late/duplicate respawn ACK cannot make server replay an obsolete placement',async()=>{
    const h=backend(),account=await h.auth(),a=h.connect(account);a.send(foot(a));
    a.player.health=0;a.player.lastDeath=h.clock.now-3000;a.player.homes.push('authored-home');
    const request={t:'selfHealth',c:a.peer.inventoryConnection,s:1,kind:'respawn',damage:0};
    a.send(request);same(a.envelope().revision,1,'Initial respawn placement absent');
    a.send(foot(a,1480,-1738,{z:13,heading:0}));
    h.game.action(a.player,'home.visit',{home:'authored-home'});
    same(a.envelope().revision,2,'Newer server teleport did not advance placement');
    const count=a.packets.filter(p=>p.t==='tp').length;a.send(request);
    same(a.packets.filter(p=>p.t==='tp').length,count,'Duplicate health ACK replayed old spawn command');
    same(a.player.reconnectPlacement.intent.spot,[110,110,20,Math.PI/2],'Late ACK rewound server resume target');
    a.close();const b=h.connect(await h.auth(account.cookie));
    same(b.hello().spot,[110,110,20,Math.PI/2],'Reconnect chose old respawn over newer teleport');
    check(!h.errors.length,h.errors.join('\n'));h.stop();
  });
  await scenario('revision exhaustion rejects before partial home/job/respawn mutation',async()=>{
    const h=backend(),a=h.connect(await h.auth());a.send(foot(a,110,110));a.player.homes.push('authored-home');
    a.peer.placementSession.revision=Number.MAX_SAFE_INTEGER;
    const state=structuredClone(a.peer.state),store=structuredClone(a.player.reconnectPlacement);
    check(!h.game.placement.canIssue(a.peer),'Exhausted epoch may advance');
    for(const [action,input]of[['home.enter',{home:'authored-home'}],['job.start',{job:'pilot'}]]){
      let rejected=false;try{h.game.action(a.player,action,input);}catch(error){rejected=/Placement session/.test(error.message);}
      check(rejected,'Exhausted placement action did not reject');
    }
    same(a.player.insideHome,null,'Rejected home partially changed dimension');same(a.player.job,null,'Rejected pilot partially created job');
    same(a.peer.state,state,'Rejected placement discarded live pose');same(a.player.reconnectPlacement,store,'Rejected placement changed checkpoint');
    a.player.health=0;a.player.lastDeath=h.clock.now-3000;
    a.send({t:'selfHealth',c:a.peer.inventoryConnection,s:1,kind:'respawn',damage:0});
    same(a.player.health,0,'Exhausted placement partially healed');
    same(a.packets.filter(p=>p.t==='tp').length,0,'Exhausted placement emitted TP');
    check(!h.errors.length,h.errors.join('\n'));h.stop();
  });
  await scenario('malformed/unowned/missing-ground persisted placements fail closed without healing',async()=>{
    const h=backend(),account=await h.auth(),a=h.connect(account);a.send(foot(a,125,140));
    a.player.health=0;a.player.lastDeath=h.clock.now;h.stop();
    const statePath='/fixture/local-only/selfhost/players.json';
    const valid={spot:[125,140,20,.75],home:null,source:'foot',context:null,updatedAt:h.clock.now};
    const mutants=[null,{version:2,foot:valid},
      {version:1,foot:{...valid,spot:[125,140,20]}},
      {version:1,foot:{...valid,spot:[125,140,20,1e300]}},
      {version:1,foot:{...valid,spot:[125,140,null,.75]}},
      {version:1,foot:{...valid,spot:[1e7,140,20,.75]}},
      {version:1,foot:{...valid,source:'driver'}},
      {version:1,foot:{...valid,home:'unowned-home'}},
      {version:1,foot:{...valid,updatedAt:1e300}},
      {version:1,foot:{...valid,spot:[500,500,20,.75]}},
      {version:1,foot:{...valid,spot:[125,140,19.9,.75]}}];
    for(const mutant of mutants){
      const m=new MemoryFS();m.files=new Map([...h.memory.files].map(([k,v])=>[k,Buffer.from(v)]));
      const saved=JSON.parse(m.readFileSync(statePath,'utf8'));saved.players[account.id].reconnectPlacement=mutant;
      m.json('local-only/selfhost/players.json',saved);const r=backend(m,h.clock),b=r.connect(await r.auth(account.cookie));
      same(b.hello().spot,[1480,-1738,13,0],'Malformed checkpoint changed spawn admission');
      same(b.hello().life[0],0,'Fallback placement implicitly respawned dead actor');
      same(r.game.players.size,1,'Malformed record created account');
      same(r.game.vehicleClaims.size,0,'Malformed placement created vehicle authority');
      check(!r.errors.length,r.errors.join('\n'));r.stop();
    }
  });
  await scenario('all seven actual TP producers preserve degrees, fence revisions and retain world authority',async()=>{
    const text=fs.readFileSync(path.join(ROOT,'selfhost_backend.js'),'utf8');
    same((text.match(/\bt:\s*['"]tp['"]/g)||[]).length,7,'TP inventory changed: extend actual producer coverage');
    const paths=['home.enter','home.exit','home.visit','pilot.start','passenger.release','passenger.reject','respawn'];
    for(const degrees of [-180,-40,0,39.5340878640268,90,180,720])for(const producer of paths){
      const m=storage(),catalog=JSON.parse(m.readFileSync('/fixture/local-only/selfhost/client-catalog.json','utf8'));
      catalog.homes[0].out[3]=degrees;catalog.interior_spawns['authored-room'][3]=degrees;
      m.json('local-only/selfhost/client-catalog.json',catalog);
      const h=backend(m),a=h.connect(await h.auth());a.player.homes.push('authored-home');
      a.send(foot(a,110,110,{heading:degrees*Math.PI/180}));
      const previous=foot(a,100,100),beforeInventory=structuredClone(a.player.inventory);
      let expected=[110,110,20,degrees];
      if(producer==='home.enter'){
        h.game.action(a.player,'home.enter',{home:'authored-home'});expected=[110,110,900,degrees];
      }else if(producer==='home.exit'){
        h.game.action(a.player,'home.enter',{home:'authored-home'});
        a.send(foot(a,110,110,{z:900,heading:degrees*Math.PI/180}));
        h.game.action(a.player,'home.exit',{});
      }else if(producer==='home.visit')h.game.action(a.player,'home.visit',{home:'authored-home'});
      else if(producer==='pilot.start'){
        h.game.action(a.player,'job.start',{job:'pilot',model:593});
        expected=[1563,-2460,13.55,90];
        check(h.game.vehicles.has(a.player.job.vehicleId),'Pilot TP lost mission hull');
      }else if(producer==='passenger.release'){
        a.player.cars=[400];a.player.garage=[{active:true,position:[110,110,20,degrees*Math.PI/180],
          health:930,damage:'',paint:null,pitch:0,roll:0,work:1234,parkedHome:null}];
        const car=h.game.addOwnedVehicle(a.player,0);
        a.send({t:'enter',v:car.id,seat:1});check(a.packets.filter(p=>p.t==='enter').at(-1).ok,'Authored passenger reservation denied');
        a.send(foot(a,110,110,{riding:car.id,seat:1}));
        const claim=h.game.passengerClaims.get(a.peer);check(claim?.active,'Actual passenger report not activated');
        h.game.releasePassengerClaim(claim,{correct:true});
        same(h.game.passengerClaims.size,0,'Correction retained passenger authority');
        same(car.row[16],1234,'Passenger correction changed working part');
      }else if(producer==='passenger.reject'){
        a.send({...foot(a,110,110),walking:false,driving:true,riding:'unknown',seat:1});
      }else{
        a.player.health=0;a.player.lastDeath=h.clock.now-3000;
        a.send({t:'selfHealth',c:a.peer.inventoryConnection,s:1,kind:'respawn',damage:0});
        expected=[1480,-1738,13,0];
      }
      const tp=a.packets.filter(p=>p.t==='tp').at(-1);
      check(!!tp,producer+' did not emit actual TP');
      same([tp.x,tp.y,tp.z],expected.slice(0,3),producer+' changed target');
      near(tp.h,expected[3],producer+' violated TP degrees');
      same(tp.placement,a.envelope(),producer+' lacks exact current revision');
      same(a.envelope().revision,producer==='home.exit'?2:1,producer+' revision count');
      check(!a.peer.state,producer+' left live pre-placement state');
      a.send(previous);check(!a.peer.state,producer+' admitted queued pre-placement report');
      same(a.player.inventory,beforeInventory,producer+' changed ammunition');
      check(!h.errors.length,h.errors.join('\n'));h.stop();
    }
  });
  await scenario('active passenger reconnect/TP never restores seat or promotes body-origin target to foot',async()=>{
    const h=backend(),account=await h.auth(),a=h.connect(account);a.send(foot(a,100,100));
    a.player.cars=[400];a.player.garage=[{active:true,position:[105,105,20,.5],health:930,
      damage:'',paint:null,pitch:0,roll:0,work:1200,parkedHome:null}];
    const car=h.game.addOwnedVehicle(a.player,0);
    a.send({t:'enter',v:car.id,seat:1});check(a.packets.filter(p=>p.t==='enter').at(-1).ok,'Seat reservation rejected');
    a.send(foot(a,105,105,{riding:car.id,seat:1}));
    check(h.game.passengerClaims.get(a.peer)?.active,'Passenger ownership not active');
    same(a.player.reconnectPlacement.foot.spot,[100,100,20,.75],'Seated body replaced verified foot');
    const old=foot(a,105,105,{riding:car.id,seat:1});
    h.game.releasePassengerClaim(h.game.passengerClaims.get(a.peer),{correct:true});
    same(a.player.reconnectPlacement.intent.source,'passenger','Correction did not fence');
    a.send(old);check(!a.peer.state,'Old passenger report reacquired after fenced correction');
    a.close();const b=h.connect(await h.auth(account.cookie));
    same(b.hello().spot,[100,100,20,.75],'Reconnect used unverified body origin');
    same(h.game.passengerClaims.size,0,'Reconnect restored seat');
    same(h.game.vehicleClaims.size,0,'Reconnect granted driver authority');
    same(car.row.slice(3,6),[105,105,20],'Reconnect moved hull');
    check(!h.errors.length,h.errors.join('\n'));h.stop();
  });
  await scenario('invalid issued commands fail atomically; pilot intent survives restart without boarding grant',async()=>{
    const h=backend(),account=await h.auth(),a=h.connect(account);a.send(foot(a));
    const before=structuredClone(a.player.reconnectPlacement),epoch=a.envelope(),state=structuredClone(a.peer.state);
    for(const [packet,options]of[
      [{t:'tp',x:NaN,y:100,z:20,h:0},{source:'pilot'}],
      [{t:'tp',x:100,y:100,z:20,h:Infinity},{source:'pilot'}],
      [{t:'tp',x:100,y:100,z:20,h:0},{source:'invented'}],
      [{t:'tp',x:100,y:100,z:20,h:0},{source:'home.enter',home:{id:'wrong'}}]]){
      let rejected=false;try{h.game.sendTeleport(a.peer,packet,options);}catch{rejected=true;}
      check(rejected,'Malformed command was issued');same(a.player.reconnectPlacement,before,'Malformed command mutated persistent target');
      same(a.envelope(),epoch,'Malformed command consumed revision');same(a.peer.state,state,'Malformed command cleared actor');
    }
    h.game.action(a.player,'job.start',{job:'pilot',model:593});
    const job=structuredClone(a.player.job);a.close();h.stop();
    const r=backend(h.memory,h.clock),b=r.connect(await r.auth(account.cookie));
    same(b.hello().spot,[1563,-2460,13.55,Math.PI/2],'Pilot authoritative intent lost on restart');
    same(b.player.job.vehicleId,job.vehicleId,'Restart replaced job identity');
    check(r.game.vehicles.has(job.vehicleId),'Restart lost valid mission vehicle');
    same(r.game.vehicleClaims.size,0,'Pilot placement resumed implicit driver grant');
    same([b.player.health,b.player.armour],[100,0],'Pilot resume changed vitals');
    check(!r.errors.length,r.errors.join('\n'));r.stop();
  });
  await scenario('normalizer strips authority/actions and rejects scalar/schema corruption',async()=>{
    const Placement=require('../../player_placement');
    const valid={spot:[125,140,20,.75],home:null,source:'foot',context:null,updatedAt:1000};
    const value=Placement.normalize({version:1,foot:{...valid,vehicle:'FORGED',health:100,shots:[1]},
      inventory:{clip:999},revision:999,connection:'FORGED'});
    same(Object.keys(value).sort(),['foot','intent','version'],'Schema retained foreign state');
    same(Object.keys(value.foot).sort(),['context','home','source','spot','updatedAt'],'Checkpoint retained authority/action fields');
    const bad=[null,undefined,{},[],true,'1',NaN,Infinity,-Infinity];
    for(const scalar of bad){
      same(Placement.normalize({version:scalar,foot:valid}).foot,null,'Malformed schema admitted');
      same(Placement.normalize({version:1,foot:{...valid,spot:[scalar,140,20,.75]}}).foot,null,'Malformed coordinate admitted');
      same(Placement.normalize({version:1,foot:{...valid,spot:[125,140,20,scalar]}}).foot,null,'Malformed heading admitted');
    }
    for(const scalar of [-1,.5,Number.MAX_SAFE_INTEGER+1,Infinity,NaN])
      same(Placement.normalize({version:1,foot:{...valid,updatedAt:scalar}}).foot,null,'Invalid checkpoint time admitted');
    same([...Placement.DEFAULT_SPOT],[1480,-1738,13,0],'Initial server spawn mutated');
  });
  let historical=null;
  if(baseline){
    const first=checks,h=backend(storage(),{now:1_700_000_000_000},baseline);
    const account=await h.auth(),a=h.connect(account);a.send(foot(a,125,140));
    check(!a.peer.positionAckEnabled&&!a.hello().positionAck,'Historical backend unexpectedly supports negotiated placement');
    a.player.homes.push('authored-home');const queued=foot(a,125,140);
    h.game.action(a.player,'home.visit',{home:'authored-home'});a.send(queued);
    same([a.peer.state.x,a.peer.state.y],[125,140],'Actual historical stale-me ambiguity absent');
    a.close();const b=h.connect(await h.auth(account.cookie));
    same(b.hello().spot,[1480,-1738,13,0],'Actual historical reconnect no longer resets spawn');
    check(!b.peer.state,'Historical fresh hello unexpectedly restored old actor state');
    b.player.health=0;b.player.lastDeath=h.clock.now;b.close();h.stop();
    const r=backend(h.memory,h.clock,baseline),c=r.connect(await r.auth(account.cookie));
    same(c.player.health,1,'Actual historical saved-death health floor no longer reproduced');
    same(r.game.players.size,1,'Historical fixture changed account');
    check(!h.errors.length&&!r.errors.length,[...h.errors,...r.errors].join('\n'));r.stop();
    historical={status:'ACTUAL_BASELINE_DEFECTS_REPRODUCED',checks:checks-first,
      sourceRoot:baseline,sourceHashes:Object.fromEntries(SOURCES.filter(n=>fs.existsSync(path.join(baseline,n)))
        .map(n=>[n,hash(path.join(baseline,n))])),
      observations:['Requested positionAck is unsupported; stale same-peer me overwrites a server TP.',
        'Reconnect uses default spawn after a prior valid foot report.',
        'Restart loads saved health0 as1 while preserving the account.']};
  }
  fs.mkdirSync(OUT,{recursive:true});
  const report={status:'PASS',checks,scenarios,historical,sourceHashes:Object.fromEntries(SOURCES.map(n=>[n,hash(path.join(ROOT,n))])),
    limits:['Actual backend/HTTP/upgrade/Peer framing and persistence execute with authored catalogues and SCL2 floors.',
      'All backend file writes, process IDs, sockets and timers are virtual; no listener/device/live save or compiler.',
      'Negotiated clients are authored protocol peers, not the currently frozen native App.',
      'No physical Home/foreground or current-hull egress acceptance is claimed.']};
  fs.writeFileSync(path.join(OUT,'report.json'),JSON.stringify(report,null,2)+'\n');
  console.log(JSON.stringify({status:report.status,checks,scenarios:scenarios.length,historical:historical?.status||null}));
}
main().catch(error=>{console.error(error.stack||error);process.exitCode=1;});
