#!/usr/bin/env node
'use strict';
// Exercise actual backend HTTP/WS handlers with isolated state and synthetic
// transports. No listening socket, application or production service starts.
// Catalogs and collision geometry below are expressly synthetic test fixtures;
// no archived website/game files are read, symlinked or required by this gate.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),{EventEmitter}=require('node:events');
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-inventory-ack-')),originalNow=Date.now;
let game,now=1_700_000_000_000;
async function main(){
 Date.now=()=>now;
 const local=path.join(temporary,'local-only');fs.mkdirSync(path.join(local,'selfhost'),{recursive:true});
 for(const file of ['selfhost_backend.js','player_placement.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js'])fs.copyFileSync(path.join(require('node:path').resolve(__dirname, '../..'),file),path.join(temporary,file));
 fs.writeFileSync(path.join(local,'selfhost/client-catalog.json'),JSON.stringify({vehicles:[],homes:[]}));
 fs.writeFileSync(path.join(local,'selfhost/weapon-catalog.json'),JSON.stringify({items:[{
  id:22,name:'Synthetic ACK fixture',ammo:100,capacity:17,price:0,slot:2,
  fire:'INSTANT_HIT',stats:{loop:[0,9,0],range:40}}],shops:[]}));
 const world=path.join(local,'site/game/world');fs.mkdirSync(world,{recursive:true});
 fs.writeFileSync(path.join(world,'index.json'),JSON.stringify({detail:{size:375,grid:16,origin:-3000,cells:[{cell:28}]},inside:{cells:[]}}));
 // Synthetic flat floor covering the test participants' cell. Actual hit
 // assertions below still exercise the real server's fail-closed SCL2 LOS.
 const vertices=[[1500,-2625,0],[1875,-2625,0],[1875,-2250,0],[1500,-2250,0]],indices=[0,1,2,0,2,3];
 const mesh=Buffer.alloc(16+vertices.length*12+indices.length*4);
 [0x324c4353,vertices.length,indices.length/3,0].forEach((n,i)=>mesh.writeUInt32LE(n,i*4));
 vertices.forEach((point,i)=>point.forEach((n,axis)=>mesh.writeFloatLE(n,16+i*12+axis*4)));
 indices.forEach((n,i)=>mesh.writeUInt32LE(n,16+vertices.length*12+i*4));
 fs.writeFileSync(path.join(world,'c28.col.bin'),mesh);
 game=require(path.join(temporary,'selfhost_backend.js'));
 function peer(id=null,ack=true){
  const account=game.ensurePlayer({headers:{cookie:id?'zgta_local='+id:''}},{setHeader(){}}),packets=[];
  const p={id:account.id,player:account.player,ready:false,lastSeen:now,closed:false,
   state:{walking:true,x:1570,y:-2460,z:13.6},packets,send:m=>packets.push(structuredClone(m))};
  game.peers.add(p);game.onMessage(p,{t:'hi',nativeInventory:true,...(ack?{inventoryAck:1}:{})});return p;
 }
 const a=peer(),b=peer();b.state.x+=4;
 const inventory=p=>p.packets.filter(m=>m.t==='inventory').at(-1);
 const connection=a.inventoryConnection;
 assert.match(connection,/^[\w-]{24}$/);assert.notEqual(connection,b.inventoryConnection);
 assert.deepEqual(inventory(a).state.ack,{connection,processedShot:0});
 assert.equal(a.packets.find(m=>m.t==='hello').inventoryAck,1);
 // This rejection/replay scenario resumes one elapsed interval after a saved
 // shot. Fresh full transport bursts are exercised by smoke_weapon_transport.
 a.player.inventory={selected:22,weapons:{22:{clip:17,rest:30}},lastShotAt:now-300};game.sendInventory(a);
 const shot=(s,extra={})=>{
  a.lastSeen=b.lastSeen=now;
  const count=a.packets.filter(m=>m.t==='inventory').length;
  game.onMessage(a,{t:'shot',w:22,c:connection,s,o:[1570,-2460,14.95],h:[1574,-2460,14.75],...extra});
  assert.equal(a.packets.filter(m=>m.t==='inventory').length,count+1,'Processed native shot had no inventory result');return inventory(a);
 };
 let reply=shot(1);assert.equal(reply.result.accepted,true);assert.equal(reply.state.weapons.find(w=>w.id===22).clip,16);
 const first=structuredClone(reply.state);reply=shot(2);assert.equal(reply.result.accepted,false);assert.equal(reply.state.revision,first.revision);assert.equal(reply.state.ack.processedShot,2);
 now+=400;reply=shot(2);assert.equal(reply.result.accepted,false);assert.equal(a.player.inventory.weapons[22].clip,16,'Rejected sequence became a later billable shot');
 reply=shot(3);assert.equal(reply.result.accepted,true);assert.equal(reply.state.ack.processedShot,3);assert.equal(a.player.inventory.weapons[22].clip,15);
 assert.equal(first.ack.processedShot,1);assert.equal(first.weapons.find(w=>w.id===22).clip,16,'Earlier snapshot aliased mutable current inventory');
 reply=shot(4,{o:[5000,5000,0]});assert.equal(reply.result.accepted,false);assert.equal(reply.state.ack.processedShot,4);
 a.player.passive=true;reply=shot(5);assert.equal(reply.result.accepted,false);assert.equal(reply.state.ack.processedShot,5);a.player.passive=false;
 a.player.health=0;reply=shot(6);assert.equal(reply.result.accepted,false);assert.equal(reply.state.ack.processedShot,6);a.player.health=100;
 reply=shot(7,{w:24});assert.equal(reply.result.accepted,false);assert.equal(reply.state.ack.processedShot,7);
 a.player.inventory.weapons[22].clip=0;reply=shot(8);assert.equal(reply.result.accepted,false);assert.equal(reply.state.ack.processedShot,8);
 a.player.inventory.weapons[22].clip=3;a.player.inventory.reload={weapon:22,until:now+1800};reply=shot(9);assert.equal(reply.result.accepted,false);assert.equal(reply.state.ack.processedShot,9);
 for(const s of [0,'10',Number.MAX_SAFE_INTEGER+1]){reply=shot(s);assert.equal(reply.state.ack.processedShot,9);assert.equal(reply.result.accepted,false);}
 reply=shot(900,{c:b.inventoryConnection});assert.equal(reply.state.ack.processedShot,9);assert.equal(reply.result.accepted,false,'Foreign connection advanced watermark');
 game.onMessage(a,{t:'hi',nativeInventory:false,inventoryAck:0});assert.equal(a.inventoryConnection,connection);assert.equal(a.processedShotSequence,9);assert(a.inventoryAckEnabled&&a.inventoryEnabled,'Duplicate hello downgraded authoritative inventory');
 now+=2000;reply=shot(10);assert.equal(reply.result.accepted,true);assert.equal(reply.state.ack.processedShot,10);
 const health=b.player.health;
 game.onMessage(a,{t:'hit',w:22,c:b.inventoryConnection,s:10,to:String(b.player.number)});assert.equal(b.player.health,health,'Wrong connection hit accepted');
 game.onMessage(a,{t:'hit',w:22,c:connection,s:10,to:String(b.player.number)});assert(b.player.health<health);
 function transport(method,url,id,nonce){
  const req=new EventEmitter();req.method=method;req.url=url;req.headers={cookie:'zgta_local='+id,...(nonce===undefined?{}:{'x-zgta-inventory-connection':nonce})};req.destroy=()=>{};
  const res={status:null,body:null,setHeader(){},writeHead(status){this.status=status;},end(data){this.body=JSON.parse(data.toString());}};return {req,res};
 }
 async function request(method,url,id,nonce,body={}){
  const t=transport(method,url,id,nonce),pending=game.http(t.req,t.res);
  if(method==='POST'){t.req.emit('data',Buffer.from(JSON.stringify(body)));t.req.emit('end');}
  await pending;return t.res;
 }
 let response=await request('GET','/api/local/state',a.id,connection);
 assert.equal(response.status,200);assert.deepEqual(response.body.weaponInventory.ack,{connection,processedShot:10});
 response=await request('GET','/api/local/state',a.id);assert.equal(response.status,200);assert.equal(response.body.weaponInventory.ack,undefined,'Legacy HTTP borrowed another connection watermark');
 response=await request('GET','/api/local/state',b.id,connection);assert.equal(response.status,409,'HTTP nonce was not bound to authenticated player');
 response=await request('POST','/api/local/action',b.id,connection,{action:'weapon.select',weapon:0});assert.equal(response.status,409);
 const sibling=peer(a.id);assert.notEqual(sibling.inventoryConnection,connection);
 response=await request('POST','/api/local/action',a.id,connection,{action:'weapon.select',weapon:0});
 assert.equal(response.status,200);assert.equal(response.body.state.weaponInventory.selected,0);assert.deepEqual(response.body.state.weaponInventory.ack,{connection,processedShot:10});
 assert.deepEqual(inventory(sibling).state.ack,{connection:sibling.inventoryConnection,processedShot:0},'Action broadcast reused another socket ACK');
 now+=301;a.lastSeen=b.lastSeen=now;const beforeMelee=b.player.health;
 game.onMessage(a,{t:'hit',w:0,c:b.inventoryConnection,to:String(b.player.number)});assert.equal(b.player.health,beforeMelee);
 game.onMessage(a,{t:'hit',w:0,c:connection,to:String(b.player.number)});assert.equal(b.player.health,beforeMelee-8,'Negotiated melee nonce path failed');
 a.player.inventory.selected=22;a.player.inventory.weapons[22]={clip:1,rest:30};
 response=await request('POST','/api/local/action',a.id,connection,{action:'weapon.reload'});assert.equal(response.status,200);assert(response.body.state.weaponInventory.reload);assert.equal(response.body.state.weaponInventory.ack.processedShot,10);
 now+=1801;a.lastSeen=sibling.lastSeen=now;
 response=await request('GET','/api/local/state',a.id,connection);assert.equal(response.body.weaponInventory.reload,null);assert.equal(response.body.weaponInventory.weapons.find(w=>w.id===22).clip,17);assert.equal(response.body.weaponInventory.ack.processedShot,10);
 // Connection expires while the HTTP request body is still in flight: action
 // must not mutate the player or borrow the sibling connection's watermark.
 const delayed=transport('POST','/api/local/action',a.id,connection),pending=game.http(delayed.req,delayed.res);
 a.closed=true;game.remove(a);delayed.req.emit('data',Buffer.from(JSON.stringify({action:'weapon.select',weapon:0})));delayed.req.emit('end');await pending;
 assert.equal(delayed.res.status,409);assert.equal(a.player.inventory.selected,22);
 response=await request('GET','/api/local/state',a.id,connection);assert.equal(response.status,409);
 const reconnected=peer(a.id),nonce=reconnected.inventoryConnection;
 assert.notEqual(nonce,connection);assert.equal(inventory(reconnected).state.ack.processedShot,0);
 now+=400;reconnected.lastSeen=now;
 game.onMessage(reconnected,{t:'shot',w:22,c:nonce,s:1,o:[1570,-2460,14.95],h:[1574,-2460,14.75]});
 assert.equal(inventory(reconnected).result.accepted,true,'Reconnect could not restart its sequence');
 assert.equal(inventory(reconnected).state.ack.processedShot,1);
 const legacy=peer(null,false);assert.equal(inventory(legacy).state.ack,undefined);
 legacy.player.inventory={selected:22,weapons:{22:{clip:3,rest:0}}};legacy.lastSeen=now;
 game.onMessage(legacy,{t:'shot',w:22,o:[1570,-2460,14.95],h:[1574,-2460,14.75]});
 assert.equal(legacy.player.inventory.weapons[22].clip,2);assert.equal(inventory(legacy).state.ack,undefined,'Legacy no-sequence client lost compatibility');
 // Run the real WebSocket upgrade, mask decoder and output-frame serializer
 // over an in-memory socket, still without starting a listening service.
 const framedAccount=game.ensurePlayer({headers:{cookie:''}},{setHeader(){}});
 class MemorySocket extends EventEmitter {
  constructor(){super();this.writable=true;this.writableLength=0;this.writes=[];}
  write(data){this.writes.push(data);return true;}
  end(){this.writable=false;}
  destroy(){this.writable=false;}
 }
 function frame(value){
  const data=Buffer.from(JSON.stringify(value)),mask=Buffer.from([3,7,11,19]);
  const header=data.length<126 ? Buffer.from([0x81,0x80|data.length]):Buffer.from([0x81,0xfe,data.length>>8,data.length&255]);
  return Buffer.concat([header,mask,Buffer.from(data.map((n,i)=>n^mask[i%4]))]);
 }
 function packets(socket){return socket.writes.filter(Buffer.isBuffer).filter(bytes=>bytes[0]===0x81).map(bytes=>{
  const size=bytes[1]&127,offset=size===126?4:2,length=size===126?bytes.readUInt16BE(2):size;
  return JSON.parse(bytes.subarray(offset,offset+length).toString());
 });}
 function upgrade(socket){game.upgrade({url:'/api/world/live',socket:{remoteAddress:'127.0.0.1'},headers:{host:'localhost:1',upgrade:'websocket','sec-websocket-key':Buffer.alloc(16,3).toString('base64'),cookie:'zgta_local='+framedAccount.id}},socket,Buffer.alloc(0));socket.emit('data',frame({t:'hi',nativeInventory:true,inventoryAck:1}));return [...game.peers].find(p=>p.socket===socket);}
 const socket1=new MemorySocket(),framed=upgrade(socket1),framedNonce=framed.inventoryConnection;
 assert(socket1.writes.some(value=>typeof value==='string'&&value.startsWith('HTTP/1.1 101')));
 framed.player.inventory={selected:22,weapons:{22:{clip:3,rest:0}}};
 socket1.emit('data',frame({t:'me',walking:true,x:1570,y:-2460,z:13.6}));now+=400;
 socket1.emit('data',frame({t:'shot',w:22,c:framedNonce,s:1,o:[1570,-2460,14.95],h:[1574,-2460,14.75]}));
 assert.deepEqual(packets(socket1).filter(p=>p.t==='inventory').at(-1).state.ack,{connection:framedNonce,processedShot:1});
 assert.equal(framed.player.inventory.weapons[22].clip,2);
 socket1.emit('data',frame({t:'shot',w:22,c:framedNonce,s:1,o:[1570,-2460,14.95],h:[1574,-2460,14.75]}));assert.equal(framed.player.inventory.weapons[22].clip,2);
 const socket2=new MemorySocket(),newFramed=upgrade(socket2);
 assert(framed.closed&&!socket1.writable);assert.notEqual(newFramed.inventoryConnection,framedNonce);
 response=await request('GET','/api/local/state',framedAccount.id,framedNonce);assert.equal(response.status,409);
 response=await request('GET','/api/local/state',framedAccount.id,newFramed.inventoryConnection);assert.equal(response.status,200);assert.equal(response.body.weaponInventory.ack.processedShot,0);
 newFramed.close();
 game.flushSync();const saved=fs.readFileSync(path.join(local,'selfhost/players.json'),'utf8');
 assert(!saved.includes('processedShot')&&!saved.includes('inventoryConnection'),'Ephemeral socket correlation leaked into saved inventory');
 console.log('PASS (synthetic fixtures; no archive): atomic WS/HTTP inventory ACKs, every shot rejection/duplicate, nonce-bound hit/action/refresh, pending-body disconnect, per-peer broadcasts, reload, reconnect, legacy no-s and actual masked WebSocket codec/upgrade');
}
main().catch(error=>{console.error(error);process.exitCode=1;}).finally(()=>{
 Date.now=originalNow;if(game){clearInterval(game.tick);clearInterval(game.projectileTimer);game.flushSync();}fs.rmSync(temporary,{recursive:true,force:true});
});
