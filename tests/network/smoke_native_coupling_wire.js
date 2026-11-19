'use strict';
// Disposable protocol peer; no game assets, saves or production ports.
const http=require('node:http'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{spawn}=require('node:child_process');
let child,joins=0,hitches=0,finished=false;const sockets=new Set(),observed=[];
const link=(parent,trailer,kind='trailer')=>({parent,trailer,kind});
const first=link('cab','first'),second=link('first','second');
function send(socket,value){if(socket.destroyed)return;const b=Buffer.from(JSON.stringify(value));let h;if(b.length<126)h=Buffer.from([129,b.length]);else{h=Buffer.alloc(4);h[0]=129;h[1]=126;h.writeUInt16BE(b.length,2)}socket.write(Buffer.concat([h,b]));}
function topology(p,revision,links,ack){send(p.socket,{t:'couplings',state:{revision,links},...(ack?{ack}: {})});}
function ack(p,sequence,accepted=true,processed=sequence){return{connection:p.nonce,sequence,processed,accepted};}
function all(p){send(p.socket,{t:'inventory',state:{revision:0,selected:0,weapons:[],ack:{connection:p.nonce,processedShot:0}}});send(p.socket,{t:'all',you:'Coupling fixture',cash:0,cars:[],vehicles:[],chat:[]});}
function note(p,text){send(p.socket,{t:'note',text});}
function receive(p,m){
 if(m.t==='hi'){
  assert.equal(m.inventoryAck,1);assert.equal(m.couplingAck,1);p.index=++joins;p.nonce='coupling-'+p.index;
  assert(p.index<=3,'Unexpected transport retry');
  if(p.index===3)topology(p,500,[link('premature','state')]);
  send(p.socket,{t:'hello',inventoryAck:1,inventoryConnection:p.nonce,spot:[1,2,3,0],life:[100,0],...(p.index===1?{}:{couplingAck:1})});
  if(p.index===3){topology(p,0,[]);setTimeout(()=>all(p),30)}else all(p);
  return;
 }
 if(m.t==='ping'){send(p.socket,{t:'pong',c:m.c,s:Date.now()});return;}
 if(m.t==='me'){
  if(m.say==='BASELINE PLEASE'){assert.equal(p.index,2);topology(p,0,[]);return;}
  if(m.driving){p.pose=true;observed.push(['driving',m.w]);if(m.w!==undefined)assert([0,2500].includes(m.w));}
  else if(m.parked){observed.push(['parked',m.parked.w]);if(m.parked.w!==undefined)assert.equal(m.parked.w,0);}
  else {assert.equal(m.w,undefined,'Vehicle working-part field leaked into pedestrian state');observed.push(['foot']);}
  return;
 }
 if(m.t==='vmove'){p.moved=true;assert.equal(m.v,'first');assert.equal(m.w,2500);return;}
 if(m.t!=='hitch')return;
 hitches++;assert.equal(m.c,p.nonce);assert.equal(m.s,++p.sequence,'Invalid requests left a sequence hole or a duplicate hello reset it');
 assert(p.index>1,'Legacy server received a hitch');
 if(p.index===2){
  if(m.s===1){
   assert(p.pose&&p.moved,'Hitch preceded fresh driver/trailer state');assert.deepEqual([m.v,m.tr,m.kind],['cab','first','trailer']);
   const bad=[
    {revision:1,links:[link('cab','cab')]},
    {revision:1,links:[first,link('cab','other')]},
    {revision:1,links:[first,link('other','first')]},
    {revision:1,links:[first,link('first','cab')]},
    {revision:1,links:[first,second,link('second','third')]},
    {revision:1,links:[link('tow','car','tow'),link('car','tail')]},
    {revision:1,links:[link('root','tow'),link('tow','car','tow')]},
    {revision:1,links:[link('','first')]},
    {revision:1,links:[link('cab','x'.repeat(65))]},
    {revision:1,links:[link('cab','bad\u0000id')]},
    {revision:1,links:[link('cab','first','invented')]},
    {revision:true,links:[]},{revision:-1,links:[]},{revision:0.5,links:[]},
    {revision:1,links:Array.from({length:257},(_,i)=>link('p'+i,'t'+i))}
   ];
   for(const state of bad)send(p.socket,{t:'couplings',state,ack:ack(p,1)});
   topology(p,1,[first],{...ack(p,1),connection:'stale-peer'});
   topology(p,1,[first],{...ack(p,1),sequence:2,processed:2});
   topology(p,1,[first],{...ack(p,1),accepted:1});
   topology(p,1,[first],{...ack(p,1),processed:0});
   note(p,'INVALID TOPOLOGIES CHECK');topology(p,1,[first],ack(p,1));
  }else if(m.s===2){
   assert.equal(m.tr,null,'Detach must encode explicit null');
   topology(p,1,[link('cab','alternate')],ack(p,2)); // contradictory equal revision
   note(p,'CONTRADICTORY CHECK');topology(p,1,[first],ack(p,2,false));
  }else if(m.s===3){
   assert.deepEqual([m.v,m.tr],['first','second']);
   topology(p,1,[first],ack(p,2,false)); // duplicate prior acknowledgement
   topology(p,2,[second,first]);
   send(p.socket,{t:'hello',inventoryAck:1,inventoryConnection:p.nonce,couplingAck:0,spot:[999,999,999,0],life:[100,0]});
   topology(p,1,[first],ack(p,3));note(p,'STALE REVISION CHECK');
   topology(p,2,[first,second],ack(p,3));
  }else if(m.s===4){
   assert.equal(m.tr,null);topology(p,3,[first],ack(p,4));
  }else throw Error('Uncertain request replayed');
 }else{
  assert.equal(m.s,1,'Fresh peer inherited issued sequence');assert.deepEqual([m.v,m.tr,m.kind],['tow','car','tow']);
  topology(p,99,[link('old','peer')],{connection:'coupling-2',sequence:4,processed:4,accepted:true});
  topology(p,0,[link('contradictory','state')],ack(p,1));
  note(p,'OLD NONCE CHECK');topology(p,1,[link('tow','car','tow')],ack(p,1));
 }
}
const server=http.createServer();server.on('upgrade',(req,socket)=>{
 sockets.add(socket);socket.on('close',()=>sockets.delete(socket));socket.on('error',()=>{});
 socket.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+crypto.createHash('sha1').update(req.headers['sec-websocket-key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64')+'\r\n\r\n');
 const p={socket,sequence:0};let pending=Buffer.alloc(0);
 socket.on('data',chunk=>{pending=Buffer.concat([pending,chunk]);while(pending.length>=2){let length=pending[1]&127,offset=2;if(length===126){if(pending.length<4)return;length=pending.readUInt16BE(2);offset=4}assert.notEqual(length,127);const mask=pending[1]&128?pending.subarray(offset,offset+4):null;if(mask)offset+=4;if(pending.length<offset+length)return;const opcode=pending[0]&15,b=Buffer.from(pending.subarray(offset,offset+length));pending=pending.subarray(offset+length);if(mask)for(let i=0;i<b.length;i++)b[i]^=mask[i%4];if(opcode===1)receive(p,JSON.parse(b));else if(opcode===8){socket.end();return}}});
});
function stop(){for(const s of sockets)s.destroy();server.close();}
server.listen(0,'127.0.0.1',()=>{
 child=spawn(process.argv[2],['http://127.0.0.1:'+server.address().port],{stdio:'inherit'});
 child.on('exit',code=>{stop();assert.equal(code,0);assert.equal(joins,3);assert.equal(hitches,5);assert(observed.some(r=>r[0]==='driving'&&r[1]===0));assert(observed.some(r=>r[0]==='driving'&&r[1]===2500));assert(observed.some(r=>r[0]==='driving'&&r[1]===undefined));assert(observed.some(r=>r[0]==='parked'&&r[1]===0));assert(observed.some(r=>r[0]==='parked'&&r[1]===undefined));finished=true;console.log('PASS real coupling wire: 3 namespaces/5 hitch requests, malformed topology/ACK rejection, legacy compatibility, uncertain drop, work field/pose ordering')});
});
setTimeout(()=>{if(!finished){child?.kill();stop();throw Error('Coupling wire timeout')}},55000).unref();
