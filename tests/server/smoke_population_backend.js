// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),http=require('node:http');
const {Pedestrians}=require('../../server/population/pedestrians');
const root=path.resolve(__dirname,'../..'),temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-population-'));
let server,socket,game,checks=0;const check=(v,text)=>{assert(v,text);checks++;};
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function wait(test,text){const end=Date.now()+6000;while(Date.now()<end){if(test())return;await sleep(20);}throw Error(text);}
(async()=>{
 try{
  for(const name of ['selfhost_backend.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js','player_placement.js'])fs.copyFileSync(path.join(root,name),path.join(temporary,name));
  const local=path.join(temporary,'local-only/selfhost');fs.mkdirSync(local,{recursive:true});
  fs.writeFileSync(path.join(local,'weapon-catalog.json'),JSON.stringify({items:[{id:22,name:'Authored handgun',ammo:17,price:0,capacity:17,slot:2,stats:{range:40}}]}));
  game=require(path.join(temporary,'selfhost_backend.js'));
  // Geometry is an explicit controlled boundary in this network/server test.
  // Actual SCL2/Rapier/world acceptance is tested separately.
  const geometry=require(path.join(temporary,'world_collision.js'));let cover=false;
  geometry.lineOfSight=()=>!cover;
  const points=[[0,0,13],[50,0,13],[50,50,13],[0,50,13]];
  const graph={point:id=>points[id].slice(),neighbors:id=>[{id:(id+1)%4,kind:0},{id:(id+3)%4,kind:0}],nearest:()=>({id:1,distance:0}),crc32:'00000000'};
  game.population=new Pedestrians({graph,models:[7],ground:()=>13,clear:()=>true,random:()=>0.1});
  server=http.createServer((req,res)=>game.http(req,res));server.on('upgrade',(req,stream,head)=>game.upgrade(req,stream,head));
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  socket=new WebSocket('ws://127.0.0.1:'+server.address().port+'/api/world/live');socket.binaryType='arraybuffer';
  const messages=[],binary=[];
  socket.addEventListener('message',event=>typeof event.data==='string'?messages.push(JSON.parse(event.data)):binary.push(Buffer.from(event.data)));
  await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',reject,{once:true});});
  socket.send(JSON.stringify({t:'hi',nativeInventory:true,inventoryAck:1,npcProtocol:38}));
  await wait(()=>messages.some(row=>row.t==='hello'),'Actual hello missing');
  const hello=messages.find(row=>row.t==='hello');check(hello.npcProtocol===38&&hello.peds===1,'Population capability not negotiated');
  socket.send(JSON.stringify({t:'me',walking:true,skin:7,x:0,y:0,z:13,h:0,weapon:22}));
  await wait(()=>[...game.peers].some(peer=>peer.state),'Actual position missing');
  game.publishPopulation(Date.now(),true);await wait(()=>binary.some(packet=>packet[0]===10),'Actual binaryopcode2 NPC state missing');
  const peer=[...game.peers][0],actor=[...game.population.actors.values()][0];check(actor,'Server population missing');
  check(binary.some(packet=>packet[0]===11),'Supplemental actor state missing');
  socket.send(JSON.stringify({t:'board'}));await wait(()=>messages.some(row=>row.t==='board'),'Actual board missing');
  check(messages.filter(row=>row.t==='board').at(-1).players===1&&game.peers.size===1,'NPC counted as human player');
  const inventory=require(path.join(temporary,'weapon_inventory.js'));
  peer.player.inventory={revision:1,selected:22,weapons:{22:{clip:10,rest:0}}};inventory.ensure(peer.player);
  Object.assign(peer.state,{x:actor.position[0]-2,y:actor.position[1],z:actor.position[2]});
  const origin=[peer.state.x,peer.state.y,peer.state.z+0.9],hit=actor.position.map((v,i)=>v+(i===2?0.9:0)),target='p'+actor.id;
  const send=packet=>socket.send(JSON.stringify(packet));
  const claim={t:'hit',to:target,w:22,s:1,c:hello.inventoryConnection};
  send(claim);await sleep(80);check(actor.health===100,'Claim without accepted shot damaged NPC');
  send({t:'shot',w:22,s:1,c:hello.inventoryConnection,o:origin,h:hit});
  await wait(()=>peer.processedShotSequence===1,'Actual inventory shot not processed');
  cover=true;send(claim);await sleep(80);check(actor.health===100,'NPC damage passed through cover');
  cover=false;send(claim);await wait(()=>actor.health<100,'Authorized visible NPC hit missing');
  check(actor.health===82&&actor.hitCounter===1,'Authoritative NPC damage wrong');
  send(claim);await sleep(80);check(actor.health===82,'Accepted shot damaged NPC twice');
  send({...claim,s:2,c:'stale-connection'});await sleep(80);check(actor.health===82,'Stale inventory namespace damaged NPC');
  peer.player.insideHome='authored-interior';game.publishPopulation(Date.now(),false);
  await wait(()=>binary.some(packet=>packet[0]===8),'Interior did not stream out exterior NPCs');
  check(![...game.population.interest.get(peer)||[]].length,'Interior retains exterior interest');
  socket.close();await wait(()=>game.peers.size===0,'Disconnected actual socket retained');
  check(!game.population.interest.has(peer),'Disconnected socket leaked NPC interest');
  console.log('PASS actual backend/WebSocket NPC channel: '+checks+' checks; explicit geometry boundary, no native rendering or retail claim');
 }finally{
  socket?.close();for(const peer of game?.peers||[])peer.close();
  if(server)await new Promise(resolve=>server.close(resolve));
  if(game){clearInterval(game.tick);clearInterval(game.projectileTimer);game.flushSync();}
  fs.rmSync(temporary,{recursive:true,force:true});
 }
})().catch(error=>{console.error(error);process.exitCode=1;});
