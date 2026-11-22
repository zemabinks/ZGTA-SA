// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Real ephemeral HTTP/WebSocket clients and actual backend publication. The
// pavement islands and ground/LOS are authored boundaries, not original data.
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path'),http=require('node:http');
const {Pedestrians}=require('../../server/population/pedestrians');
const root=path.resolve(__dirname,'../..');let checks=0;
const check=(value,message)=>{assert(value,message);checks++;};
const sleep=ms=>new Promise(resolve=>setTimeout(resolve,ms));
async function wait(test,message){const end=Date.now()+6500;while(Date.now()<end){if(test())return;await sleep(25);}throw Error(message);}
const payloadOffset=packet=>packet[1]&128?3:2;
const freeID=packet=>packet[0]===10?packet.readUInt16BE(payloadOffset(packet)+4):null;
async function scenario(shared){
 const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-npc-observation-'));
 let game,server;const clients=[];
 try{
  for(const name of ['selfhost_backend.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js','player_placement.js'])
   fs.copyFileSync(path.join(root,name),path.join(temporary,name));
  const local=path.join(temporary,'local-only/selfhost');fs.mkdirSync(local,{recursive:true});
  fs.writeFileSync(path.join(local,'weapon-catalog.json'),JSON.stringify({items:[]}));
  game=require(path.join(temporary,'selfhost_backend.js'));
  let blocked=false;
  const points=[[50,0,13],[60,0,13],[220,0,13],[230,0,13]];
  const graph={crc32:'00000000',point:id=>points[id].slice(),neighbors:id=>[{id:id^1,kind:0}],nearest:query=>{
   const rows=points.map((p,id)=>({id,distance:Math.hypot(...p.map((v,i)=>v-query[i]))})).sort((a,b)=>a.distance-b.distance);
   return rows[0].distance<=18?rows[0]:null;
  }};
  game.population=new Pedestrians({graph,models:[14],ground:()=>13,clear:()=>!blocked,random:()=>0,maximum:1,perObserver:1});
  server=http.createServer((req,res)=>game.http(req,res));server.on('upgrade',(req,stream,head)=>game.upgrade(req,stream,head));
  await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
  async function connect(x){
   const socket=new WebSocket('ws://127.0.0.1:'+server.address().port+'/api/world/live');socket.binaryType='arraybuffer';
   const client={socket,binary:[],messages:[]};clients.push(client);
   socket.addEventListener('message',event=>typeof event.data==='string'?client.messages.push(JSON.parse(event.data)):client.binary.push(Buffer.from(event.data)));
   await new Promise((resolve,reject)=>{socket.addEventListener('open',resolve,{once:true});socket.addEventListener('error',reject,{once:true});});
   socket.send(JSON.stringify({t:'hi',npcProtocol:38}));await wait(()=>client.messages.some(m=>m.t==='hello'),'Actual hello missing');
   check(client.messages.find(m=>m.t==='hello').npcProtocol===38,'NPC protocol not negotiated');
   client.report=x=>socket.send(JSON.stringify({t:'me',walking:true,skin:14,x,y:0,z:13,h:0}));
   client.report(x);await wait(()=>[...game.peers].some(p=>p.state?.x===x),'Actual position not admitted');return client;
  }
  const first=await connect(0);
  await wait(()=>first.binary.some(p=>p[0]===10),'Actual initial free-goal packet missing');
  const actor=[...game.population.actors.values()][0];check(actor&&freeID(first.binary.find(p=>p[0]===10))===actor.id,'Initial client/actor identity differs');
  blocked=true;
  const other=shared?await connect(60):null;
  const leavingIndex=first.binary.length;first.report(180);
  await wait(()=>[...game.peers].some(p=>p.state?.x===180),'New observer area not admitted');
  await wait(()=>first.binary.slice(leavingIndex).some(p=>p[0]===8&&p.readUInt16BE(payloadOffset(p))===actor.id),'Actual client did not stream out the old actor');
  check(!first.binary.slice(leavingIndex).some(p=>freeID(p)===actor.id),'Hidden actor was still published to the distant client');
  if(shared){
   await sleep(3500);
   check(game.population.actors.get(actor.id)===actor,'Second live WebSocket observer lost its visible actor');
   check(other.binary.some(p=>freeID(p)===actor.id),'Second observer never received that shared identity');
   other.socket.close();await wait(()=>game.peers.size===1,'Second observer did not actually disconnect');
   check(game.population.interest.size<=1,'Disconnected observer retained an interest owner');
  }
  await wait(()=>!game.population.actors.has(actor.id),'Actual backend retained an invisible NPC beyond its timeout');
  await wait(()=>game.population.actors.size===1&&[...game.population.actors.values()][0].position[0]>=220,'Actual backend did not repopulate the new area');
  const replacement=[...game.population.actors.values()][0];
  await wait(()=>first.binary.some(p=>freeID(p)===replacement.id),'Replacement never reached the real client socket');
  check(replacement.id!==actor.id,'Replacement reused an active actor identity');
  check(game.peers.size===1&&game.population.actors.size===1,'Population exceeded shared authority/count boundaries');
  first.socket.close();await wait(()=>game.peers.size===0,'Final client did not disconnect');
  check(game.population.interest.size===0,'Final socket leaked NPC interest');
 }finally{
  for(const client of clients)client.socket.close();for(const peer of game?.peers||[])peer.close();
  if(server)await new Promise(resolve=>server.close(resolve));
  if(game){clearInterval(game.tick);clearInterval(game.projectileTimer);game.flushSync();}
  fs.rmSync(temporary,{recursive:true,force:true});
 }
}
(async()=>{
 await scenario(false);await scenario(true);
 console.log('PASS actual backend/WebSocket population retention '+checks+' checks; authored graph/geometry, not a rendered native/browser or retail comparison');
})().catch(error=>{console.error(error);process.exitCode=1;});
