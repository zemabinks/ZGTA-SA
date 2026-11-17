#!/usr/bin/env node
'use strict';
// Independent HTTP/WebSocket integration fixture. The world, accounts, cars
// and coupling anchors below are authored test data; no game assets are used.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const http=require('node:http'),net=require('node:net'),crypto=require('node:crypto');
const ROOT=__dirname,OUT=path.join(ROOT,'local-only/research/vehicle-presence');
const SOURCES=['selfhost_backend.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js','vehicle_coupling.js'];
const hashes=()=>Object.fromEntries(SOURCES.map(name=>[name,crypto.createHash('sha256').update(fs.readFileSync(path.join(ROOT,name))).digest('hex')]));
const before=hashes(),fixture=fs.mkdtempSync(path.join(require('node:os').tmpdir(),'zgta-presence-'));
let archivedSerializer=null;
if(process.argv.length>2){
 assert(process.argv.length===4&&process.argv[2]==='--archived-serializer','Expected --archived-serializer REPORT');
 const file=path.resolve(process.argv[3]),bytes=fs.readFileSync(file);assert(bytes.length<65536,'Serializer fixture report bound');
 archivedSerializer=JSON.parse(bytes);assert(archivedSerializer.schema===1&&/^[a-f0-9]{64}$/.test(archivedSerializer.archivedFactory19737SHA256),'Actual serializer provenance missing');
 assert(archivedSerializer.localReport?.driving===true&&!Object.hasOwn(archivedSerializer.localReport,'vehicle'),'Expected original unbound local report');
 assert(archivedSerializer.registryReport?.vehicle==='serializer-logical','Expected original explicit registry report');
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
function vehicle(id,extra={}){const value={id,row:[id,'Synthetic','8001.4.5.0.',100,100,20,0,0,0,1000,'',null,null,null,null,null,0],...extra};game.vehicles.set(id,value);return value;}
async function actor(native=false,cookie=null){const auth=await request('/api/auth/me',cookie||'');same(auth.status,200,'Normal HTTP account response');cookie ||= auth.headers['set-cookie'][0].split(';')[0];const wire=await new Wire(cookie).open();
 wire.send({t:'hi',...(native?{nativeInventory:true,inventoryAck:1,couplingAck:1}:{b:'owned-fixture',c:{aidrive:1}})});const hello=await wire.wait(m=>m.t==='hello');const all=await wire.wait(m=>m.t==='all');await wire.sync(foot());return{wire,cookie,number:all.number,player:game.players.get(auth.body.id),hello};}
async function enter(actor,car,kind='enter'){const n=actor.wire.messages.length;actor.wire.send({t:kind,v:car.id});return(await actor.wire.wait(m=>m.t===kind&&m.v===car.id,n)).ok;}
const cars=async actor=>(await request('/api/world/cars',actor.cookie)).body.cars;
async function parked(actor,car,extra={}){await actor.wire.sync({...foot(103,100,20),vehicle:car.id,car:car.row[2],parked:{x:car.row[3],y:car.row[4],z:car.row[5],heading:0,pitch:0,roll:0,health:car.row[9],...extra}});}
async function main(){
 fs.mkdirSync(OUT,{recursive:true});for(const name of SOURCES)fs.copyFileSync(path.join(ROOT,name),path.join(fixture,name));
 const local=path.join(fixture,'local-only');fs.mkdirSync(path.join(local,'selfhost'),{recursive:true});fs.mkdirSync(path.join(local,'site/game/world'),{recursive:true});
 fs.writeFileSync(path.join(local,'site/game/world/index.json'),'{"water":[],"tiles":[]}');fs.writeFileSync(path.join(local,'site/game/world/collision.json'),'{"cells":[]}');
 fs.writeFileSync(path.join(local,'selfhost/client-catalog.json'),'{"vehicles":[],"homes":[]}');fs.writeFileSync(path.join(local,'selfhost/weapon-catalog.json'),'{"items":[],"shops":[]}');
 const definition=(id,kind,extra={})=>({id,kind,minimum:[-1,-2,-1],frontAnchor:[0,.5,-2],rearAnchor:null,trailerAnchor:null,targets:[],...extra});
 fs.writeFileSync(path.join(local,'selfhost/coupling-catalog.json'),JSON.stringify({version:1,models:{8001:definition(8001,'car',{rearAnchor:[0,.5,3],targets:[8002]}),8002:definition(8002,'trailer',{trailerAnchor:[0,.5,-2]})}}));
 game=require(path.join(fixture,'selfhost_backend.js'));server=http.createServer((req,res)=>game.http(req,res).catch(error=>{res.writeHead(500);res.end(JSON.stringify({error:error.message}));}));server.on('upgrade',(req,socket,head)=>game.upgrade(req,socket,head));
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));port=server.address().port;check(![8803,8804,8805].includes(port),'Disposable fixture used a live QA port');
 const a=await actor(true),b=await actor(),observer=await actor();
 await scenario('pending, competing claims, cancellation and expiry do not change parked appearance',async()=>{
  const car=vehicle('claim-test');check(await enter(a,car),'First real enter denied');check(!(await enter(b,car)),'Competing real enter accepted');same((await cars(observer)).find(v=>v[0]===car.id)[11],null,'Pending entry changed driver marker');
  await a.wire.sync({t:'exit',v:car.id});check(await enter(b,car,'jack'),'Cancelled parked claim did not release');await b.wire.sync({t:'exit',v:car.id});
  check(await enter(a,car),'Native cancellation claim denied');await parked(a,car,{x:105});check(!game.vehicleClaim(car),'Native final parked report retained pending reservation');same(car.row[3],100,'Cancelled entry moved an undriven car');
  check(await enter(a,car),'New pending claim denied');offset+=12001;game.broadcastPositions();await a.wire.sync(drive(car));same(car.row[11],null,'Expired first drive hid a car');
  await b.wire.sync(foot());check(await enter(b,car),'Expired claim blocked next entrant');await b.wire.sync({t:'exit',v:car.id});
  const near=vehicle('simultaneous');await a.wire.sync(foot());const answer=await Promise.all([enter(a,near),enter(b,near)]);same(answer.filter(Boolean).length,1,'Two simultaneous enters acquired one car');await(answer[0]?a:b).wire.sync({t:'exit',v:near.id});
 });
 await scenario('browser stand/get-in parked snapshots retain bounded pending authority',async()=>{
  // The real browser controller is parked while stand() prepares its get-in
  // animation; own() legitimately sends that snapshot in ordinary foot rows.
  // These default bytes are authored. Optional private archive execution below
  // supplies its unchanged getter+serializer output for the same exact shape.
  const car=vehicle('serializer-logical');car.row[2]='420.6.1.0.';
  await b.wire.sync(foot(98,100,20));check(await enter(b,car),'Browser ordinary entry denied');
  const claim=game.vehicleClaim(car),at=observer.wire.messages.length;
  const entering=archivedSerializer?.enteringReport || {...foot(98,100,20),car:car.row[2],vehicle:car.id,
    parked:{x:100,y:100,z:20,heading:0,pitch:0,roll:0,health:1000,damage:''}};
  check(entering.walking===true&&entering.driving!==true&&entering.vehicle===car.id&&entering.car===car.row[2]&&entering.parked,'Get-in fixture lacks the original foot/parked shape');
  await b.wire.sync({t:'me',...entering});const accepted=[...game.peers].find(peer=>peer.player===b.player)?.state;check(accepted?.walking===true&&accepted.vehicle===car.id&&accepted.parked?.x===entering.parked.x,'Actual get-in foot report was not processed by backend');check(game.vehicleClaim(car)===claim,'Browser stand snapshot cancelled pending entry');
  same(car.row[11],null,'Pending browser stand snapshot prematurely published a driver');same(car.row.slice(3,6),[100,100,20],'Pending snapshot changed parked body pose');
  check(!(await enter(a,car)),'Browser get-in snapshot released its exclusive reservation');
  // Repeated foot snapshots cannot extend the initial twelve-second lease.
  const until=claim.until;await b.wire.sync({t:'me',...entering});same(claim.until,until,'Browser foot/get-in report extended pending lease');
  await b.wire.sync(archivedSerializer?.drivingAfterEnteringReport ? {t:'me',...archivedSerializer.drivingAfterEnteringReport} : drive(car,{skin:7,x:101,health:1000}));
  await observer.wire.wait(m=>m.t==='cars'&&m.c.some(r=>r[0]===String(b.number)&&r[35]===car.id&&r[2]===car.row[2]),at);
  same(car.row[11],String(b.number),'Browser first drive did not publish its player ID');
  const packets=observer.wire.messages.slice(at),occupied=packets.findIndex(m=>m.t==='veh'&&m.v[0]===car.id&&m.v[11]===String(b.number)),driven=packets.findIndex(m=>m.t==='cars'&&m.c.some(r=>r[0]===String(b.number)&&r[35]===car.id&&r[2]===car.row[2]));
  check(occupied>=0&&driven>occupied,'Browser occupied registry marker did not precede driving actor');
  same((await cars(observer)).find(v=>v[0]===car.id)[11],String(b.number),'HTTP lost browser occupied marker');
  await parked(b,car,{x:102});same(car.row[11],null,'Completed browser exit did not restore parked representation');check(!game.vehicleClaim(car),'Completed browser exit retained driver authority');
  await b.wire.sync(foot(98,100,20));check(await enter(b,car),'Browser explicit-cancel setup denied');await b.wire.sync({t:'me',...entering});await b.wire.sync({t:'exit',v:car.id});check(!game.vehicleClaim(car),'Explicit browser cancel retained pending authority');
  await b.wire.sync(drive(car));same(car.row[11],null,'Late drive acquired explicitly cancelled browser entry');
  await b.wire.sync(foot(98,100,20));check(await enter(b,car),'Browser expiry setup denied');await b.wire.sync({t:'me',...entering});offset+=12001;game.broadcastPositions();await b.wire.sync(drive(car));same(car.row[11],null,'Expired browser stand/get-in acquired driver authority');
  await a.wire.sync(foot(98,100,20));check(await enter(a,car),'Expired browser stand/get-in blocked next native driver');await a.wire.sync({t:'exit',v:car.id});
 });
 await scenario('only the claimed first valid drive publishes driver slot11 before its driving row',async()=>{
  const car=vehicle('publication');await a.wire.sync(foot());await b.wire.sync(foot());
  for(const bad of [{car:'9001'}, {x:null}, {x:6001}, {health:null}, {pitch:'zero'}]){
   await b.wire.sync({...drive(car),vehicle:undefined,car:'420',...bad});same(game.row([...game.peers].find(p=>p.player===b.player))[2],'s7','Malformed local free-play report replaced the accepted foot state');
  }
  await b.wire.sync({...drive(car),vehicle:undefined,car:'420.6.1.0.'});same(car.row[11],null,'A legitimate local free-play car acquired unrelated logical identity');same(game.row([...game.peers].find(p=>p.player===b.player))[35],null,'Local free-play actor received a logical vehicle ID');await b.wire.sync(foot());
  if(archivedSerializer){
   const logical=vehicle('serializer-logical');logical.row[2]='420.6.1.0.';
   await b.wire.sync({t:'me',...archivedSerializer.localReport});same(logical.row[11],null,'Actual original local serializer hid a registry car');same(game.row([...game.peers].find(p=>p.player===b.player))[35],null,'Actual original local serializer acquired a logical ID');
   await b.wire.sync({t:'me',...archivedSerializer.registryReport});same(logical.row[11],null,'Actual original registry report acquired a car without entry');
   same(game.row([...game.peers].find(p=>p.player===b.player))[35],null,'Forged explicit registry report replaced accepted local state');await b.wire.sync(foot());
  }
  await b.wire.sync(drive(car));same(car.row[11],null,'Forged unclaimed drive changed appearance');
  check(await enter(a,car),'Valid claim denied');await a.wire.sync(drive(car,{car:'8999.0'}));same(car.row[11],null,'Wrong car token acquired claim');
  await a.wire.sync(drive(car,{x:400}));same(car.row[3],100,'Far first pose acquired claim');
  const at=observer.wire.messages.length;await a.wire.sync(drive(car,{x:101,health:800,damage:'fixture-damage',w:2100}));
  await observer.wire.wait(m=>m.t==='cars'&&m.c.some(r=>r[0]===String(a.number)&&r[2]===car.row[2]),at);
  const messages=observer.wire.messages.slice(at),marker=messages.findIndex(m=>m.t==='veh'&&m.v[0]===car.id&&m.v[11]===String(a.number)),body=messages.findIndex(m=>m.t==='cars'&&m.c.some(r=>r[0]===String(a.number)&&r[2]===car.row[2]));
  check(marker>=0&&body>marker,'First driving publication order was not occupied row then driving body');same(car.row[11],String(a.number),'Confirmed driver marker is not a string player ID');
  const late=await actor();const all=late.wire.messages.find(m=>m.t==='all');same(all.vehicles.find(v=>v[0]===car.id)[11],String(a.number),'Late join lost logical occupied row');check(all.cars.some(r=>r[0]===String(a.number)&&r[35]===car.id),'Late join lost matching driver/vehicle identity');
  const api=(await cars(late)).find(v=>v[0]===car.id);same(api[11],String(a.number),'Normal HTTP snapshot omitted occupied identity');
  await b.wire.sync({t:'vmove',v:car.id,x:102,y:100,z:20,h:0,p:0,r:0,hp:1});same(car.row[9],800,'Unattended writer modified an occupied car');
  check(!observer.wire.messages.slice(at).some(m=>m.t==='vgone'&&m.id===car.id),'Occupancy used destructive vgone');
  const releaseAt=observer.wire.messages.length;await a.wire.sync({t:'exit',v:car.id,x:104,y:102,z:20,h:.7,p:.1,r:-.2,hp:900,d:'',w:2300});same(car.row[11],String(a.number),'Exit intent prematurely removed driving body');
  await a.wire.sync(foot(106,103,20));await observer.wire.wait(m=>m.t==='veh'&&m.v[0]===car.id&&m.v[11]===null,releaseAt);
  const released=observer.wire.messages.slice(releaseAt),footIndex=released.findIndex(m=>m.t==='cars'&&m.c.some(r=>r[0]===String(a.number)&&r[2]==='s7')),parkIndex=released.findIndex(m=>m.t==='veh'&&m.v[0]===car.id&&m.v[11]===null);
  check(footIndex>=0&&parkIndex>footIndex,'Release restored parked body before replacing driving row');same(car.row.slice(3,12),[104,102,20,.7,.1,-.2,800,'fixture-damage',null],'Same-ID final pose/condition differs or exit repaired damage');same(car.row[16],2300,'Final working state was lost');
 });
 await scenario('mission access, owner persistence and stale incarnation reports',async()=>{
  const mission=vehicle('reserved',{missionOwner:a.player});await a.wire.sync(foot());await b.wire.sync(foot());check(!(await enter(b,mission)),'Foreign mission claim accepted');await b.wire.sync(drive(mission,{health:1}));same(mission.row[9],1000,'Foreign mission report changed condition');
  const slot=a.player.garage.length;a.player.cars.push(410);a.player.garage.push({position:[100,100,20,0],health:1000,damage:'',active:true});const owned=vehicle('owned',{owner:a.player,slot});
  check(await enter(b,owned),'Unlocked owned car cannot be entered under existing policy');await b.wire.sync(drive(owned,{x:102,health:700,damage:'owned-damage'}));await parked(b,owned,{x:104,heading:.2,w:1500});same(a.player.garage[slot].position,[104,100,20,.2],'Authorized driver did not save owner garage pose');same(a.player.garage[slot].health,700,'Owner garage condition lost');
  await b.wire.sync(foot());check(await enter(b,owned),'Owner persistence re-entry denied');await b.wire.sync(drive(owned,{x:105}));const savedAt=owned.lastGarageSave;offset+=100;await b.wire.sync(drive(owned,{x:106}));same(owned.lastGarageSave,savedAt,'Driving position saves were not throttled');await parked(b,owned,{x:107});check(owned.lastGarageSave>savedAt,'Final parked position did not force persistence');
  check(await enter(a,mission),'Mission owner denied');await a.wire.sync(drive(mission));const replacement=vehicle(mission.id,{missionOwner:a.player});await a.wire.sync(drive(mission,{x:500,health:1}));same(replacement.row.slice(3,12),[100,100,20,0,0,0,1000,'',null],'Old incarnation altered replacement');
  await a.wire.sync(foot());check(await enter(a,replacement),'Fresh replacement claim denied');await a.wire.sync({t:'exit',v:replacement.id});
 });
 await scenario('disconnect, death and real removal release exactly one logical vehicle',async()=>{
  const departing=await actor(),car=vehicle('disconnect');check(await enter(departing,car),'Disconnect fixture claim denied');await departing.wire.sync(drive(car,{x:105,health:650,damage:'disconnect-damage',w:2000}));const at=observer.wire.messages.length;await departing.wire.close();await observer.wire.wait(m=>m.t==='veh'&&m.v[0]===car.id&&m.v[11]===null,at);
  const list=observer.wire.messages.slice(at);check(list.findIndex(m=>m.t==='gone'&&m.id===String(departing.number))<list.findIndex(m=>m.t==='veh'&&m.v[0]===car.id),'Disconnect restored a car before retiring driver');same(car.row.slice(3,6),[105,100,20],'Disconnect lost final accepted body pose');same(car.row[9],650,'Disconnect lost final health');
  const dead=await actor(),wreck=vehicle('death');check(await enter(dead,wreck),'Death fixture claim denied');await dead.wire.sync(drive(wreck));await dead.wire.sync(drive(wreck,{life:0}));same(wreck.row[11],null,'Dead driver retained occupancy');check(!game.vehicleClaim(wreck),'Dead claim retained authority');
  const stale=await actor(),staleCar=vehicle('stale-driver');check(await enter(stale,staleCar),'Stale driver setup denied');await stale.wire.sync(drive(staleCar,{x:102}));offset+=10001;game.broadcastPositions();same(staleCar.row[11],null,'Inactive driver retained occupancy');check(!game.vehicleClaim(staleCar),'Inactive driver retained authority');same(staleCar.row[3],102,'Inactive release lost last accepted body pose');
  await a.wire.sync(foot());const gone=vehicle('despawn');check(await enter(a,gone),'Despawn fixture claim denied');await a.wire.sync(drive(gone));game.removeOwnedVehicle(gone);await a.wire.sync(drive(gone,{x:200}));check(!game.vehicles.has(gone.id)&&!game.vehicleClaims.has(gone.id),'Removed ID retained vehicle/claim');
  await a.wire.sync(foot());const ownedSlot=a.player.garage.length;a.player.cars.push(410);a.player.garage.push({position:[100,100,20,0],health:1000,damage:'',active:true});const first=game.addOwnedVehicle(a.player,ownedSlot);game.removeOwnedVehicle(first);const second=game.addOwnedVehicle(a.player,ownedSlot);check(first.id!==second.id,'Owner-slot reuse recycled a browser tombstone ID');
 });
 await scenario('driver marker retains coupling identity and final linked body state',async()=>{
  await a.wire.sync(foot());const root=vehicle('tractor'),trailer=vehicle('trailer');trailer.row[2]='8002.0';trailer.row[4]=95;
  check(await enter(a,root),'Coupling root claim denied');await a.wire.sync(drive(root));a.wire.send({t:'hitch',v:root.id,tr:trailer.id,kind:'trailer',c:a.hello.inventoryConnection,s:1});const ack=await a.wire.wait(m=>m.t==='couplings'&&m.ack?.sequence===1);check(ack.ack.accepted,'Existing coupling authority rejected confirmed driver');same(ack.state.links,[{parent:'tractor',trailer:'trailer',kind:'trailer'}],'Coupling identity changed');
  await a.wire.sync({t:'vmove',v:trailer.id,x:100,y:95,z:20,h:.1,p:.2,r:.3,hp:750,d:'trailer-condition',w:500});same(trailer.row[9],750,'Linked body condition lost');same(root.row[11],String(a.number),'Coupling removed root driver marker');
  await parked(a,root,{x:101});same(game.coupling.snapshot().links,[],'Exit retained driver-owned link');same(trailer.row.slice(6,11),[.1,.2,.3,750,'trailer-condition'],'Exit discarded linked final body state');check(game.vehicles.get(root.id)===root&&game.vehicles.get(trailer.id)===trailer,'Occupancy transition destroyed coupling vehicle identities');
 });
 same(hashes(),before,'Source changed during integration fixture');
 const observedWire=observer.wire.messages.filter(m=>['veh','spawned','vgone','gone','cars'].includes(m.t));
 fs.writeFileSync(path.join(OUT,'server-report.json'),JSON.stringify({passed:true,checks,scenarios,sourceSHA256:before,observedWire,archivedSerializerReplayed:!!archivedSerializer,archivedGetInReplayed:!!archivedSerializer?.enteringReport,...(archivedSerializer?{archivedFactory19737SHA256:archivedSerializer.archivedFactory19737SHA256}:{}),listener:'Ephemeral127.0.0.1only;stoppedinfinally',originalAssets:false,limits:'RealHTTP/WebSocketandserverauthority;notGPU/retailphysicsverification'},null,2)+'\n');
 console.log(`PASS real HTTP/WebSocket vehicle presence: ${checks} checks, ${scenarios.length} scenarios`);
}
main().catch(error=>{console.error(error.stack);process.exitCode=1;}).finally(async()=>{
 for(const client of clients)if(!client.closed)client.socket.destroy();
 if(server)await new Promise(resolve=>server.close(resolve));if(game){clearInterval(game.tick);clearInterval(game.projectileTimer);game.flushSync();}
 Date.now=realNow;for(const[key,value]of Object.entries(savedEnv))if(value===undefined)delete process.env[key];else process.env[key]=value;
 fs.rmSync(fixture,{recursive:true,force:true});
});
