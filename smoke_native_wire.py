#!/usr/bin/env python3
"""Exercise the actual Swift URLSession client against an isolated wire peer."""
from pathlib import Path
import subprocess
import tempfile
ROOT=Path(__file__).resolve().parent
JS=r'''
const http=require('node:http'),crypto=require('node:crypto'),assert=require('node:assert/strict'),{spawn}=require('node:child_process');
let baselineReady=false;let child,socket,done=false,driven=false,parked=false,foot=false,moved=false,flights=0,used=false,shotSequence=0,boundHit=false,meleeBound=false,meleeMarkers=0;
const damage='3434012122110101201';
function send(value){const b=Buffer.from(JSON.stringify(value));let head;if(b.length<126)head=Buffer.from([129,b.length]);else{head=Buffer.alloc(4);head[0]=129;head[1]=126;head.writeUInt16BE(b.length,2)}socket.write(Buffer.concat([head,b]))}
function row(){const r=Array(50).fill(null);Object.assign(r,{0:'42',1:'Browser peer',2:'420',3:1684.7612,4:-2101.9894,5:12.85125,6:.75,7:.25,8:-.125,9:13.25,10:.3,12:1,13:1.5,14:-2.25,15:.7,16:123456,17:1,18:645,19:damage,20:.1,21:.2,22:.3,23:23.4,24:2.13,25:1,26:1,27:22,28:.23,29:6,30:23,31:7,32:92,34:['passenger-car',2],35:'car-fixture',36:1,38:3,39:['trailer',.1,.2,.3],42:[.2,.4,1,.8,-.2],43:67});return r}
function received(m){
 if(!['hi','ping','board'].includes(m.t))assert(baselineReady,'Gameplay before complete baseline');
 if(m.t==='shot'){assert.equal(m.s,++shotSequence);assert.equal(m.w,22);assert.equal(m.c,'wire-nonce');send({t:'inventory',state:{revision:shotSequence,selected:22,weapons:[{id:22,clip:17-shotSequence,rest:30}],ack:{connection:'wire-nonce',processedShot:shotSequence}}})}
 if(m.t==='hit'){assert.equal(m.to,'42');assert.equal(m.c,'wire-nonce');if(m.w===0){assert.equal(m.s,undefined);meleeBound=true}else{assert.equal(m.s,2);assert.equal(m.w,22);boundHit=true}}
 if(m.t==='me'&&m.walking&&!m.parked&&m.act===0&&m.weapon===0){assert.equal(m.on,null,'Detached walker retained support');assert.equal(m.shots,[3,4,4][meleeMarkers++],'Public strike counter must include a miss, avoid double-counting a hit and reject guns on the melee path')}
 if(m.t==='usedParachute'){used=true}
 if(m.t==='hi'){assert.equal(m.nativeInventory,true);assert.equal(m.inventoryAck,1);send({t:'hello',inventoryAck:1,inventoryConnection:'wire-nonce',spot:[1684.7612,-2101.9894,12.85125,.75],life:[100,25]});send({t:'inventory',state:{revision:0,selected:22,weapons:[{id:22,clip:17,rest:30}],ack:{connection:'wire-nonce',processedShot:0}}});send({t:'flightgear',parachute:true,jetpack:true});setTimeout(()=>{baselineReady=true;send({t:'all',you:'Native wire',cash:0,chat:[],vehicles:[['car-fixture','Browser peer','420',1684.7612,-2101.9894,12.85125,.75,.25,-.125,645,damage]],cars:[row()]})},50)}
 if(m.t==='vmove'){assert.equal(m.v,'car-fixture');assert.deepEqual([m.x,m.y,m.z,m.h,m.p,m.r,m.hp,m.d,m.w],[1685,-2102,12.8,.4,.1,-.2,623,damage,321]);moved=true;send({t:'veh',v:['car-fixture','Browser peer','420',1685,-2102,12.8,.4,.1,-.2,623,damage,null,null,null,null,null,321]})}
 if(m.t==='me'&&m.driving){assert(Math.abs(m.heading+.75)<1e-6);assert(Math.abs(m.steer+.3)<1e-6);assert.equal(m.pitch,.25);assert.equal(m.roll,.125);assert.equal(m.health,645);assert.equal(m.damage,damage);assert.equal(m.horn,3);assert.equal(m.act,1);assert.equal(m.lights,true);driven=true}
 if(m.t==='me'&&m.walking&&!m.parked&&m.act===28){assert.equal(m.move,2.13);assert.equal(m.anim,null);assert.equal(m.aim,.24);assert.equal(m.act,28);assert.deepEqual(m.on,{v:'support-fixture',x:.13,y:-.24,z:1.01});assert.equal(m.air,true);assert.equal(m.crouch,true);assert.equal(m.paused,true);assert.deepEqual([m.vx,m.vy,m.vz],[1.2,-2.3,.4]);assert.deepEqual([m.wx,m.wy,m.wz],[.1,.2,.3]);assert(Number.isFinite(m.clock));foot=true}
 if(m.t==='me'&&m.act>=50&&m.act<=62){assert.equal(m.pitch,-.23);assert.equal(m.roll,.46);if(m.act===60){assert.equal(m.move,2.13);assert.equal(m.air,true);assert.equal(m.crouch,true)}else{assert.equal(m.move,0);assert.equal(m.air,false);assert.equal(m.crouch,false)}assert.equal(m.aim,m.act===54?null:.24);flights++}
 if(m.t==='me'&&m.walking&&m.parked){assert(driven&&foot&&moved&&used&&flights===3&&shotSequence===2&&boundHit&&meleeBound&&meleeMarkers===3);assert.equal(m.parked.damage,damage);assert.equal(m.parked.health,645);assert(Math.abs(m.parked.heading+.75)<1e-6);assert.equal(m.parked.roll,.125);parked=true;send({t:'all',you:'Native wire',cash:0,chat:[],vehicles:[],cars:[]});send({t:'note',text:'WIRE OMITTED'});send({t:'vgone',id:'car-fixture'});send({t:'vgone',id:'car-fixture'});send({t:'vgone',id:'absent-dynamic'});send({t:'note',text:'WIRE COMPLETE'})}
}
const server=http.createServer();server.on('upgrade',(req,s)=>{socket=s;s.write('HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: '+crypto.createHash('sha1').update(req.headers['sec-websocket-key']+'258EAFA5-E914-47DA-95CA-C5AB0DC85B11').digest('base64')+'\r\n\r\n');let pending=Buffer.alloc(0);s.on('data',chunk=>{pending=Buffer.concat([pending,chunk]);while(pending.length>=2){let length=pending[1]&127,start=2;if(length===126){if(pending.length<4)return;length=pending.readUInt16BE(2);start=4}if(length===127)throw Error('Unexpected huge test packet');const masked=!!(pending[1]&128),mask=masked?pending.subarray(start,start+4):null;if(masked)start+=4;if(pending.length<start+length)return;const opcode=pending[0]&15,payload=Buffer.from(pending.subarray(start,start+length));pending=pending.subarray(start+length);if(masked)for(let i=0;i<length;i++)payload[i]^=mask[i%4];if(opcode===1)received(JSON.parse(payload));else if(opcode===8){s.end();return}}})});
server.listen(0,'127.0.0.1',()=>{child=spawn(process.argv[2],['http://127.0.0.1:'+server.address().port],{stdio:'inherit'});child.on('exit',code=>{assert.equal(code,0);assert(driven&&parked);done=true;socket?.destroy();server.close();console.log('PASS actual native WebSocket client: fractional spawn, browser yaw/roll, full foot/flight and parked vehicle state, equipment, damage/lights/horn, streamed omission and explicit repeated despawn')})});
const timer=setTimeout(()=>{if(!done){child?.kill();socket?.destroy();server.close();throw Error('Native wire timed out')}},20000);timer.unref();
'''
SWIFT=r'''
let client=NativeMultiplayerClient(server:ServerAddress(CommandLine.arguments[1])!)
var spawned=false,actors=false,cleared=false,sent=false,finished=false,vehicleUpdated=false,gear=false,removedIDs:[String]=[]
let damage="3434012122110101201"
client.onTeleport={p,h in precondition(abs(p.x-1684.7612)<0.0002 && abs(p.y+2101.9894)<0.0003 && abs(p.z-12.85125)<0.00001);precondition(abs(h!+0.75)<1e-6);spawned=true}
client.onFlightGear={parachute,jetpack in precondition(parachute&&jetpack);gear=true}
client.onPlayers={players in
 if let p=players.first{precondition(p.id=="42" && p.vehicleHealth==645 && p.vehicleDamage==damage && p.lights && p.horn==1);precondition(abs(p.heading+0.75)<1e-6 && p.roll==0.125 && p.pitch==0.25)
 precondition(abs(p.movementRatio-2.13)<1e-6 && p.airborne && p.crouching && abs(p.aim!-0.23)<1e-6 && p.action==92 && p.burning)
 precondition(p.velocity==SIMD3<Float>(1.5,-2.25,0.7) && p.angularVelocity==SIMD3<Float>(0.1,0.2,0.3) && p.shotCount==6 && p.paused && p.down==3 && p.life==67 && p.armour==23)
 precondition(p.ridingVehicleID=="passenger-car" && p.ridingSeat==2 && p.supportVehicleID=="trailer" && p.supportOffset==SIMD3<Float>(0.1,0.2,0.3))
 precondition(p.kit==[0.2,0.4,1,0.8,-0.2] && p.packetReceivedAt>0 && p.packetClockMilliseconds==123456 && abs(p.latencyMilliseconds-23.4)<1e-5);actors=true}
 else if actors{cleared=true}
}
client.onVehicleRemoved={id in
 precondition(client.vehicles[id]==nil,"Explicit deletion callback ran before row removal")
 removedIDs.append(id)
}
client.onVehicles={vehicles in
 if let changed=vehicles.first,changed.work==321{precondition(changed.health==623 && changed.heading == -0.4 && changed.roll==0.2);vehicleUpdated=true}
 sendIfReady()
}
func sendIfReady(){
 guard client.isReady,!sent,actors,let v=client.orderedVehicles.first else{return};sent=true
 precondition(v.damage==damage && v.health==645 && v.roll==0.125 && v.heading == -0.75)
 client.sendPosition(v.position,heading:0.75,moving:true,running:false,vehicle:v,speed:13.25,steer:0.3,pitch:0.25,roll:-0.125,vehicleHealth:645,vehicleDamage:damage,lights:true,horn:true,siren:true,action:1)
 client.sendPosition(v.position,heading:0.75,moving:true,running:false,airborne:true,weapon:22,crouching:true,movement:2.13,aim:0.236,action:28,velocity:SIMD3(1.2,-2.3,0.4),angularVelocity:SIMD3(0.1,0.2,0.3),paused:true,support:("support-fixture",SIMD3(0.126,-0.236,1.006)))
 for state in [54,60,61]{client.sendPosition(v.position,heading:0.75,moving:true,running:false,pitch:-0.234,roll:0.456,airborne:true,weapon:46,crouching:true,movement:2.13,aim:0.236,action:state)}
 client.usedParachute()
 client.sendVehicleMove(v.id,state:["x":1685,"y":-2102,"z":12.8,"h":0.4,"p":0.1,"r":-0.2,"hp":623,"d":damage,"w":321])
 let first=client.reserveShot()!,second=client.reserveShot()!
 precondition(client.sendWeaponShot(weapon:22,from:v.position,to:v.position+SIMD3<Float>(1,0,0),player:nil,ticket:first))
 precondition(!client.sendWeaponShot(weapon:22,from:v.position,to:v.position+SIMD3<Float>(1,0,0),player:nil,ticket:first),"duplicate ticket was sent twice")
 precondition(client.sendWeaponShot(weapon:22,from:v.position,to:v.position+SIMD3<Float>(2,0,0),player:"42",ticket:second))
 precondition(client.recordMeleeStrike(weapon:0))
 precondition(client.sendMeleeHit(to:"42"))
 client.sendPosition(v.position,heading:0,moving:false,running:false,weapon:0)
 precondition(client.recordMeleeStrike(weapon:0)) // A valid marker without a damage target.
 client.sendPosition(v.position,heading:0,moving:false,running:false,weapon:0)
 precondition(!client.recordMeleeStrike(weapon:22))
 client.sendPosition(v.position,heading:0,moving:false,running:false,weapon:0)
 DispatchQueue.main.asyncAfter(deadline:.now()+0.1){client.sendExit(v.position+SIMD3<Float>(2,0,0),parked:v.position,heading:0.75,pitch:0.25,roll:-0.125,vehicle:v,vehicleHealth:645,vehicleDamage:damage)}
}
client.onConnectionState={state in if state == .ready {sendIfReady()}}
client.onInventoryConnection={nonce in if nonce != nil {precondition(!client.isReady && client.reserveShot()==nil,"Hello alone unlocked gameplay")}}
client.onInventory={_ in if !client.isReady {precondition(client.reserveShot()==nil,"Inventory before all unlocked gameplay")}}
client.onStatus={text in if text=="WIRE OMITTED"{precondition(client.orderedVehicles.isEmpty && removedIDs.isEmpty,"Stream omission was treated as explicit despawn")}
 if text=="WIRE COMPLETE"{precondition(removedIDs==["car-fixture","car-fixture","absent-dynamic"],"Explicit despawns lost the retained-physics routing event");precondition(spawned&&actors&&cleared&&vehicleUpdated&&gear);finished=true;client.disconnect()}}
client.connect();let deadline=Date().addingTimeInterval(15)
while !finished && Date()<deadline{RunLoop.main.run(until:Date().addingTimeInterval(0.02))}
precondition(finished,"Swift wire checks timed out")
'''
def main():
    with tempfile.TemporaryDirectory(prefix='zgtasa-wire-') as directory:
        folder=Path(directory);(folder/'peer.cjs').write_text(JS)
        actor=(ROOT/'ios/App/NativeActorAnimation.swift').read_text()
        actor=actor[actor.index('struct NativePedestrianMotion {'):actor.index('struct NativeWeaponAnimation {')]
        source='\n'.join((ROOT/'ios/App'/f'{name}.swift').read_text() for name in ['NativeConnectionRecovery','ServerAddress','NativeInventoryPrediction','NativeShotTargeting','NativeStreamShotClaims','NativeSAMPProtocol','NativeSAMPGameplayCommands','NativeOriginalWorldProtocol','NativeOriginalWorldCommands','NativeOriginalWorldVitals','NativeOriginalWorldEffects','NativeSAMPLocalVitals'])+'\n'+actor+'\n'+(ROOT/'ios/App/NativeMultiplayerClient.swift').read_text()
        (folder/'main.swift').write_text(source+'\n'+SWIFT)
        subprocess.run(['swiftc','-module-cache-path','/private/tmp/zgtasa-wire-module-cache',str(folder/'main.swift'),'-o',str(folder/'client')],check=True)
        subprocess.run(['node',str(folder/'peer.cjs'),str(folder/'client')],check=True)
if __name__=='__main__':main()
