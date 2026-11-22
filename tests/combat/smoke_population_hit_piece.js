// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Actual backend handlers, inventory tickets, population task and packet codec.
// Catalog, pavement, geometry clearance, clock and transports are authored
// boundaries. No original files, rendered client or retail timings are used.
const assert=require('node:assert/strict'),fs=require('node:fs'),os=require('node:os'),path=require('node:path');
const root=path.resolve(process.argv[2]||path.join(__dirname,'../..'));
const {Pedestrians}=require(path.join(root,'server/population/pedestrians'));
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-npc-hit-piece-')),originalNow=Date.now;
let game,now=1700000000000,checks=0;const evidence=[];
const check=(value,message)=>{assert(value,message);checks++;};
try{
 Date.now=()=>now;
 for(const name of ['selfhost_backend.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js','player_placement.js'])
  fs.copyFileSync(path.join(root,name),path.join(temporary,name));
 const local=path.join(temporary,'local-only/selfhost');fs.mkdirSync(local,{recursive:true});
 fs.writeFileSync(path.join(local,'client-catalog.json'),JSON.stringify({vehicles:[],homes:[]}));
 fs.writeFileSync(path.join(local,'weapon-catalog.json'),JSON.stringify({items:[
  {id:22,name:'Authored pistol',ammo:40,capacity:40,price:0,slot:2,fire:'INSTANT_HIT',stats:{range:40,pellets:1,damage:7,loop:[0,9,0]}},
  {id:24,name:'Authored terminal shot',ammo:5,capacity:5,price:0,slot:2,fire:'INSTANT_HIT',stats:{range:40,pellets:1,damage:100,loop:[0,9,0]}}
 ],shops:[]}));
 game=require(path.join(temporary,'selfhost_backend.js'));
 let cover=false;require(path.join(temporary,'world_collision.js')).lineOfSight=()=>!cover;
 const graph={crc32:'00000000',point:id=>[1574+id,-2460,13.6],nearest:()=>({id:0,distance:0}),neighbors:id=>[{id:id^1,kind:0}]};
 game.population=new Pedestrians({graph,models:[14],ground:()=>13.6,clear:()=>true,random:()=>0,maximum:1,perObserver:1});
 const account=game.ensurePlayer({headers:{cookie:''}},{setHeader(){}}),packets=[],binary=[];
 const peer={id:account.id,player:account.player,ready:false,lastSeen:now,closed:false,
  state:{walking:true,skin:14,x:1570,y:-2460,z:13.6,weapon:22},send:packet=>packets.push(structuredClone(packet)),sendBinary:packet=>binary.push(Buffer.from(packet))};
 game.peers.add(peer);game.onMessage(peer,{t:'hi',nativeInventory:true,inventoryAck:1,ordinaryShots:1,npcProtocol:38});
 check(peer.ordinaryShotGroupsEnabled===true,'Actual grouped authority did not negotiate');
 peer.player.inventory={selected:22,weapons:{22:{clip:40,rest:0}},lastShotAt:now-1000};
 game.publishPopulation(now,true);const actor=[...game.population.actors.values()][0],target='p'+actor.id;
 check(actor&&binary.some(packet=>packet[0]===10),'Fixture did not create/publish the actual NPC');
 const baseline={time:now,free:binary.find(packet=>packet[0]===10).toString('base64'),
  packet:binary.find(packet=>packet[0]===11).toString('base64')};
 const origin=[1570,-2460,14.95],hit=[1574,-2460,14.7];let sequence=0;
 const latest=()=>packets.filter(packet=>packet.t==='inventory').at(-1);
 function shoot(piece,{ordinary=true,weapon=22,extra={}}={}){
  now+=500;peer.lastSeen=now;
  const group={o:origin,h:hit,ht:1,id:target,n:1,...(piece===undefined?{}:{bp:piece})};
  game.onMessage(peer,{t:'shot',w:weapon,c:peer.inventoryConnection,s:++sequence,o:origin,h:hit,
   ...(ordinary?{rays:[group]}:{}),...extra});
  return latest();
 }
 function statePiece(expected,label){
  check(actor.hitPiece===expected,'Accepted NPC shot lost its body piece: '+label);
  const more=binary.filter(packet=>packet[0]===11).at(-1),header=more[1]&128?3:2;
  const packed=more[header+6],piece=packed>>5;
  check((piece===0?0:piece+2)===expected,'Actual supplemental packet lost the admitted body piece: '+label);
  check((packed&31)===actor.hitCounter,'Supplemental hit counter differs from the authoritative task');
  evidence.push({label,expected,counter:actor.hitCounter,health:actor.health,time:now,
   free:binary.filter(packet=>packet[0]===10).at(-1).toString('base64'),packet:more.toString('base64')});
 }
 for(const piece of [0,1,2,10,-1,1.5,NaN,Infinity,'9']){
  const health=actor.health,counter=actor.hitCounter;
  check(!game.population.damage(target,7,{weapon:22,from:origin,now,piece}),'Invalid internal piece was allowed to break protocol publication');
  check(actor.health===health&&actor.hitCounter===counter,'Invalid internal piece partially mutated the task');
 }
 for(const piece of [9,3,4,5,6,7,8]){
  const health=actor.health,clip=peer.player.inventory.weapons[22].clip,counter=actor.hitCounter;
  check(shoot(piece).result.accepted===true,'Valid body-piece emission was rejected');
  check(actor.health===health-7&&peer.player.inventory.weapons[22].clip===clip-1,'Body-piece metadata changed catalog damage or ammunition');
  check(actor.hitCounter===((counter+1)&31),'One emission did not produce exactly one reaction');
  statePiece(piece,'group-'+piece);
  game.onMessage(peer,{t:'hit',w:22,c:peer.inventoryConnection,s:sequence,to:target,bp:piece===9?3:9});
  check(actor.health===health-7&&actor.hitPiece===piece,'Settled ticket was rewritten by a late body-piece claim');
 }
 // Existing grouped admission allows 1/2, which protocol38 cannot represent.
 // Preserve their old torso presentation without rejecting otherwise valid damage.
 for(const piece of [undefined,1,2]){
  check(shoot(piece).result.accepted===true,'Compatible absent/legacy piece was rejected');statePiece(3,'compatible-'+piece);
 }
 for(const bad of [0,10,-1,1.5,NaN,'9']){
  const health=actor.health,counter=actor.hitCounter,clip=peer.player.inventory.weapons[22].clip;
  check(shoot(bad).result.accepted===false,'Malformed body piece was admitted');
  check(actor.health===health&&actor.hitCounter===counter&&peer.player.inventory.weapons[22].clip===clip,'Malformed group partially changed NPC state');
 }
 // The hit message itself grants no piece authority. Older emissions still
 // use the established torso fallback after their normal hit claim succeeds.
 const prior=actor.health;check(shoot(undefined,{ordinary:false}).result.accepted===true,'Legacy emission rejected');
 game.onMessage(peer,{t:'hit',w:22,c:peer.inventoryConnection,s:sequence,to:target,bp:9});
 check(actor.health===prior-18,'Legacy hit changed its retained damage policy');statePiece(3,'untrusted-late-bp');
 const health=actor.health,counter=actor.hitCounter;cover=true;
 check(shoot(9).result.accepted===true,'Occluded emission should settle without target damage');
 check(actor.health===health&&actor.hitCounter===counter,'Blocked shot invented a reaction');cover=false;
 game.onMessage(peer,{t:'hit',w:22,c:peer.inventoryConnection,s:sequence,to:target,bp:9});
 check(actor.health===health&&actor.hitCounter===counter,'Occluded settled ticket became a delayed reaction');
 check(shoot(9,{extra:{c:'stale-connection'}}).result.accepted===false,'Stale connection gained body-piece authority');
 check(actor.health===health&&actor.hitCounter===counter,'Stale connection changed the task');
 peer.player.inventory={selected:24,weapons:{24:{clip:5,rest:0}},lastShotAt:now-1000};
 check(shoot(9,{weapon:24}).result.accepted===true,'Terminal head emission rejected');
 check(actor.health===0&&(actor.flags&9)===9&&actor.speed===0,'Terminal hit failed the actual death task');statePiece(9,'terminal-head');
 check(!game.population.damage(target,7,{weapon:22,from:origin,now,piece:4}),'Dead task accepted another reaction');
 if(process.argv[3])fs.writeFileSync(process.argv[3],JSON.stringify({checks,baseline,evidence,scope:'Authored catalog/graph/geometry and actual backend/ticket/task/binary producer; no native rendering or retail comparison'},null,2));
 console.log('PASS NPC body-piece authority '+checks+' checks; admitted ticket metadata, exact packet pieces, replay/default/blocked/death policies; no render or retail claim');
}finally{
 Date.now=originalNow;
 if(game){clearInterval(game.tick);clearInterval(game.projectileTimer);clearTimeout(game.saveTimer);}
 fs.rmSync(temporary,{recursive:true,force:true});
}
