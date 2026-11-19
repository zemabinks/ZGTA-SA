#!/usr/bin/env python3
"""Actual native stream-cylinder/cadence and local URLSession wire regression."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess,tempfile
from tests.movement.smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parents[2]
JS=r'''
const http=require('node:http'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{spawn}=require('node:child_process');
let child,done=false,connections=0;const peers=[];
function send(p,m){const b=Buffer.from(JSON.stringify(m)),h=b.length<126?Buffer.from([129,b.length]):Buffer.from([129,126,b.length>>8,b.length&255]);p.s.write(Buffer.concat([h,b]))}
function received(p,m){
 if(m.t==='hi'){assert.equal(m.inventoryAck,1);send(p,{t:'hello',inventoryAck:1,inventoryConnection:p.nonce,life:[100,0]});send(p,{t:'inventory',state:{revision:0,selected:37,weapons:[{id:37,clip:99,rest:0}],reload:null,ack:{connection:p.nonce,processedShot:0}}});setTimeout(()=>{p.ready=true;send(p,{t:'all',you:'Stream peer',cash:0,cars:[],vehicles:[],chat:[]})},50);return}
 if(!['ping','board'].includes(m.t))assert(p.ready,'Stream claim before all/inventory ready');
 if(m.t==='shot'){
  assert.equal(m.c,p.nonce);assert.equal(m.s,++p.sequence);p.shots.set(m.s,m.w);
  assert.equal(m.w,p.index===1?[37,22,42,41][m.s-1]:42);return;
 }
 if(m.t==='hit'){
  assert.equal(m.c,p.nonce);assert.equal(m.w,p.shots.get(m.s),'Claim must follow that exact shot');
  const key=m.s+':'+m.to;assert(!p.hits.has(key),'Duplicate victim');p.hits.add(key);
  if(p.index===1){
   assert(['1:A','1:B','2:C','4:A','4:B'].includes(key),'Unexpected/early stream claim '+key);
   if(p.hits.size===5){assert.equal(p.sequence,4);send(p,{t:'note',text:'STREAM ROUND ONE'})}
  }else{assert(['1:A','1:B'].includes(key));if(p.hits.size===2)send(p,{t:'note',text:'STREAM COMPLETE'})}
 }
}
const server=http.createServer();server.on('upgrade',(req,s)=>{
 const p={s,index:++connections,nonce:'stream-'+connections,sequence:0,shots:new Map,hits:new Set};peers.push(p);assert(connections<=2);
 s.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+crypto.createHash('sha1').update(req.headers['sec-websocket-key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64')+'\r\n\r\n');
 let pending=Buffer.alloc(0);s.on('data',chunk=>{pending=Buffer.concat([pending,chunk]);while(pending.length>=2){let length=pending[1]&127,start=2;if(length===126){if(pending.length<4)return;length=pending.readUInt16BE(2);start=4}assert(length!==127);const masked=!!(pending[1]&128),mask=masked?pending.subarray(start,start+4):null;if(masked)start+=4;if(pending.length<start+length)return;const opcode=pending[0]&15,payload=Buffer.from(pending.subarray(start,start+length));pending=pending.subarray(start+length);if(masked)for(let i=0;i<length;i++)payload[i]^=mask[i%4];if(opcode===1)received(p,JSON.parse(payload));else if(opcode===8){s.end();return}}});s.on('error',()=>{});
});
server.listen(0,'127.0.0.1',()=>{child=spawn(process.argv[2],['http://127.0.0.1:'+server.address().port],{stdio:'inherit'});child.on('exit',code=>{assert.equal(code,0);assert.equal(connections,2);assert.equal(peers[0].hits.size,5);assert.equal(peers[1].hits.size,2);done=true;for(const p of peers)p.s.destroy();server.close();console.log('PASS real stream wire: two victims per paid event, shared300ms cadence, instant API and new nonce')})});
setTimeout(()=>{if(!done){child?.kill();for(const p of peers)p.s.destroy();server.close();throw Error('Stream wire timeout')}},15000).unref();
'''
def main():
 out=ROOT/'local-only/research/muzzle';out.mkdir(parents=True,exist_ok=True)
 with tempfile.TemporaryDirectory(prefix='stream-',dir=out) as temporary:
  work=Path(temporary);(work/'peer.cjs').write_text(JS)
  motion=(ROOT/'ios/App/NativeActorAnimation.swift').read_text();motion=motion[motion.index('struct NativePedestrianMotion {'):motion.index('struct NativeWeaponAnimation {')]
  method=function((ROOT/'ios/App/NativeMultiplayerClient.swift').read_text(),'    @discardableResult func sendWeaponShot(')
  tests=(ROOT/'tests/combat/smoke_native_stream_shots.swift').read_text().replace('// ACTUAL_SEND_WEAPON_SHOT',method)
  old='var socket:DeferredSocket?=DeferredSocket(),health=100,passive=false,shots=0,resyncs=0'
  assert old in tests
  tests=tests.replace(old,old+',isReady=true,usesClientOwnedWeapons=false,usesOriginalWorldProtocol=false;var transportGeneration:UInt64=0',1)
  tests=tests.replace('final class CallbackHarness {','final class DisabledLegacy {func send(_ packet:[String:Any])->Bool{preconditionFailure("Legacy branch in strict self-host test")}}\nfinal class CallbackHarness {\n var legacy:DisabledLegacy?',1)
  old='func requestInventoryResync(){resyncs += 1}'
  assert old in tests
  tests=tests.replace(old,old+'\n func failTransport(generation:UInt64,reason:String){resyncs += 1}\n func sendOriginal(_ packet:[String:Any])->Bool{preconditionFailure("Original branch in strict self-host test")}',1)
  old='client.onInventoryConnection={nonce in\n guard nonce != nil else{return};nonceCount += 1'
  assert old in tests
  tests=tests.replace(old,'client.onConnectionState={state in\n guard state == .ready else{return};nonceCount += 1',1)
  old='check(client.reserveShot()==nil,"Unnegotiated stream cannot fire")'
  assert old in tests
  tests=tests.replace(old,'client.onInventoryConnection={nonce in if nonce != nil {check(!client.isReady && client.reserveShot()==nil,"Hello alone cannot fire stream")}}\nclient.onInventory={_ in if !client.isReady {check(client.reserveShot()==nil,"Inventory before all cannot fire stream")}}\n'+old,1)
  source='\n'.join((ROOT/'ios/App'/f'{name}.swift').read_text() for name in ['NativeConnectionRecovery','ServerAddress','NativeInventoryPrediction','NativeShotTargeting','NativeStreamShotClaims','NativeOriginalWorldProtocol','NativeOriginalWorldCommands','NativeOriginalWorldVitals','NativeSAMPProtocol','NativeSAMPGameplayCommands','NativeSAMPLocalVitals','NativeMultiplayerClient'])+'\n'+motion+'\n'+tests
  (work/'main.swift').write_text(source)
  subprocess.run(['swiftc','-O','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',str(work/'main.swift'),'-o',str(work/'verify')],check=True)
  subprocess.run(['node',str(work/'peer.cjs'),str(work/'verify')],check=True)
if __name__=='__main__':main()
