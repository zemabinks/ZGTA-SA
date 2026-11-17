#!/usr/bin/env node
'use strict';
// Independent HTTP/WebSocket integration fixture. The world, accounts, cars
// and coupling anchors below are authored test data; no game assets are used.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const http=require('node:http'),net=require('node:net'),crypto=require('node:crypto');
const ROOT=__dirname,OUT=path.join(ROOT,'local-only/research/vehicle-seats-native-107');
const SOURCES=['selfhost_backend.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js','vehicle_coupling.js'];
const hashes=()=>Object.fromEntries(SOURCES.map(name=>[name,crypto.createHash('sha256').update(fs.readFileSync(path.join(ROOT,name))).digest('hex')]));
const before=hashes(),fixture=fs.mkdtempSync(path.join(require('node:os').tmpdir(),'zgta-seats-'));
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
const executable=process.argv[2]&&path.resolve(process.argv[2]);
let nativeChild,deadline;const nativeMessages=[];let browserActor,shared;
function report(){return {vehicle:shared.row.slice(),browserNumber:browserActor.number,browserName:browserActor.player.name,
 browserRows:[...browserActor.wire.messages].reverse().find(m=>m.t==='cars')?.c || [],
 serverRows:[...game.peers].map(p=>game.row(p)).filter(Boolean),nativeMessages:nativeMessages.slice(-100)};}
