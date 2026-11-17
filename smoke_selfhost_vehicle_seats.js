#!/usr/bin/env node
'use strict';
// Independent HTTP/WebSocket integration fixture. The world, accounts, cars
// and coupling anchors below are authored test data; no game assets are used.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const http=require('node:http'),net=require('node:net'),crypto=require('node:crypto');
const ROOT=__dirname,OUT=path.join(ROOT,'local-only/research/vehicle-seats-107');
const SOURCES=['selfhost_backend.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js','vehicle_coupling.js'];
const hashes=()=>Object.fromEntries(SOURCES.map(name=>[name,crypto.createHash('sha256').update(fs.readFileSync(path.join(ROOT,name))).digest('hex')]));
const before=hashes(),fixture=fs.mkdtempSync(path.join(require('node:os').tmpdir(),'zgta-seats-'));
let archivedSerializer=null;
if(process.argv.length>2){
 assert(process.argv.length===4&&process.argv[2]==='--seat-serializer','Expected --seat-serializer REPORT');
 const bytes=fs.readFileSync(path.resolve(process.argv[3]));assert(bytes.length<256*1024,'Archived seat serializer report bound');
 archivedSerializer=JSON.parse(bytes);assert(archivedSerializer.schema===1&&archivedSerializer.passed===true&&/^[a-f0-9]{64}$/.test(archivedSerializer.archivedFactory19737SHA256),'Actual archived provenance missing');
 assert(Array.isArray(archivedSerializer.passengers)&&archivedSerializer.passengers.length===2,'Expected two actual serializer reports');
}
const savedEnv=Object.fromEntries(['ZGTA_JOIN_CODE','ZGTA_JOIN_CODE_FILE'].map(k=>[k,process.env[k]]));
for(const key of Object.keys(savedEnv))delete process.env[key];
let game,server,port,offset=0,checks=0;const clients=[],scenarios=[];
const realNow=Date.now;Date.now=()=>realNow()+offset;
function check(value,label){checks++;assert(value,label);}
function same(value,wanted,label){checks++;assert.deepEqual(value,wanted,label);}
async function scenario(name,body){const first=checks;await body();scenarios.push({name,checks:checks-first,passed:true});}
function request(route,cookie='',method='GET',body=null){return new Promise((resolve,reject)=>{
 const bytes=body===null?null:Buffer.from(JSON.stringify(body));
 const req=http.request({host:'127.0.0.1',port,path:route,method,headers:{...(cookie?{Cookie:cookie}:{}),...(bytes?{'Content-Type':'application/json','Content-Length':bytes.length}:{})}},res=>{
  const parts=[];let size=0;res.on('data',part=>{size+=part.length;if(size>256*1024)res.destroy(Error('Bounded fixture response exceeded'));else parts.push(part);});
  res.on('end',()=>{try{resolve({status:res.statusCode,headers:res.headers,body:JSON.parse(Buffer.concat(parts))});}catch(error){reject(error);}});res.on('error',reject);
 });req.on('error',reject);req.setTimeout(3000,()=>req.destroy(Error('HTTP fixture timeout')));if(bytes)req.write(bytes);req.end();
});}
class Wire {
 constructor(cookie){this.cookie=cookie;this.messages=[];this.waiters=[];this.buffer=Buffer.alloc(0);this.upgraded=false;this.closed=false;}
 async open(){await new Promise((resolve,reject)=>{
  const key=crypto.randomBytes(16).toString('base64');this.expected=crypto.createHash('sha1').update(key+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64');
  this.socket=net.createConnection({host:'127.0.0.1',port},()=>this.socket.write(`GET /api/world/live HTTP/1.1\r\nHost: 127.0.0.1:${port}\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Version: 13\r\nSec-WebSocket-Key: ${key}\r\nCookie: ${this.cookie}\r\n\r\n`));
  const timer=setTimeout(()=>reject(Error('WebSocket upgrade timeout')),3000);
  this.onUpgrade=()=>{clearTimeout(timer);resolve();};this.socket.on('data',data=>{try{this.receive(data);}catch(error){reject(error);}});this.socket.on('error',reject);
  this.socket.on('close',()=>{this.closed=true;for(const w of this.waiters.splice(0)){clearTimeout(w.timer);w.reject(Error('Socket closed'));}});
 });clients.push(this);return this;}
 receive(data){this.buffer=Buffer.concat([this.buffer,data]);assert(this.buffer.length<1024*1024,'Bounded WebSocket buffer');
  if(!this.upgraded){const end=this.buffer.indexOf('\r\n\r\n');if(end<0)return;const head=this.buffer.subarray(0,end).toString();assert(head.startsWith('HTTP/1.1 101 '),head.split('\r\n')[0]);assert(head.includes('Sec-WebSocket-Accept: '+this.expected));this.buffer=this.buffer.subarray(end+4);this.upgraded=true;this.onUpgrade();}
  while(this.buffer.length>=2){let length=this.buffer[1]&127,at=2;const opcode=this.buffer[0]&15;assert(!(this.buffer[1]&128),'Server frame unexpectedly masked');
   if(length===126){if(this.buffer.length<4)return;length=this.buffer.readUInt16BE(2);at=4;}else if(length===127){if(this.buffer.length<10)return;length=Number(this.buffer.readBigUInt64BE(2));at=10;}
   assert(length<=256*1024,'Server fixture frame bound');if(this.buffer.length<at+length)return;const payload=this.buffer.subarray(at,at+length);this.buffer=this.buffer.subarray(at+length);
   if(opcode===8){this.socket.end();continue;}if(opcode===9){this.frame(payload,10);continue;}if(opcode!==1)continue;
   const value=JSON.parse(payload);this.messages.push(value);for(const w of [...this.waiters])if(w.test(value)){clearTimeout(w.timer);this.waiters.splice(this.waiters.indexOf(w),1);w.resolve(value);}
  }
 }
 frame(bytes,opcode=1){assert(bytes.length<65536);const mask=crypto.randomBytes(4),head=Buffer.alloc(bytes.length<126?6:8);head[0]=0x80|opcode;
  if(bytes.length<126)head[1]=0x80|bytes.length;else{head[1]=0xfe;head.writeUInt16BE(bytes.length,2);}mask.copy(head,head.length-4);const data=Buffer.from(bytes);for(let i=0;i<data.length;i++)data[i]^=mask[i&3];this.socket.write(Buffer.concat([head,data]));}
 send(value){this.frame(Buffer.from(JSON.stringify(value)));}
 wait(test,after=0){const found=this.messages.slice(after).find(test);if(found)return Promise.resolve(found);return new Promise((resolve,reject)=>{const w={test,resolve,reject,timer:setTimeout(()=>{this.waiters.splice(this.waiters.indexOf(w),1);reject(Error('Expected actual server packet did not arrive'));},3000)};this.waiters.push(w);});}
 async sync(value){const token=crypto.randomBytes(8).toString('hex'),at=this.messages.length;this.send(value);this.send({t:'ping',c:token});await this.wait(m=>m.t==='pong'&&m.c===token,at);}
 async close(){if(this.closed)return;this.frame(Buffer.from([3,232]),8);await new Promise(resolve=>{this.socket.once('close',resolve);setTimeout(()=>{this.socket.destroy();resolve();},1000).unref();});}
}
const foot=(x=100,y=100,z=20)=>({t:'me',walking:true,skin:7,x,y,z,heading:0,health:100,armour:0});
const drive=(vehicle,extra={})=>({t:'me',driving:true,walking:false,skin:7,vehicle:vehicle.id,car:vehicle.row[2],x:vehicle.row[3],y:vehicle.row[4],z:vehicle.row[5],heading:0,pitch:0,roll:0,health:1000,life:100,...extra});
function vehicle(id,extra={}){const value={id,row:[id,'Synthetic','420.6.1.0.',100,100,20,0,0,0,1000,'',null,null,null,null,null,0],...extra};game.vehicles.set(id,value);return value;}
async function actor(native=false,cookie=null){const auth=await request('/api/auth/me',cookie||'');same(auth.status,200,'Normal HTTP account response');cookie ||= auth.headers['set-cookie'][0].split(';')[0];const wire=await new Wire(cookie).open();
 wire.send({t:'hi',...(native?{nativeInventory:true,inventoryAck:1,couplingAck:1}:{b:'owned-fixture',c:{aidrive:1}})});const hello=await wire.wait(m=>m.t==='hello');const all=await wire.wait(m=>m.t==='all');await wire.sync(foot());return{wire,cookie,number:all.number,player:game.players.get(auth.body.id),hello};}
async function enter(actor,car,kind='enter'){const n=actor.wire.messages.length;actor.wire.send({t:kind,v:car.id});return(await actor.wire.wait(m=>m.t===kind&&m.v===car.id,n)).ok;}
const cars=async actor=>(await request('/api/world/cars',actor.cookie)).body.cars;
async function parked(actor,car,extra={}){await actor.wire.sync({...foot(103,100,20),vehicle:car.id,car:car.row[2],parked:{x:car.row[3],y:car.row[4],z:car.row[5],heading:0,pitch:0,roll:0,health:car.row[9],...extra}});}
async function main(){
 fs.mkdirSync(OUT,{recursive:true});for(const name of SOURCES)fs.copyFileSync(path.join(ROOT,name),path.join(fixture,name));
 const local=path.join(fixture,'local-only');fs.mkdirSync(path.join(local,'selfhost'),{recursive:true});fs.mkdirSync(path.join(local,'site/game/world'),{recursive:true});fs.mkdirSync(path.join(local,'site/game/native'),{recursive:true});
 fs.writeFileSync(path.join(local,'site/game/world/index.json'),'{}');fs.writeFileSync(path.join(local,'site/game/world/collision.json'),'{"cells":[]}');
 fs.writeFileSync(path.join(local,'selfhost/client-catalog.json'),'{"vehicles":[],"homes":[]}');fs.writeFileSync(path.join(local,'selfhost/weapon-catalog.json'),'{"items":[],"shops":[]}');
 const seats=n=>Array.from({length:n},(_,i)=>({at:[i%2,i<2?0:-1,0]}));
 fs.writeFileSync(path.join(local,'site/game/native/riders.json'),JSON.stringify({version:2,models:{420:{seats:seats(4)},8002:{seats:seats(1)},8003:{seats:[]}}}));
 game=require(path.join(fixture,'selfhost_backend.js'));server=http.createServer((req,res)=>game.http(req,res).catch(error=>{res.writeHead(500);res.end(JSON.stringify({error:error.message}));}));server.on('upgrade',(req,socket,head)=>game.upgrade(req,socket,head));
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));port=server.address().port;
 check(![8766,8780,8801,8803,8804,8805,8806].includes(port),'Ephemeral fixture collided with known live services');
 const a=await actor(),b=await actor(),native=await actor(true),observer=await actor();
 const peer=actor=>[...game.peers].find(p=>p.player===actor.player);
 const seated=(car,seat=1,extra={})=>({...foot(),driving:false,riding:car.id,seat,move:0,...extra});
 async function passenger(actor,car,seat,request=1){const at=actor.wire.messages.length;actor.wire.send({t:'enter',v:car.id,seat,passenger:true,request});const ack=await actor.wire.wait(m=>m.t==='enter'&&m.v===car.id&&m.seat===seat,at);same(ack.request,request,'Native seat request correlation lost');return ack.ok;}
 const taxi=vehicle('shared-taxi',{missionOwner:a.player});
 await scenario('browser implicit seat and native pending reservation share exact authority',async()=>{
  check(await enter(a,taxi),'Driver entry denied');await a.wire.sync(drive(taxi,{skin:undefined}));same(game.row(peer(a))[31],7,'Driver without redundant skin lost last accepted identity');
  await b.wire.sync(archivedSerializer?{t:'me',...archivedSerializer.passengers[0]}:seated(taxi));check(game.passengerClaim(peer(b))?.active,'Actual browser report did not acquire a passenger seat');
  same(game.row(peer(b))[34],[taxi.id,1],'Passenger riding row missing');same(game.row(peer(b))[35],null,'Passenger obtained parallel vehicle ownership');same(game.gameplayState(b.player).onFoot,false,'Wire walking flag incorrectly grants physical on-foot state');same(game.onFoot(peer(b)),false,'Active passenger is physically on foot');same(taxi.row[11],String(a.number),'Passenger replaced driver marker');
  check(!(await passenger(native,taxi,1,31)),'Occupied seat accepted twice');check(await passenger(native,taxi,2,32),'Free exact seat denied');
  await native.wire.sync(foot());check(game.passengerClaim(peer(native))&&!game.passengerClaim(peer(native)).active,'Pending foot animation cancelled seat');
  await native.wire.sync(archivedSerializer?{t:'me',...archivedSerializer.passengers[1]}:seated(taxi,2,{skin:2}));same(game.row(peer(native))[34],[taxi.id,2],'Native seat did not publish original riding shape');same(game.row(peer(native))[2],'s2','Native passenger skin lost');
  check(!(await enter(b,taxi)),'Passenger simultaneously acquired driver authority');
  await a.wire.sync(drive(taxi,{x:110,y:106,z:21,heading:.7,pitch:.2,roll:-.3,vx:4,vy:2,vz:1,speed:6,health:870}));
  const row=game.row(peer(b));same(row.slice(3,9),[110,106,21,.7,.2,-.3],'Passenger does not follow current accepted driver pose');same(row.slice(13,16),[4,2,1],'Passenger velocity does not follow driver');same(game.position(b.player).x,110,'Gameplay position remains at boarding site');
  await b.wire.sync(seated(taxi,1,{x:5000,y:5000,z:900,health:100,parked:{x:500,y:500,z:50,health:1000}}));same(game.row(peer(b)).slice(3,6),[110,106,21],'Passenger report became movement authority');same(taxi.row[9],870,'Passenger repaired driver vehicle');
  await b.wire.sync({t:'vmove',v:taxi.id,x:111,y:106,z:21,h:0,p:0,r:0,hp:1});same(taxi.row[9],870,'Passenger mutated unattended vehicle');
  await b.wire.sync({...drive(taxi),riding:taxi.id,seat:1,x:300,health:1});same(taxi.row[3],110,'Passenger stole drive authority');same(game.row(peer(b))[34],[taxi.id,1],'Rejected drive destroyed valid seat');
  await b.wire.sync(seated(taxi,1,{weapon:22,aim:.25,heading:1.2}));same(game.row(peer(b))[6],1.2,'Shared body orientation erased passenger world-space aim heading');same(taxi.row[6],.7,'Passenger aim rotated shared vehicle');
  await game.publishPlayerRows();await observer.wire.wait(m=>m.t==='cars'&&m.c.some(r=>r[0]===String(b.number)&&r[34]?.[0]===taxi.id));
 });
 await scenario('passenger exit cannot park the driver and driver departure preserves remaining seats',async()=>{
  await native.wire.sync({t:'exit',v:taxi.id,seat:2,parked:{x:999,y:999,z:20,health:1}});check(!game.passengerClaim(peer(native)),'Explicit passenger exit retained claim');same(taxi.row[3],110,'Passenger exit moved shared vehicle');same(taxi.row[11],String(a.number),'Passenger exit removed live driver');
  await native.wire.sync(foot(110,106,21));b.player.supplies.paint_can=1;assert.throws(()=>game.action(b.player,'supply.give',{item:'paint_can',number:native.number}),/Both players must stand on foot/);checks++;same(b.player.supplies.paint_can,1,'Seated transfer spent supplies');await a.wire.sync({t:'exit',v:taxi.id,x:112,y:107,z:21,h:.8,p:.1,r:.2,hp:800});await a.wire.sync(foot(114,107,21));
  same(taxi.row[11],null,'Driver exit did not park');same(game.row(peer(b))[34],[taxi.id,1],'Driver exit detached an actual passenger');same(game.row(peer(b)).slice(3,6),[112,107,21],'Passenger stayed on old driven ghost');same(game.row(peer(b)).slice(13,16),[0,0,0],'Parked passenger retains driving velocity');
  await b.wire.sync(foot(114,107,21));check(!game.passengerClaim(peer(b)),'Completed foot exit retained passenger authority');same(game.row(peer(b))[34],null,'Foot exit retains riding appearance');
 });
 await scenario('exact seat capacity, duplicate claims, cancellation and expiry',async()=>{
  await a.wire.sync(foot());await b.wire.sync(foot());await native.wire.sync(foot());const car=vehicle('seats');
  for(const seat of [0,-1,4,100,1.5,null]){const at=native.wire.messages.length;native.wire.send({t:'enter',v:car.id,seat,passenger:true});const ack=await native.wire.wait(m=>m.t==='enter'&&m.v===car.id,at);check(!ack.ok,'Invalid exact seat accepted '+seat);}
  const bike=vehicle('bicycle');bike.row[2]='8002';check(!(await passenger(native,bike,1,41)),'Single-seat bicycle invented passenger seat');const absent=vehicle('missing-model');absent.row[2]='8999';check(!(await passenger(native,absent,1,42)),'Missing metadata invented passenger capacity');
  const answers=await Promise.all([passenger(a,car,1,43),passenger(b,car,1,44)]);same(answers.filter(Boolean).length,1,'Two transports acquired one seat');const winner=answers[0]?a:b;await winner.wire.sync({t:'exit',v:car.id,seat:1});check(!game.passengerClaim(peer(winner)),'Pending cancellation retained seat');
  check(await passenger(native,car,1,45),'Cancelled seat did not free');offset+=12001;game.broadcastPositions();check(!game.passengerClaim(peer(native)),'Pending seat failed expiry');await b.wire.sync(foot());check(await passenger(b,car,1,46),'Expired seat blocked later guest');await b.wire.sync({t:'exit',v:car.id,seat:1});
  await native.wire.sync(foot(1000,1000,20));const mark=native.wire.messages.length;await native.wire.sync(seated(car));check(!game.passengerClaim(peer(native)),'Distant implicit browser acquired seat');check(native.wire.messages.slice(mark).some(m=>m.t==='tp'),'Denied implicit seat lacked original browser correction');
 });
 await scenario('disconnect, replacement, death, wreck and reconnect revoke exact seat incarnation',async()=>{
  const driver=await actor(),rider=await actor(),car=vehicle('disconnect-car');check(await enter(driver,car),'Disconnect setup driver denied');await driver.wire.sync(drive(car,{x:104}));await rider.wire.sync(seated(car));check(game.passengerClaim(peer(rider)),'Disconnect setup passenger denied');await driver.wire.close();same(car.row[11],null,'Disconnected driver retained marker');same(game.row(peer(rider))[34],[car.id,1],'Disconnected driver stranded a ghost passenger');
  const before=observer.wire.messages.length;await rider.wire.close();check(![...game.passengerClaims.values()].some(c=>c.vehicle===car),'Disconnected passenger retained seat');
  const reused=await actor(false,rider.cookie);check(!game.passengerClaim(peer(reused)),'Reconnect inherited former transport seat');
  await reused.wire.sync(seated(car));check(game.passengerClaim(peer(reused)),'Reconnected guest cannot normally acquire seat');const replacement=vehicle(car.id);game.broadcastPositions();check(!game.passengerClaim(peer(reused)),'Old incarnation seat survived replacement');same(replacement.row[11],null,'Old passenger changed replacement');
  await reused.wire.sync(foot());await reused.wire.sync(seated(replacement));await reused.wire.sync(seated(replacement,1,{health:0}));check(!game.passengerClaim(peer(reused)),'Dead passenger retained seat');
  const live=await actor(),wreck=vehicle('wreck');await live.wire.sync(seated(wreck));const mark=live.wire.messages.length;wreck.row[9]=0;game.broadcastPositions();check(!game.passengerClaim(peer(live)),'Wrecked vehicle retained passenger');await live.wire.wait(m=>m.t==='enter'&&m.ok===false&&m.seat===1,mark);check(true,'Wreck exact native seat revoke received');
  const removed=vehicle('removed');await live.wire.sync(foot());await live.wire.sync(seated(removed));game.removeOwnedVehicle(removed);check(!game.passengerClaim(peer(live)),'Deleted vehicle retained passenger');same(game.row(peer(live))[34],null,'Deleted vehicle leaves riding row');
 });
 same(hashes(),before,'Source changed during actual HTTP/WS seat fixture');
 fs.writeFileSync(path.join(OUT,'server-seats-report.json'),JSON.stringify({schema:1,passed:true,checks,scenarios,sourceSHA256:before,archivedSerializerReplayed:!!archivedSerializer,identities:{driver:a.number,browserPassenger:b.number,nativePassenger:native.number},observedWire:observer.wire.messages.filter(m=>['veh','spawned','vgone','gone','cars'].includes(m.t)),scope:'Real ephemeral loopbackHTTP/WebSocket; synthetic finite seats/world; no browser renderer/native runtime or retail accuracy claim.'},null,2)+'\n');console.log(`PASS real HTTP/WebSocket seats: ${checks} checks, ${scenarios.length} scenarios`);
}
main().catch(error=>{console.error(error.stack);process.exitCode=1;}).finally(async()=>{
 for(const client of clients)if(!client.closed)client.socket.destroy();if(server)await new Promise(resolve=>server.close(resolve));if(game){clearInterval(game.tick);clearInterval(game.projectileTimer);game.flushSync();}
 Date.now=realNow;for(const[key,value]of Object.entries(savedEnv))if(value===undefined)delete process.env[key];else process.env[key]=value;fs.rmSync(fixture,{recursive:true,force:true});
});
