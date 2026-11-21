#!/usr/bin/env node
'use strict';
// Disposable original-protocol service fixture. No original backend, account,
// credential or game assets are copied into this test.
const http=require('node:http'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{spawn}=require('node:child_process');
let child,done=false,connections=0,checks=0;const peers=[];let originalFlow=false,reconnected=false,strictDefault=false,negotiatedDefault=false;
function check(value,message){checks++;assert(value,message)}
function frame(tag,p){return Buffer.concat([p.length<128?Buffer.from([tag,p.length]):Buffer.from([tag,(p.length&127)|128,p.length>>7]),p])}
const u16=n=>{let b=Buffer.alloc(2);b.writeUInt16BE(n);return b},u32=n=>{let b=Buffer.alloc(4);b.writeUInt32BE(n>>>0);return b},i32=n=>{let b=Buffer.alloc(4);b.writeInt32BE(n);return b},i16=n=>{let b=Buffer.alloc(2);b.writeInt16BE(n);return b};
function row(id='7'){let x=Array(44).fill(null);Object.assign(x,{0:id,1:'Browser peer',2:'s7',3:10,4:20,5:30,6:0,16:Date.now(),18:100,27:22,30:0,31:7});return x}
function full(id='7'){return frame(1,Buffer.concat([u16(3),Buffer.from(JSON.stringify(row(id)))]))}
function delta(id=7){return frame(2,Buffer.concat([u16(id),u16(3),u16(0),u32(Date.now()),i32(21000),i32(22000),i32(23000),i16(1500),i16(0),i16(0),i16(0),u16(99),Buffer.from([8])]))}
function send(p,m,binary=false){if(p.s.destroyed)return;const b=binary?m:Buffer.from(JSON.stringify(m)),h=b.length<126?Buffer.from([binary?130:129,b.length]):Buffer.from([binary?130:129,126,b.length>>8,b.length&255]);p.s.write(Buffer.concat([h,b]))}
const vehicle=['taxi','Taxi','420.6.1.0.',1,2,3,0.7,0,0,1000,null,null,null,null,17];
function traffic(){
 // Independently authored loopback fixture bytes; no captured server records
 // or original game resources are embedded in this test.
 const stamp=u32(Date.now()),id=u16(17);
 return Buffer.concat([
  frame(4,Buffer.concat([stamp,id,u16(420),Buffer.from([6,1]),u16(0),u16(1),u16(65535),u16(0),u16(32768),Buffer.from([16,20,16])])),
  frame(9,Buffer.concat([id,Buffer.from([240,16,225,4])])),
  frame(33,Buffer.concat([id,Buffer.from([0,0])])),
  frame(36,Buffer.concat([stamp,id,i32(4000),i32(5000),i16(48),u16(16384),i16(-128),i16(128),Buffer.from([16,240])])),
  frame(34,Buffer.concat([id,Buffer.from([2]),u16(2),Buffer.from([1]),u16(3),Buffer.from([2])])),
  frame(37,Buffer.concat([id,u16(64),u16(128)])),
  frame(6,Buffer.concat([id,Buffer.from([2]),Buffer.from('QA')])),
  frame(31,Buffer.concat([id,Buffer.from([22]),i32(1000),i32(2000),i32(3000),Buffer.from([1,0,0])])),
  frame(5,id),
 ]);
}
function received(p,m){
 if(m.t==='hi'){
  if(p.index===6){
   check(m.inventoryAck===1&&m.npcProtocol===38,'Default inventory/population capabilities');
   const nonce='traffic-peer-000000000000';p.baseline=true;
   send(p,{t:'hello',inventoryAck:1,inventoryConnection:nonce,npcProtocol:38,traffic:1,roads:'1234abcd',life:[100,0]});
   send(p,traffic(),true);send(p,{t:'gangs',g:[['authored',0,[7],[420]]]});
   send(p,{t:'inventory',state:{revision:0,selected:0,weapons:[],ack:{connection:nonce,processedShot:0}}});
   send(p,{t:'all',you:'Negotiated traffic peer',cash:0,cars:[],vehicles:[],chat:[]});negotiatedDefault=true;return;
  }
  if(p.index===5){check(m.inventoryAck===1,'Default capability remains strict');send(p,{t:'hello',protocol:38,life:[100,0]});send(p,{t:'gangs',g:[['authored',0,[7],[420]]]});send(p,{t:'guns',w:[]});send(p,{t:'all',you:'Wrong service',cash:0,cars:[],vehicles:[],chat:[]});strictDefault=true;return}
  check(m.b==='202611100434','Versioned original hello');check(!('inventoryAck'in m)&&!('nativeInventory'in m),'No fake ACK capabilities');check(m.c&&Object.keys(m.c).length===0,'No unimplemented AI capability');
  check(new URL('http://fixture'+p.url).searchParams.get('device')==='a'.repeat(32),'Original device query');
  if(p.index===1){send(p,{t:'login'});return}
  if(p.index===2){send(p,{t:'hello',protocol:39});return}
  send(p,{t:'hello',protocol:38,time:Date.now(),life:p.index===3?[83.25,2.45]:[100,0],spot:[1,2,3,0.7],day:{shift:1,hold:null},weather:2,traffic:p.index===3?1:0,...(p.index===3?{roads:'1234abcd'}:{})});
  if(p.index===3){
   send(p,full(),true);send(p,delta(),true);send(p,{t:'all',protocol:38,you:'Original fixture',cash:50,time:Date.now(),near:[['7',3,0]],vehicles:[vehicle],chat:[[1,'Browser peer','Hello']],heard:1,traffic:3});
   send(p,traffic(),true);send(p,{t:'traffic',level:2});send(p,{t:'gangs',g:[['authored',0,[7],[420]]]});
   send(p,{t:'guns',w:[[22,null]]});setTimeout(()=>{p.baseline=true;send(p,{t:'guns',w:[[22,20]],back:false});for(let i=0;i<10;i++)send(p,{t:'hit',d:0.1,w:22,from:'7'});send(p,{t:'hit',d:0.2,w:53});send(p,{t:'hit',d:0.3,w:54});send(p,{t:'note',text:'FRACTIONAL HITS'})},100);
  }else{check(p.index===4,'No unexpected connection');send(p,{t:'all',you:'Original reconnected',cars:[],vehicles:[],chat:[],cash:10});setTimeout(()=>{p.baseline=true;send(p,{t:'guns',w:[]})},75)}
  return;
 }
 if(m.t==='ping'){send(p,{t:'pong',c:m.c,s:Date.now()});return}
 if(m.t==='board')return;
 if(p.index===6){check(m.t==='me','Unexpected negotiated-default gameplay request');return}
 check(p.baseline,'No gameplay before hello/world/guns baseline');
 check(!('inventoryAck'in m)&&!('nativeInventory'in m),'No hidden ACK in original data');
 if(p.index===4){
  check(m.t==='me'&&m.walking&&m.shots===0&&!m.say,'Reconnect drops prior shots/chat');reconnected=true;send(p,{t:'note',text:'RECONNECTED COMPLETE'});return;
 }
 if(m.t==='shot'){check(m.w===22&&m.ht===1&&m.id==='7','Original shot target');check(!('c'in m)&&!('s'in m),'No fake shot ACK');p.shots++;return}
 if(m.t==='hit'){check(m.to==='7'&&m.n===1&&!('c'in m)&&!('s'in m),'Original melee shape');p.melee++;return}
 if(m.t==='guns'){check(JSON.stringify(m.w)==='[[22,19]]','Original carried total after paid local shot');p.guns++;return}
 if(m.t==='enter'){check(m.v==='taxi','Actual vehicle request');send(p,{t:'enter',v:'taxi',ok:true});return}
 if(m.t==='exit'){
  check(m.v==='taxi'&&m.hp===900&&m.d==='fixture','Original vehicle release health/damage');check(Math.abs(m.h+0.7)<1e-6&&Math.abs(m.r+0.2)<1e-6&&Math.abs(m.p-0.1)<1e-6,'Original body orientation signs');check(!('heading'in m)&&!('health'in m),'Explicit release uses correct field names');p.exits++;return;
 }
 if(m.t==='me'){
  check(/^[0-9a-f]{32}$/.test(m.key),'Original per-client world key');check(Number.isFinite(m.clock),'Original packet clock');
  if(m.walking&&m.health===0)p.deadPosition=true;
  if(m.driving){check(m.life===83&&m.armour===2,'Fractional vitals ceil only at wire boundary');p.livingReport=true}
  if(m.walking&&Math.abs(m.heading+1.9)<1e-6)p.actorHeading=true;
  if(m.say){check(m.say==='/help'&&m.heard===1,'Original queued chat and heard ACK');p.chat++;}
  return;
 }
 if(m.t==='died'){check(p.deadPosition,'Death reports current zero-health state before died');check(++p.deaths===1,'Death deduplicated');send(p,{t:'note',text:'REQUEST RESPAWN'});return}
 if(m.t==='escape'){
  check(m.c==='respawn','Original respawn request');p.respawns++;
  if(p.respawns===1){check(p.deaths===0,'First approved escape is alive');send(p,{t:'escape',c:'respawn',go:true})}
  else if(p.respawns===2){check(p.deaths===1,'Denied request follows death');send(p,{t:'escape',c:'respawn',go:false,no:'other'})}
  else{check(p.respawns===3,'Respawn retry bounded');send(p,{t:'guns',w:[[24,8]],back:true});send(p,{t:'escape',c:'respawn',go:true});setTimeout(()=>send(p,delta(88),true),30);}
  return;
 }
 if(m.t==='who'){
  check(Array.isArray(m.ids)&&m.ids.every(id=>id==='7'||id==='88'),'Only known stale/missing fixture baselines requested');
  if(m.ids.includes('7'))send(p,full('7'),true);
  if(!m.ids.includes('88'))return;
  check(m.ids.includes('88'),'Missing binary baseline resync '+JSON.stringify(m)+' respawns='+p.respawns);check(p.shots===1&&p.melee===1&&p.guns===1&&p.exits===1&&p.chat===1&&p.actorHeading&&p.livingReport,'Gameplay flow completed');
  send(p,full('88'),true);for(const invalid of [1,0,false,'true'])send(p,{t:'spawned',v:['arbitrary-registered','owner','420.6.1.0.',4,5,6,0,0,0,900,null,null,null,null,17],in:invalid});send(p,{t:'spawned',v:['arbitrary-registered','owner','420.6.1.0.',4,5,6,0,0,0,900,null,null,null,null,17],in:true});originalFlow=true;send(p,{t:'note',text:'RECONNECT NOW'});return;
 }
 throw Error('Unexpected original packet '+JSON.stringify(m));
}
const server=http.createServer();server.on('upgrade',(req,s)=>{
 const p={s,index:++connections,url:req.url,baseline:false,shots:0,melee:0,guns:0,exits:0,chat:0,deaths:0,respawns:0};peers.push(p);check(connections<=6,'Bounded test connections');
 s.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+crypto.createHash('sha1').update(req.headers['sec-websocket-key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64')+'\r\n\r\n');
 let pending=Buffer.alloc(0);s.on('data',chunk=>{pending=Buffer.concat([pending,chunk]);while(pending.length>=2){let length=pending[1]&127,start=2;if(length===126){if(pending.length<4)return;length=pending.readUInt16BE(2);start=4}if(length===127)throw Error('Unexpected large fixture packet');const masked=!!(pending[1]&128),mask=masked?pending.subarray(start,start+4):null;if(masked)start+=4;if(pending.length<start+length)return;const opcode=pending[0]&15,payload=Buffer.from(pending.subarray(start,start+length));pending=pending.subarray(start+length);if(masked)for(let i=0;i<length;i++)payload[i]^=mask[i%4];if(opcode===1)received(p,JSON.parse(payload));else if(opcode===8){s.end();return}}});s.on('error',()=>{});
});
server.listen(0,'127.0.0.1',()=>{child=spawn(process.argv[2],['http://127.0.0.1:'+server.address().port],{stdio:'inherit'});child.on('exit',(code,signal)=>{if(code!==0)console.error('Swift original fixture failed:',{code,signal});done=true;for(const p of peers)p.s.destroy();server.close();check(code===0,'Actual Swift client success');check(connections===6&&originalFlow&&reconnected&&strictDefault&&negotiatedDefault,'All isolation/join phases');console.log('PASS original/default protocol actual URLSession WebSocket fixture:',checks,'server checks')})});
setTimeout(()=>{if(!done){child?.kill();for(const p of peers)p.s.destroy();server.close();throw Error('Original wire fixture timeout')}},25000).unref();
