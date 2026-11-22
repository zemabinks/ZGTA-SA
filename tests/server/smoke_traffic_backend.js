// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Actual independent backend and two WebSocket clients. Roads/world are
// authored boundaries; this is not native/browser rendering or retail AI.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os'),http=require('node:http');
const {square}=require('./traffic_fixture'),{crc32}=require('../../server/population/pedestrian_paths');
const {TrafficRoads}=require('../../server/population/traffic_roads'),{Traffic}=require('../../server/population/traffic');
const root=path.resolve(__dirname,'../..'),temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-traffic-backend-'));
let game,server,checks=0;const clients=[];const check=(v,message)=>{assert(v,message);checks++;};
const delay=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function wait(condition,message){const end=Date.now()+7000;while(Date.now()<end){if(condition())return;await delay(20);}throw Error(message);}
function records(data){
 const result=[];let at=0;
 while(at+2<=data.length){const tag=data[at++],first=data[at++];let length=first;if(first&128){if(at===data.length)break;length=(first&127)|(data[at++]<<7);}if(at+length>data.length)break;result.push({tag,payload:data.subarray(at,at+length)});at+=length;}
 return result;
}
async function connect(hello){
 const socket=new WebSocket('ws://127.0.0.1:'+server.address().port+'/api/world/live');socket.binaryType='arraybuffer';
 const client={socket,events:[],messages:[],binary:[],send:value=>socket.send(JSON.stringify(value))};clients.push(client);
 socket.addEventListener('message',event=>{
  if(typeof event.data==='string'){const value=JSON.parse(event.data);client.messages.push(value);client.events.push({json:value});}
  else{const value=Buffer.from(event.data);client.binary.push(...records(value));client.events.push({binary:records(value)});}
 });
 await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',reject,{once:true});});
 client.send({t:'hi',...hello});await wait(()=>client.messages.some(m=>m.t==='hello'),'No actual hello');
 client.send({t:'me',walking:true,skin:7,x:0,y:0,z:13,h:0,weapon:0});
 return client;
}
(async()=>{
 try{
  for(const name of ['selfhost_backend.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js','player_placement.js'])fs.copyFileSync(path.join(root,name),path.join(temporary,name));
  game=require(path.join(temporary,'selfhost_backend'));
  clearInterval(game.tick);clearInterval(game.projectileTimer);
  const bytes=square(),graph=new TrafficRoads(bytes,crc32(bytes));
  game.traffic=new Traffic({graph,models:[{id:410,length:4,width:2,colors:[[2,3]]}],ground:()=>13,clear:()=>true,random:()=>.55,
   maximum:1,perObserver:1,reserved:()=>new Set([...game.vehicles.values()].filter(v=>v.trafficOrigin).map(v=>v.trafficOrigin.id))});
  server=http.createServer((req,res)=>game.http(req,res));server.on('upgrade',(req,socket,head)=>game.upgrade(req,socket,head));
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  const native=await connect({nativeInventory:true,inventoryAck:1,trafficProtocol:38}),browser=await connect({});
  await wait(()=>game.peers.size===2&&[...game.peers].every(p=>p.state),'Actual peer positions missing');
  check(native.messages.find(m=>m.t==='hello').trafficProtocol===38,'Native traffic capability missing');
  check(browser.messages.find(m=>m.t==='hello').traffic===1,'Browser compact traffic not announced');
  check(game.population===null&&native.messages.find(m=>m.t==='hello').peds===0,'Traffic incorrectly requires/enables pedestrian population');
  game.publishTraffic(Date.now(),true);
  await wait(()=>native.binary.some(r=>r.tag===4)&&browser.binary.some(r=>r.tag===4),'Shared binary traffic base missing');
  const actor=[...game.traffic.actors.values()][0],id=actor.id;
  check(native.binary.find(r=>r.tag===4).payload.readUInt16BE(4)===id&&browser.binary.find(r=>r.tag===4).payload.readUInt16BE(4)===id,'Clients received different traffic identities');
  check(game.peers.size===2,'Traffic counted as a human player');
  native.send({t:'tcar',id,why:'door'});
  await wait(()=>native.messages.some(m=>m.t==='note'&&m.text.includes('no longer available')),'Distant materialization not rejected');
  check(![...game.vehicles.values()].some(v=>v.trafficOrigin),'Distant request created registered vehicle');
  const near={x:actor.pose.position[0],y:actor.pose.position[1],z:13};
  native.send({t:'me',walking:true,skin:7,...near,h:0,weapon:0});browser.send({t:'me',walking:true,skin:7,...near,h:0,weapon:0});
  await wait(()=>[...game.peers].every(p=>Math.abs(p.state.x-near.x)<.01),'Near positions not accepted');
  native.send({t:'tcar',id,why:'door'});
  await wait(()=>[...game.vehicles.values()].some(v=>v.trafficOrigin?.id===id),'Nearby traffic not materialized');
  const vehicle=[...game.vehicles.values()].find(v=>v.trafficOrigin?.id===id),registered=vehicle.id;
  await wait(()=>browser.messages.some(m=>m.t==='veh'&&m.v[0]===registered)&&browser.binary.some(r=>r.tag===5),'Other client missed registry/removal');
  check(vehicle.row[14]===id&&game.traffic.actors.size===0,'Transfer duplicated or lost source identity');
  check(Math.abs(actor.pose.direction[0])>.1&&Math.abs(actor.pose.direction[1])>.1,'Transfer fixture failed to exercise a non-axial heading');
  check(Math.hypot(-Math.sin(vehicle.row[6])-actor.pose.direction[0],Math.cos(vehicle.row[6])-actor.pose.direction[1])<.001,
   'Compact-to-registered transfer mirrored or snapped the vehicle heading');
  check(vehicle.row[11]===null&&!game.vehicleClaim(vehicle),'Materialization fabricated a driver or seat permission');
  const registryIndex=browser.events.findIndex(e=>e.json?.t==='veh'&&e.json.v[0]===registered),goneIndex=browser.events.findIndex(e=>e.binary?.some(r=>r.tag===5));
  check(registryIndex>=0&&registryIndex<goneIndex,'Compact removal preceded registered identity');
  native.send({t:'tcar',id,why:'door'});await delay(60);
  check([...game.vehicles.values()].filter(v=>v.trafficOrigin).length===1,'Repeated materialization duplicated a car');
  native.send({t:'enter',v:registered,request:1});
  await wait(()=>native.messages.some(m=>m.t==='enter'&&m.request===1),'Normal native entry reply missing');
  check(native.messages.find(m=>m.t==='enter'&&m.request===1).ok===true,'Normal vehicle permission denied after transfer');
  browser.send({t:'enter',v:registered,request:2});
  await wait(()=>browser.messages.some(m=>m.t==='enter'&&m.request===2),'Second seat request missing');
  check(browser.messages.find(m=>m.t==='enter'&&m.request===2).ok===false,'Two drivers reserved the same car');
  native.send({t:'me',driving:true,vehicle:registered,car:vehicle.row[2],skin:7,...near,heading:Math.PI/2,pitch:0,roll:0,life:100});
  await wait(()=>game.vehicleDriver(vehicle),'Reserved client did not become actual driver');
  check(vehicle.row[11]===String(game.vehicleDriver(vehicle).player.number),'Registry driver identity not shared');
  // Observe the actual backend-to-planner boundary after a normal driving
  // report, retaining the production tick and existing socket ownership.
  const tick=game.traffic.tick;let observedObstacles;
  game.traffic.tick=function(now,observers,obstacles){observedObstacles=obstacles;return tick.call(this,now,observers,obstacles);};
  try{game.publishTraffic(Date.now(),true);}finally{game.traffic.tick=tick;}
  check(observedObstacles.filter(o=>o.id===410&&o.length===4&&o.width===2&&Math.abs(o.direction[0]+1)<.001&&Math.abs(o.direction[1])<.001).length===2,
   'Registered/driven vehicle obstacles lost prepared dimensions or wire heading');
  const parked={...near,x:near.x+1,heading:vehicle.row[6],pitch:0,roll:0,health:1000};
  native.send({t:'me',walking:true,vehicle:registered,car:vehicle.row[2],skin:7,...near,heading:0,parked,health:100});
  await wait(()=>!game.vehicleClaim(vehicle),'Normal exit retained driver ownership');
  check(vehicle.id===registered&&vehicle.row[11]===null&&Math.abs(vehicle.row[3]-parked.x)<.001,'Exit changed identity or lost final parked pose');
  game.publishTraffic(Date.now(),true);
  const nativePeer=[...game.peers].find(p=>p.inventoryEnabled);
  await wait(()=>game.traffic.interest.has(nativePeer),'Second visible traffic lifetime missing before capability revocation');
  native.send({t:'hi',nativeInventory:true,inventoryAck:1,trafficProtocol:0});
  await wait(()=>!nativePeer.trafficEnabled,'Server did not revoke traffic capability');
  check(!game.traffic.interest.has(nativePeer),'Revoked capability retained server traffic interest');
  native.socket.close();await wait(()=>game.peers.size===1,'Disconnected driver peer retained');
  check(game.traffic.interest.size<=1,'Disconnected traffic interest leaked');
  game.publishTraffic(Date.now()+61000,true);
  check(!game.vehicles.has(registered),'Unobserved unclaimed traffic registry never retired');
  console.log('PASS actual traffic/backend two-WebSocket handoff '+checks+' checks; authored road/world, not rendered browser/native or retail acceptance');
 }finally{
  for(const client of clients)client.socket.close();for(const peer of game?.peers||[])peer.close();
  if(server)await new Promise(resolve=>server.close(resolve));
  if(game){clearInterval(game.tick);clearInterval(game.projectileTimer);game.flushSync();}
  fs.rmSync(temporary,{recursive:true,force:true});
 }
})().catch(error=>{console.error(error);process.exitCode=1;});
