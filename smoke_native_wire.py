#!/usr/bin/env python3
"""Exercise the actual Swift URLSession client against an isolated wire peer."""
from pathlib import Path
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parent
JS=r'''
const http=require('node:http'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{spawn}=require('node:child_process');
let child,socket,done=false,driven=false,parked=false;
const damage='3434012122110101201';
function send(value){const b=Buffer.from(JSON.stringify(value));let head;if(b.length<126)head=Buffer.from([129,b.length]);else{head=Buffer.alloc(4);head[0]=129;head[1]=126;head.writeUInt16BE(b.length,2)}socket.write(Buffer.concat([head,b]))}
function row(){const r=Array(50).fill(null);Object.assign(r,{0:'42',1:'Browser peer',2:'420',3:1684.7612,4:-2101.9894,5:12.85125,6:.75,7:.25,8:-.125,9:13.25,10:.3,12:1,17:1,18:645,19:damage,27:22,31:7,32:0,35:'car-fixture'});return r}
function received(m){
 if(m.t==='hi'){assert.equal(m.nativeInventory,true);send({t:'hello',spot:[1684.7612,-2101.9894,12.85125,.75],life:[100,25]});send({t:'all',vehicles:[['car-fixture','Browser peer','420',1684.7612,-2101.9894,12.85125,.75,.25,-.125,645,damage]],cars:[row()]})}
 if(m.t==='me'&&m.driving){assert(Math.abs(m.heading+.75)<1e-6);assert.equal(m.pitch,.25);assert.equal(m.roll,.125);assert.equal(m.health,645);assert.equal(m.damage,damage);assert.equal(m.horn,true);assert.equal(m.lights,true);driven=true}
 if(m.t==='me'&&m.walking&&m.parked){assert(driven);assert.equal(m.parked.damage,damage);assert.equal(m.parked.health,645);assert(Math.abs(m.parked.heading+.75)<1e-6);assert.equal(m.parked.roll,.125);parked=true;send({t:'cars',c:[]});send({t:'note',text:'WIRE COMPLETE'})}
}
const server=http.createServer();server.on('upgrade',(req,s)=>{socket=s;s.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+crypto.createHash('sha1').update(req.headers['sec-websocket-key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64')+'\r\n\r\n');let pending=Buffer.alloc(0);s.on('data',chunk=>{pending=Buffer.concat([pending,chunk]);while(pending.length>=2){let length=pending[1]&127,start=2;if(length===126){if(pending.length<4)return;length=pending.readUInt16BE(2);start=4}if(length===127)throw Error('Unexpected huge test packet');const masked=!!(pending[1]&128),mask=masked?pending.subarray(start,start+4):null;if(masked)start+=4;if(pending.length<start+length)return;const opcode=pending[0]&15,payload=Buffer.from(pending.subarray(start,start+length));pending=pending.subarray(start+length);if(masked)for(let i=0;i<length;i++)payload[i]^=mask[i%4];if(opcode===1)received(JSON.parse(payload));else if(opcode===8){s.end();return}}})});
server.listen(0,'127.0.0.1',()=>{child=spawn(process.argv[2],['http://127.0.0.1:'+server.address().port],{stdio:'inherit'});child.on('exit',code=>{assert.equal(code,0);assert(driven&&parked);done=true;socket?.destroy();server.close();console.log('PASS actual native WebSocket client: fractional spawn, browser yaw/roll, damage/lights/horn, parked condition and empty snapshot')})});
const timer=setTimeout(()=>{if(!done){child?.kill();socket?.destroy();server.close();throw Error('Native wire timed out')}},20000);timer.unref();
'''
SWIFT=r'''
let client=NativeMultiplayerClient(server:ServerAddress(CommandLine.arguments[1])!)
var spawned=false,actors=false,cleared=false,sent=false,finished=false
let damage="3434012122110101201"
client.onTeleport={p,h in precondition(abs(p.x-1684.7612)<0.0002 && abs(p.y+2101.9894)<0.0003 && abs(p.z-12.85125)<0.00001);precondition(abs(h!+0.75)<1e-6);spawned=true}
client.onPlayers={players in
 if let p=players.first{precondition(p.id=="42" && p.vehicleHealth==645 && p.vehicleDamage==damage && p.lights && p.horn==1);precondition(abs(p.heading+0.75)<1e-6 && p.roll==0.125 && p.pitch==0.25);actors=true}
 else if actors{cleared=true}
}
client.onVehicles={vehicles in
 guard !sent,actors,let v=vehicles.first else{return};sent=true
 precondition(v.damage==damage && v.health==645 && v.roll==0.125 && v.heading == -0.75)
 client.sendPosition(v.position,heading:0.75,moving:true,running:false,vehicle:v,speed:13.25,steer:0.3,pitch:0.25,roll:-0.125,vehicleHealth:645,vehicleDamage:damage,lights:true,horn:true)
 DispatchQueue.main.asyncAfter(deadline:.now()+0.1){client.sendExit(v.position+SIMD3<Float>(2,0,0),parked:v.position,heading:0.75,pitch:0.25,roll:-0.125,vehicle:v,vehicleHealth:645,vehicleDamage:damage)}
}
client.onStatus={text in if text=="WIRE COMPLETE"{precondition(spawned&&actors&&cleared);finished=true;client.disconnect()}}
client.connect();let deadline=Date().addingTimeInterval(15)
while !finished && Date()<deadline{RunLoop.main.run(until:Date().addingTimeInterval(0.02))}
precondition(finished,"Swift wire checks timed out")
'''
def main():
    with tempfile.TemporaryDirectory(prefix='zgtasa-wire-') as directory:
        folder=Path(directory);(folder/'peer.cjs').write_text(JS)
        actor=(ROOT/'ios/App/NativeActorAnimation.swift').read_text()
        actor=actor[actor.index('struct NativePedestrianMotion {'):actor.index('struct NativeWeaponAnimation {')]
        source=(ROOT/'ios/App/ServerAddress.swift').read_text()+'\n'+actor+'\n'+(ROOT/'ios/App/NativeMultiplayerClient.swift').read_text()
        (folder/'main.swift').write_text(source+'\n'+SWIFT)
        subprocess.run(['swiftc','-module-cache-path','/private/tmp/zgtasa-wire-module-cache',str(folder/'main.swift'),'-o',str(folder/'client')],check=True)
        subprocess.run(['node',str(folder/'peer.cjs'),str(folder/'client')],check=True)
if __name__=='__main__':main()
