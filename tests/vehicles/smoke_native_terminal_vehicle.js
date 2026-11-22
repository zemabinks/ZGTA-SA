#!/usr/bin/env node
'use strict';
// Independent HTTP/WebSocket integration fixture. The world, accounts, cars
// and coupling anchors below are authored test data; no game assets are used.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const http=require('node:http'),net=require('node:net'),crypto=require('node:crypto');
const ROOT=require('node:path').resolve(__dirname, '../..'),OUT=path.join(ROOT,'local-only/research/terminal-vehicle-110');
const SOURCES=['selfhost_backend.js','player_placement.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js','vehicle_coupling.js','tests/vehicles/smoke_native_terminal_vehicle.js'];
const hashes=()=>Object.fromEntries(SOURCES.map(name=>[name,crypto.createHash('sha256').update(fs.readFileSync(path.join(ROOT,name))).digest('hex')]));
const before=hashes(),fixture=fs.mkdtempSync(path.join(require('node:os').tmpdir(),'zgta-terminal-'));
const savedEnv=Object.fromEntries(['ZGTA_JOIN_CODE','ZGTA_JOIN_CODE_FILE','ZGTA_DISCORD_CLIENT_ID','ZGTA_DISCORD_CLIENT_SECRET'].map(k=>[k,process.env[k]]));
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
 wire.send({t:'hi',...(native?{nativeInventory:true,inventoryAck:1,healthAck:1,couplingAck:1}:{b:'owned-fixture',c:{aidrive:1}})});const hello=await wire.wait(m=>m.t==='hello');const all=await wire.wait(m=>m.t==='all');await wire.sync(foot());return{wire,cookie,number:all.number,player:game.players.get(auth.body.id),hello};}
async function enter(actor,car,kind='enter'){const n=actor.wire.messages.length;actor.wire.send({t:kind,v:car.id});return(await actor.wire.wait(m=>m.t===kind&&m.v===car.id,n)).ok;}
const cars=async actor=>(await request('/api/world/cars',actor.cookie)).body.cars;
async function parked(actor,car,extra={}){await actor.wire.sync({...foot(103,100,20),vehicle:car.id,car:car.row[2],parked:{x:car.row[3],y:car.row[4],z:car.row[5],heading:0,pitch:0,roll:0,health:car.row[9],...extra}});}
const peerOf=actor=>[...game.peers].find(peer=>peer.player===actor.player&&!peer.closed&&peer.inventoryConnection===actor.hello.inventoryConnection);
let serial=0;
async function boarded(health=800){
 const a=await actor(true),slot=a.player.garage.length;
 a.player.garage.push({position:[100,100,20,0],health:1000,damage:'',work:0});
 const car=vehicle('terminal-'+(++serial),{owner:a.player,slot,lastGarageSave:0});
 check(await enter(a,car),'Real nearby entry denied');await a.wire.sync(drive(car,{health}));
 const peer=peerOf(a);check(game.vehicleClaim(car)?.peer===peer&&game.vehicleClaim(car).driving,'No actual accepted driver claim');
 same(car.row[11],String(a.number),'Driver marker not established');same(a.player.garage[slot].health,health,'Driver hull was not persisted');
 return{a,car,peer,slot};
}
async function fatal(s,duplicate=false){
 const packet={t:'selfHealth',c:s.a.hello.inventoryConnection,s:1,kind:'hurt',damage:100};
 await s.a.wire.sync(packet);if(duplicate)await s.a.wire.sync(packet);
 same(s.a.player.health,0,'Fatal request did not kill actual player');same(s.a.player.deaths,1,'Fatal/duplicate changed death count');
 check(!game.vehicleClaim(s.car)&&s.car.row[11]===null,'Fatal retained driver/occupancy authority');
 return packet;
}
const release=(s,extra={},outer={})=>({...foot(105,100,20),health:0,vehicle:s.car.id,car:s.car.row[2],
 parked:{x:103,y:100,z:20,heading:.1,pitch:.2,roll:.3,health:0,damage:'wrecked',w:123,...extra},...outer});
