#!/usr/bin/env node
// SPDX-License-Identifier: AGPL-3.0-only
'use strict';
// Controlled protocol peer, not production authority. Only ephemeral loopback
// HTTP/WS and authored packets; no account, asset or existing save is loaded.
const http=require('node:http'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{spawn}=require('node:child_process');
let mode='strict',counter=0,current,child,finished=false,receivedCount=0;
const peers=[],history=[];
const vehicle=['fixture-cab','Authored cab','400',100,200,20,0,0,0,930,'',null,null,null,null,null,1234];
function send(p,value){if(p.socket.destroyed)return;const b=Buffer.from(JSON.stringify(value)),h=b.length<126?Buffer.from([129,b.length]):Buffer.from([129,126,b.length>>8,b.length&255]);p.socket.write(Buffer.concat([h,b]));}
function marker(p){send(p,{t:'note',text:'MARKER-'+p.marker++});}
function tp(p,revision,extra={}){return {t:'tp',x:300,y:400,z:20,h:90,placement:{connection:p.nonce,revision},...extra};}
function hello(p){const h={t:'hello',inventoryAck:1,inventoryConnection:p.nonce,spot:[100.125,200.5,20.75,.75],life:[p.mode.startsWith('dead')?0:73,11],healthAck:{connection:p.nonce,processed:0,revision:0,respawned:0}};
 if(p.mode!=='legacy'){h.positionAck=1;h.placement={connection:p.nonce,revision:0};}
 if(p.mode==='bad-bool')h.positionAck=true;
 if(p.mode==='bad-revision')h.placement.revision=true;
 if(p.mode==='bad-spot')h.spot[1]=true;
 if(p.mode==='bad-nonce')h.placement.connection='another-connection-000';
 if(p.mode==='bad-health')h.healthAck.processed=false;
 return h;
}
function received(p,m){receivedCount++;p.seen.push(m);history.push({connection:p.nonce,mode:p.mode,packet:m});
 if(m.t==='hi'){
  assert.equal(m.positionAck,1);assert.equal(m.inventoryAck,1);assert.equal(m.healthAck,1);
  p.hello=hello(p);send(p,p.hello);
  send(p,{t:'inventory',state:{revision:0,selected:0,weapons:[],ack:{connection:p.nonce,processedShot:0}}});
  send(p,{t:'all',you:'Authored placement peer',cash:0,cars:[],vehicles:[vehicle],chat:[]});
 }else if(m.t==='enter'){if(p.holdEntries){p.heldEntries ||= [];p.heldEntries.push(m);}else send(p,{...m,ok:true});}
 else if(m.t==='selfHealth'&&p.mode.startsWith('dead')){
  if(m.s===1){send(p,{t:'vitals',health:0,armour:11,healthAck:{connection:p.nonce,processed:1,revision:1,respawned:0}});marker(p);}
  else{assert.equal(m.s,2);send(p,tp(p,1));const ack={t:'vitals',health:100,armour:0,healthAck:{connection:p.nonce,processed:2,revision:2,respawned:2}};if(p.mode==='dead-late')send(p,tp(p,2,{x:500,h:180}));send(p,ack);if(p.mode==='dead')send(p,tp(p,2,{x:500,h:180}));send(p,ack);marker(p);}
 }
}
function respond(res,value){res.writeHead(200,{'Content-Type':'application/json'});res.end(JSON.stringify(value));}
const server=http.createServer((req,res)=>{let body='';req.on('data',b=>{body+=b;assert(body.length<1000000)});req.on('end',()=>{
 const value=body?JSON.parse(body):{};
 if(req.url==='/configure'){mode=value.mode;respond(res,{ok:true});}
 else if(req.url==='/seen'){respond(res,{packets:current?.seen||[],history,receivedCount,nonce:current?.nonce});}
 else if(req.url==='/emit'){for(const packet of value.packets)send(current,packet);marker(current);respond(res,{marker:current.marker-1});}
 else if(req.url==='/duplicate'){send(current,current.hello);send(current,{t:'hello',inventoryAck:1,inventoryConnection:current.nonce});marker(current);respond(res,{marker:current.marker-1});}
 else if(req.url==='/holdEntry'){current.holdEntries=true;current.heldEntries=[];respond(res,{ok:true});}
 else if(req.url==='/replyEntry'){const held=current.heldEntries.find(m=>m.request===value.request);assert(held,'Requested held entry missing');send(current,{...held,ok:value.accepted});marker(current);respond(res,{marker:current.marker-1});}
 else if(req.url==='/teleport'){send(current,tp(current,value.revision,value.extra));marker(current);respond(res,{marker:current.marker-1});}
 else{res.writeHead(404);res.end();}
 });});
server.on('upgrade',(req,socket)=>{
 const p={socket,nonce:'placement-peer-'+String(++counter).padStart(12,'0'),mode,seen:[],marker:1};peers.push(p);current=p;
 socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+crypto.createHash('sha1').update(req.headers['sec-websocket-key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64')+'\r\n\r\n');
 let pending=Buffer.alloc(0);socket.on('error',()=>{});socket.on('data',chunk=>{pending=Buffer.concat([pending,chunk]);while(pending.length>=2){
  let length=pending[1]&127,offset=2;if(length===126){if(pending.length<4)return;length=pending.readUInt16BE(2);offset=4;}
  assert(length!==127,'Unexpected oversized test packet');const masked=!!(pending[1]&128),mask=masked?pending.subarray(offset,offset+4):null;if(masked)offset+=4;
  if(pending.length<offset+length)return;const opcode=pending[0]&15,payload=Buffer.from(pending.subarray(offset,offset+length));pending=pending.subarray(offset+length);
  if(masked)for(let i=0;i<length;i++)payload[i]^=mask[i%4];if(opcode===1)received(p,JSON.parse(payload));else if(opcode===8){socket.end();return;}
 }});
});
server.listen(0,'127.0.0.1',()=>{
 child=spawn(process.argv[2],['http://127.0.0.1:'+server.address().port],{stdio:'inherit'});
 child.on('exit',code=>{for(const p of peers)p.socket.destroy();server.close();finished=true;assert.equal(code,0);console.log('PASS authored placement wire peer: '+counter+' connections, '+receivedCount+' actual native packets');});
});
setTimeout(()=>{if(!finished){child?.kill();for(const p of peers)p.socket.destroy();server.close();throw Error('Placement wire fixture timed out');}},50000).unref();
