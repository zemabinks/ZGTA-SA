#!/usr/bin/env python3
"""Actual native stream-cylinder/cadence and local URLSession wire regression."""
from pathlib import Path
import subprocess,tempfile
from smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parent
JS=r'''
const http=require('node:http'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{spawn}=require('node:child_process');
let child,done=false,connections=0;const peers=[];
function send(p,m){const b=Buffer.from(JSON.stringify(m)),h=b.length<126?Buffer.from([129,b.length]):Buffer.from([129,126,b.length>>8,b.length&255]);p.s.write(Buffer.concat([h,b]))}
function received(p,m){
 if(m.t==='hi'){assert.equal(m.inventoryAck,1);send(p,{t:'hello',inventoryAck:1,inventoryConnection:p.nonce,life:[100,0]});return}
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
  tests=(ROOT/'smoke_native_stream_shots.swift').read_text().replace('// ACTUAL_SEND_WEAPON_SHOT',method)
  source='\n'.join((ROOT/'ios/App'/f'{name}.swift').read_text() for name in ['ServerAddress','NativeInventoryPrediction','NativeShotTargeting','NativeStreamShotClaims','NativeMultiplayerClient'])+'\n'+motion+'\n'+tests
  (work/'main.swift').write_text(source)
  subprocess.run(['swiftc','-O','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',str(work/'main.swift'),'-o',str(work/'verify')],check=True)
  subprocess.run(['node',str(work/'peer.cjs'),str(work/'verify')],check=True)
if __name__=='__main__':main()