async function control(req,res){
 if(req.method!=='POST') {res.writeHead(405);return res.end('{}');}
 let size=0,parts=[];for await(const part of req){size+=part.length;if(size>16384)throw Error('Bounded fixture control body');parts.push(part)}
 const body=JSON.parse(Buffer.concat(parts)),action=body.action;
 if(action==='browserDrive'){
  await browserActor.wire.sync({...foot(shared.row[3],shared.row[4],shared.row[5]),skin:2});
  check(await enter(browserActor,shared),'Actual browser driver reservation denied');
  await browserActor.wire.sync(drive(shared,{skin:2}));
 }else if(action==='browserMove'){
  assert([body.x,body.y,body.z].every(Number.isFinite)&&Math.abs(body.x)<=6000&&Math.abs(body.y)<=6000&&body.z>=-200&&body.z<=1000,'Finite fixture browser motion required');
  await browserActor.wire.sync(drive(shared,{skin:2,x:body.x,y:body.y,z:body.z,heading:Number.isFinite(body.heading)?body.heading:0,vx:4,vy:1,vz:0,speed:5}));
 }else if(action==='browserExit'){
  const p=[...game.peers].find(p=>p.player===browserActor.player),s=p.state;
  if(s.driving===true)await browserActor.wire.sync({t:'exit',v:shared.id,x:s.x,y:s.y,z:s.z,h:s.heading||0,p:s.pitch||0,r:s.roll||0,hp:s.health||1000});
  await browserActor.wire.sync({...foot(s.x+2,s.y,s.z),skin:2});
 }else if(action==='browserPassenger'){
  assert(Number.isInteger(body.seat)&&body.seat>0&&body.seat<4,'Synthetic exact seat required');
  const p=[...game.peers].find(p=>p.player===browserActor.player),v=shared.row;
  if(p.state.driving===true)throw Error('Browser must normally exit before passenger entry');
  await browserActor.wire.sync({...foot(v[3],v[4],v[5]),skin:2});
  await browserActor.wire.sync({...foot(v[3],v[4],v[5]),skin:2,driving:false,riding:shared.id,seat:body.seat,move:0});
 }else if(action==='browserFoot'){
  const p=[...game.peers].find(p=>p.player===browserActor.player),s=p.state;await browserActor.wire.sync({...foot(s.x+2,s.y,s.z),skin:2});
 }else if(action==='deleteVehicle')game.removeOwnedVehicle(shared);
 else if(action!=='report')throw Error('Unsupported private fixture action');
 game.publishPlayerRows();await browserActor.wire.sync({t:'board'});
 const bytes=Buffer.from(JSON.stringify(report()));res.writeHead(200,{'Content-Type':'application/json','Content-Length':bytes.length});res.end(bytes);
}
async function main(){
 assert(executable&&fs.statSync(executable).isFile(),'Pass the bounded native NMP test executable');
 fs.mkdirSync(OUT,{recursive:true});for(const name of SOURCES)fs.copyFileSync(path.join(ROOT,name),path.join(fixture,name));
 const local=path.join(fixture,'local-only');fs.mkdirSync(path.join(local,'selfhost'),{recursive:true});fs.mkdirSync(path.join(local,'site/game/world'),{recursive:true});fs.mkdirSync(path.join(local,'site/game/native'),{recursive:true});
 fs.writeFileSync(path.join(local,'site/game/world/index.json'),'{}');fs.writeFileSync(path.join(local,'site/game/world/collision.json'),'{"cells":[]}');fs.writeFileSync(path.join(local,'selfhost/client-catalog.json'),'{"vehicles":[],"homes":[]}');fs.writeFileSync(path.join(local,'selfhost/weapon-catalog.json'),'{"items":[],"shops":[]}');
 fs.writeFileSync(path.join(local,'site/game/native/riders.json'),JSON.stringify({version:2,models:{420:{seats:Array.from({length:4},(_,i)=>({at:[i%2,-Math.floor(i/2),0]}))}}}));
 game=require(path.join(fixture,'selfhost_backend.js'));
 const onMessage=game.onMessage.bind(game);game.onMessage=(peer,message)=>{if(browserActor&&peer.player!==browserActor.player&&['hi','enter','exit','me'].includes(message.t)){
  nativeMessages.push({number:peer.player.number,t:message.t,...Object.fromEntries(['v','request','seat','passenger','walking','driving','riding','vehicle','skin','x','y','z','heading','car','act'].filter(k=>message[k]!==undefined).map(k=>[k,message[k]])),hasParked:Object.hasOwn(message,'parked')});if(nativeMessages.length>3000)throw Error('Native fixture message bound');}onMessage(peer,message);};
 server=http.createServer((req,res)=>{const task=req.url==='/__fixture'?control(req,res):game.http(req,res);task.catch(error=>{const b=Buffer.from(JSON.stringify({error:error.message}));res.writeHead(400,{'Content-Type':'application/json','Content-Length':b.length});res.end(b)});});server.on('upgrade',(req,socket,head)=>game.upgrade(req,socket,head));
 await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));port=server.address().port;check(![8766,8780,8801,8803,8804,8805,8806].includes(port),'Fixture collided with live service');
 browserActor=await actor();await browserActor.wire.sync({...foot(),skin:2});shared=vehicle('shared-cab');
 const base='http://127.0.0.1:'+port,{spawn}=require('node:child_process');nativeChild=spawn(executable,[base,base+'/__fixture'],{stdio:['ignore','pipe','pipe']});let stdout='',stderr='';
 nativeChild.stdout.on('data',b=>{stdout+=b;if(stdout.length>65536)nativeChild.kill('SIGTERM')});nativeChild.stderr.on('data',b=>{stderr+=b;if(stderr.length>65536)nativeChild.kill('SIGTERM')});
 deadline=setTimeout(()=>nativeChild.kill('SIGTERM'),180000);
 const result=await new Promise((resolve,reject)=>{nativeChild.once('error',reject);nativeChild.once('exit',(code,signal)=>resolve({code,signal}))});clearTimeout(deadline);
 same(hashes(),before,'Server source changed during actual native test');fs.writeFileSync(path.join(OUT,'report.json'),JSON.stringify({schema:1,passed:result.code===0,result,sourceSHA256:before,nativeExecutableSHA256:crypto.createHash('sha256').update(fs.readFileSync(executable)).digest('hex'),stdout,stderr,checks,...report(),scope:'Actual unmodified Swift NativeMultiplayerClient plus copied real backend and separate browser-shaped peer over ephemeral loopback. Synthetic world/seats; no rendered/GPU/device or retail claim.'},null,2)+'\n');process.stdout.write(stdout);process.stderr.write(stderr);if(result.code!==0)throw Error('Native executable failed '+JSON.stringify(result));
 console.log('PASS actual native seat backend fixture');
}
main().catch(error=>{console.error(error.stack);process.exitCode=1;}).finally(async()=>{
 clearTimeout(deadline);if(nativeChild?.exitCode===null)nativeChild.kill('SIGTERM');for(const client of clients)if(!client.closed)client.socket.destroy();if(server)await new Promise(resolve=>server.close(resolve));if(game){clearInterval(game.tick);clearInterval(game.projectileTimer);game.flushSync();}
 Date.now=realNow;for(const[key,value]of Object.entries(savedEnv))if(value===undefined)delete process.env[key];else process.env[key]=value;fs.rmSync(fixture,{recursive:true,force:true});
});