async function final(s,extra={},outer={}){await s.a.wire.sync(release(s,extra,outer));}
function unchangedHull(s,health=800){same(s.car.row[9],health,'Rejected report changed registry hull');same(s.a.player.garage[s.slot].health,health,'Rejected report changed garage hull');check(!game.vehicleClaim(s.car),'Rejected report granted authority');same(s.car.row[11],null,'Rejected report restored occupancy');}
function noStandin(s){const row=game.row(s.peer);same(row?.[33]??null,null,'Denied explicit-ID report published an unauthorized parked stand-in');same(row?.[35]??null,null,'Denied explicit-ID report retained an unauthorized vehicle identity');}
async function main(){
 fs.mkdirSync(OUT,{recursive:true});for(const name of SOURCES){const destination=path.join(fixture,name);fs.mkdirSync(path.dirname(destination),{recursive:true});fs.copyFileSync(path.join(ROOT,name),destination);}
 const local=path.join(fixture,'local-only');fs.mkdirSync(path.join(local,'selfhost'),{recursive:true});fs.mkdirSync(path.join(local,'site/game/world'),{recursive:true});fs.mkdirSync(path.join(local,'site/game/native'),{recursive:true});
 fs.writeFileSync(path.join(local,'site/game/world/index.json'),'{"water":[],"tiles":[]}');fs.writeFileSync(path.join(local,'site/game/world/collision.json'),'{"cells":[]}');
 fs.writeFileSync(path.join(local,'site/game/native/riders.json'),JSON.stringify({version:2,models:{8001:{seats:[{at:[0,0,0]},{at:[1,0,0]}]}}}));
 fs.writeFileSync(path.join(local,'selfhost/client-catalog.json'),'{"vehicles":[],"homes":[]}');fs.writeFileSync(path.join(local,'selfhost/weapon-catalog.json'),'{"items":[],"shops":[]}');
 game=require(path.join(fixture,'selfhost_backend.js'));clearInterval(game.tick);clearInterval(game.projectileTimer);
 server=http.createServer((req,res)=>game.http(req,res).catch(error=>{res.writeHead(500);res.end(JSON.stringify({error:error.message}));}));server.on('upgrade',(req,socket,head)=>game.upgrade(req,socket,head));
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));port=server.address().port;
 check(![8803,8804,8805,8806,8807,8808,8809].includes(port),'Fixture selected an existing QA port');
 await scenario('received driver and parked condition agree with the authoritative registry',async()=>{
  const s=await boarded(645),damage='3434012122110101201';
  await s.a.wire.sync(drive(s.car,{health:645,damage}));
  await s.a.wire.sync(drive(s.car,{health:900,damage:''}));
  const observer=await actor(false),baseline=observer.wire.messages.find(m=>m.t==='all');
  const driving=baseline.cars.find(row=>row[0]===String(s.a.number));
  same(driving?.slice(18,20),[645,damage],'Actual observer baseline restored stale driver condition');
  same(baseline.vehicles.find(row=>row[0]===s.car.id)?.slice(9,11),[645,damage],'Received baseline hulls disagree');
  const at=observer.wire.messages.length;
  await parked(s.a,s.car,{health:900,damage:''});
  const update=await observer.wire.wait(m=>m.t==='cars'&&m.c.some(row=>row[0]===String(s.a.number)&&row[33]),at);
  const released=update.c.find(row=>row[0]===String(s.a.number));
  same(released[33].slice(7,9),[645,damage],'Actual observer received a repaired parked stand-in');
  same(released[35],s.car.id,'Received release lost registered vehicle identity');
  const hull=await observer.wire.wait(m=>m.t==='veh'&&m.v[0]===s.car.id,at);
  same(hull.v.slice(9,11),[645,damage],'Actual observer parked hull disagrees with its actor');
  await s.a.wire.sync(foot());
 });
 await scenario('fatal completion cannot clear previously accepted vehicle appearance',async()=>{
  const s=await boarded(645),damage='3434012122110101201';
  await s.a.wire.sync(drive(s.car,{health:645,damage}));await fatal(s);await final(s,{damage:''});
  same(s.car.row.slice(9,11),[0,damage],'Fatal completion discarded authoritative appearance');
  same(game.row(s.peer)[33].slice(7,9),[0,damage],'Fatal parked stand-in discarded authoritative appearance');
 });
 await scenario('fatal before parked completion persists exact former driver hull once',async()=>{
  const s=await boarded();await fatal(s);check(game.terminalVehicleReports.has(s.peer),'No bounded terminal completion');await final(s);
  same(s.car.row.slice(3,11),[103,100,20,.1,.2,.3,0,'wrecked'],'Final body state mixed with foot or lost');same(s.a.player.garage[s.slot].health,0,'Fatal release lost garage hull');
  same(s.peer.state.x,105,'Foot pose replaced by parked pose');same(game.row(s.peer)[33][7],0,'Authorized terminal stand-in lost wreck hull');
  check(!game.terminalVehicleReports.has(s.peer)&&!game.vehicleClaim(s.car)&&s.car.row[11]===null,'Completion retained occupancy/claim');
  await s.a.wire.sync({...foot(105,100,20),health:0});noStandin(s);check(game.vehicles.get(s.car.id)===s.car&&s.car.row[9]===0,'Repeated ordinary native foot lost sole parked registry identity');
  await final(s,{x:104,health:1000});same(s.car.row[3],103,'Completion replay moved body');same(s.car.row[9],0,'Completion replay repaired wreck');noStandin(s);
 });
 await scenario('parked completion before fatal is unchanged and health stays authoritative',async()=>{
  const s=await boarded();await final(s);same(s.car.row[9],0,'Live exit lost wreck hull');same(s.a.player.health,100,'State packet manufactured fatal health');
  await fatal(s);same(s.car.row[9],0,'Fatal repaired completed wreck');same(s.a.player.garage[s.slot].health,0,'Fatal repaired garage hull');check(!game.terminalVehicleReports.has(s.peer),'Completed exit retained terminal authority');
 });
 await scenario('duplicate fatal and queued rejected driver frames do not lose final hull',async()=>{
  const s=await boarded();await fatal(s,true);await s.a.wire.sync(drive(s.car,{x:101,health:0,life:0}));
  check(!game.vehicleClaim(s.car)&&game.row(s.peer)===null,'Queued dead drive revived a driving actor');check(game.terminalVehicleReports.has(s.peer),'Queued rejected drive consumed final release');
  await final(s);same(s.car.row[9],0,'Queued frame lost final hull');same(s.a.player.deaths,1,'Queued frame duplicated fatal');
 });
 for(const [name,mutation] of [['nonfinite pose',{x:null}],['invalid pose type',{y:'100'}],['far pose',{x:117}],['repair',{health:801}],['negative hull',{health:-1}],['oversize hull',{health:1001}],['oversize damage',{damage:'x'.repeat(513)}]])
  await scenario('reject terminal '+name,async()=>{const s=await boarded();await fatal(s);await final(s,mutation);unchangedHull(s);noStandin(s);check(!game.terminalVehicleReports.has(s.peer),'Malformed final report retained retry authority');});
 await scenario('liveness deadline does not extend and ordinary foot consumes completion',async()=>{
  const s=await boarded();await fatal(s);const until=game.terminalVehicleReports.get(s.peer).until;offset+=5000;await s.a.wire.sync({t:'ping'});same(game.terminalVehicleReports.get(s.peer).until,until,'Ping extended old driver deadline');
  offset+=5001;game.broadcastPositions();await final(s);unchangedHull(s);noStandin(s);
  const t=await boarded();await fatal(t);await t.a.wire.sync({...foot(),health:0});check(!game.terminalVehicleReports.has(t.peer),'Ordinary foot retained terminal completion');await final(t);unchangedHull(t);noStandin(t);
 });
 await scenario('new real driver epoch invalidates old completion even with identical body',async()=>{
  const s=await boarded();await fatal(s);const b=await actor(true);check(await enter(b,s.car),'New driver could not claim released healthy body');await b.wire.sync(drive(s.car,{health:800}));await parked(b,s.car,{health:800});
  check(!game.terminalVehicleReports.has(s.peer),'New driver retained old completion');await final(s);unchangedHull(s);noStandin(s);
 });
 await scenario('new real passenger prevents old dead driver changing its body',async()=>{
  const s=await boarded();await fatal(s);const b=await actor(true),at=b.wire.messages.length;b.wire.send({t:'enter',v:s.car.id,seat:1,passenger:true});
  const ack=await b.wire.wait(m=>m.t==='enter'&&m.v===s.car.id&&m.seat===1,at);check(ack.ok,'New passenger entry denied');await b.wire.sync({...foot(),riding:s.car.id,seat:1});
  check(!game.terminalVehicleReports.has(s.peer),'Passenger reservation retained old completion');await final(s);unchangedHull(s);noStandin(s);check(game.passengerClaim(peerOf(b))?.active,'Old completion removed new passenger');
 });
 await scenario('disconnect/reconnect cannot reuse former transport completion',async()=>{
  const s=await boarded();await fatal(s);await s.a.wire.close();const end=realNow()+3000;while(game.peers.has(s.peer)&&realNow()<end)await new Promise(resolve=>setTimeout(resolve,5));
  check(!game.peers.has(s.peer)&&!game.terminalVehicleReports.has(s.peer),'Disconnect retained completion');const b=await actor(true,s.a.cookie);check(b.hello.inventoryConnection!==s.a.hello.inventoryConnection,'Reconnect reused health capability');
  await b.wire.sync(release(s));unchangedHull(s);same(game.row(peerOf(b))?.[33]??null,null,'Reconnect published old parked stand-in');
 });
 await scenario('same-ID replacement, concurrent body change and respawn invalidate completion',async()=>{
  const s=await boarded();await fatal(s);check(game.deleteVehicle(s.car.id),'Fixture body removal failed');const replacement=vehicle(s.car.id);await final(s);same(replacement.row[9],1000,'Old completion changed replacement body');check(!game.terminalVehicleReports.has(s.peer),'Removed incarnation retained completion');
  const t=await boarded();await fatal(t);t.car.row[3]=101;await final(t);unchangedHull(t);same(t.car.row[3],101,'Stale completion overwrote a changed body');noStandin(t);
  const u=await boarded();await fatal(u);offset+=2001;await u.a.wire.sync({t:'selfHealth',c:u.a.hello.inventoryConnection,s:2,kind:'respawn',damage:0});same(u.a.player.health,100,'Normal acknowledged respawn failed');await final(u);unchangedHull(u);same(u.a.player.health,100,'Stale final report killed respawned actor');noStandin(u);
 });
 await scenario('unclaimed and passenger-only reporters cannot acquire final driver authority',async()=>{
  const a=await actor(true),slot=a.player.garage.length;a.player.garage.push({position:[100,100,20,0],health:1000,damage:'',work:0});const car=vehicle('unclaimed',{owner:a.player,slot});const s={a,car,peer:peerOf(a),slot};
  await a.wire.sync(drive(car));check(!game.vehicleClaim(car),'Unclaimed direct drive was accepted');await fatal(s);check(!game.terminalVehicleReports.has(s.peer),'Unclaimed driver gained completion');await final(s);unchangedHull(s,1000);noStandin(s);
  const p=await actor(true),car2=vehicle('passenger-only'),at=p.wire.messages.length;p.wire.send({t:'enter',v:car2.id,seat:1,passenger:true});check((await p.wire.wait(m=>m.t==='enter'&&m.v===car2.id&&m.seat===1,at)).ok,'Passenger fixture setup failed');await p.wire.sync({...foot(),riding:car2.id,seat:1});
  const ps={a:p,car:car2,peer:peerOf(p)};await fatal(ps);check(!game.terminalVehicleReports.has(ps.peer),'Passenger received driver completion');await final(ps);same(car2.row[9],1000,'Passenger-only final report changed hull');noStandin(ps);
 });
 await scenario('legitimate pending browser and ID-omitted free-play stand-ins remain supported',async()=>{
  const a=await actor(),car=vehicle('pending-browser');check(await enter(a,car),'Pending browser enter denied');await parked(a,car,{health:1000});check(game.vehicleClaim(car)&&!game.vehicleClaim(car).driving,'Browser stand snapshot cancelled pending entry');same(game.row([...game.peers].find(p=>p.player===a.player))[33][0],car.row[2],'Authorized pending browser stand-in was removed');
  const b=await actor();await b.wire.sync({...foot(),car:'420.0.0.0.',parked:{x:100,y:100,z:20,heading:0,pitch:0,roll:0,health:700,damage:''}});same(game.row([...game.peers].find(p=>p.player===b.player))[33][7],700,'ID-omitted local free-play stand-in changed');
 });
 same(hashes(),before,'Source changed during terminal regression');
 fs.writeFileSync(path.join(OUT,'report.json'),JSON.stringify({passed:true,checks,scenarios,sourceUnchanged:true,sourceSHA256:before,scope:'Actual ephemeral HTTP/WebSocket peers and production backend; authored models/poses; no original assets, rendered game, retail physics or production listener'},null,2)+'\n');
 console.log(`PASS terminal vehicle authority: ${checks} checks, ${scenarios.length} scenarios`);
}
main().catch(error=>{fs.mkdirSync(OUT,{recursive:true});fs.writeFileSync(path.join(OUT,'failed-'+realNow()+'.json'),JSON.stringify({passed:false,checks,scenarios,sourceUnchanged:JSON.stringify(hashes())===JSON.stringify(before),sourceSHA256:before,error:error.stack},null,2)+'\n');console.error(error.stack);process.exitCode=1;}).finally(async()=>{
 for(const client of clients)if(!client.closed)client.socket.destroy();
 if(server)await new Promise(resolve=>server.close(resolve));if(game){clearInterval(game.tick);clearInterval(game.projectileTimer);game.flushSync();}
 Date.now=realNow;for(const[key,value]of Object.entries(savedEnv))if(value===undefined)delete process.env[key];else process.env[key]=value;
 fs.rmSync(fixture,{recursive:true,force:true});
});
