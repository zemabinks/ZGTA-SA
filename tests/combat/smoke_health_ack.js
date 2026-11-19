#!/usr/bin/env node
'use strict';
// Actual backend state transitions, synthetic accounts; no owner assets/listener.
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),os=require('node:os');
const temporary=fs.mkdtempSync(path.join(os.tmpdir(),'zgta-health-ack-')),originalNow=Date.now;
let game,now=1_700_000_000_000,checks=0;
const check=(value,label)=>{checks++;assert(value,label);};
try {
 Date.now=()=>now;
 const local=path.join(temporary,'local-only/selfhost');fs.mkdirSync(local,{recursive:true});
 for(const file of ['selfhost_backend.js','player_placement.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js'])fs.copyFileSync(path.join(require('node:path').resolve(__dirname, '../..'),file),path.join(temporary,file));
 fs.writeFileSync(path.join(local,'client-catalog.json'),JSON.stringify({vehicles:[],homes:[]}));
 fs.writeFileSync(path.join(local,'weapon-catalog.json'),JSON.stringify({items:[],shops:[]}));
 game=require(path.join(temporary,'selfhost_backend.js'));
 function peer(negotiated=true) {
  const account=game.ensurePlayer({headers:{}},{setHeader(){}}),packets=[];
  const p={player:account.player,ready:false,closed:false,lastSeen:now,
   state:{walking:true,x:1480,y:-1738,z:13},send:message=>packets.push(structuredClone(message)),packets};
  p.player.armour=25;game.peers.add(p);
  game.onMessage(p,{t:'hi',nativeInventory:true,inventoryAck:1,...(negotiated?{healthAck:1}:{})});return p;
 }
 const p=peer(),hello=p.packets.find(m=>m.t==='hello');
 check(hello.healthAck.connection===p.inventoryConnection && hello.healthAck.processed===0,'hello health namespace differs from live peer');
 const request=(s,kind='hurt',damage=10,c=p.inventoryConnection)=>game.onMessage(p,{t:'selfHealth',s,kind,damage,c});
 const reply=()=>p.packets.filter(m=>m.t==='vitals').at(-1);
 const initial=game.gameplayState(p.player,p);
 request(1,'hurt',40);check(p.player.health===60 && p.player.armour===25,'fall used armour or did not hurt');
 check(reply().healthAck.processed===1 && reply().healthAck.revision>initial.healthAck.revision,'accepted fall did not advance snapshot identity');
 request(1,'hurt',40);check(p.player.health===60,'duplicate fall was charged twice');
 const old=structuredClone(reply());p.player.health-=10;
 const serverHit=game.healthState(p);request(2,'hurt',20);
 check(p.player.health===30 && serverHit.health===50,'concurrent server and local damage did not compose');
 check(reply().healthAck.revision>serverHit.healthAck.revision && old.health===60,'snapshot mutable or revision not monotonic');
 const current=game.gameplayState(p.player,p);
 check(current.health===30 && current.healthAck.processed===2,'HTTP omitted current health ACK');
 check(!('healthAck' in game.gameplayState(p.player)),'unbound public HTTP exposed peer correlation');
 request(3,'hurt',10,'expired-connection');check(p.player.health===30 && p.processedHealthSequence===2,'old connection mutated health');
 request(4,'hurt',10);check(p.player.health===30 && p.processedHealthSequence===2,'out-of-order request skipped a loss');
 request(3,'hurt',5);check(p.player.health===25,'next contiguous request failed');
 let sequence=4;
 for(const damage of [0,-1,1.5,101,NaN,Infinity,'10',true]) {
  request(sequence++,'hurt',damage);check(p.player.health===25,'malformed environmental damage was accepted');
 }
 const priorDeaths=p.player.deaths;
 request(sequence++,'hurt',100);check(p.player.health===0 && p.player.deaths===priorDeaths+1,'fatal damage not recorded exactly once');
 request(sequence-1,'hurt',100);check(p.player.deaths===priorDeaths+1,'fatal duplicate repeated death');
 request(sequence++,'hurt',100);check(p.player.deaths===priorDeaths+1,'dead player was killed again');
 now+=1000;request(sequence++,'respawn',0);check(p.player.health===0,'respawn skipped existing cooldown');
 now+=2001;
 game.onMessage(p,{t:'me',walking:true,x:1480,y:-1738,z:13,health:100});
 check(p.player.health===0,'periodic native pose bypassed the acknowledged respawn');
 request(sequence++,'respawn',0);check(p.player.health===100 && p.player.armour===0,'acknowledged respawn failed');
 const after=game.healthState(p);check(after.healthAck.processed===sequence-1,'respawn ACK lost request ordering');
 request(sequence++,'respawn',0);check(p.player.health===100,'live player respawn changed health');
 p.player.health=75;p.player.armour=50;const healed=game.healthState(p);
 check(healed.healthAck.revision>after.healthAck.revision && healed.health===75 && healed.armour===50,'server-side healing/armour change did not version');
 const legacy=peer(false);check(!legacy.packets.find(m=>m.t==='hello').healthAck,'legacy negotiation changed');
 game.onMessage(legacy,{t:'me',walking:true,x:1480,y:-1738,z:13,health:63});
 check(legacy.player.health===63,'legacy browser/native absolute health stopped working');
 game.onMessage(legacy,{t:'selfHealth',c:legacy.inventoryConnection,s:1,kind:'hurt',damage:63});
 check(legacy.player.health===63,'unnegotiated peer used acknowledged damage');
 game.flushSync();const saved=fs.readFileSync(path.join(local,'players.json'),'utf8');
 check(!saved.includes('healthAck') && !saved.includes('processedHealthSequence'),'ephemeral health namespace leaked into account saves');
 console.log(`PASS health ACK backend: ${checks} actual handler checks; environmental armour bypass, simultaneous damage, duplicates, stale nonce, gaps, malformed amounts, fatal/respawn, HTTP revisions and legacy compatibility`);
} finally {
 Date.now=originalNow;
 if(game){clearInterval(game.tick);clearInterval(game.projectileTimer);game.flushSync();}
 fs.rmSync(temporary,{recursive:true,force:true});
}
