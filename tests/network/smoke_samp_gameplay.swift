// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
var checks=0
func check(_ condition:Bool,_ message:String){checks+=1;precondition(condition,message)}
func hex(_ value:String)->Data{let a=Array(value);return Data(stride(from:0,to:a.count,by:2).map{UInt8(String(a[$0...$0+1]),radix:16)!})}
typealias C=NativeSAMPGameplayCommands.Command
let golden:[(UInt8,String,Int,C)]=[
 (15,"00",8,.controllable(false)),(15,"01",8,.controllable(true)),
 (146,"00000000",32,.gravity(0)),(146,"6f12833b",32,.gravity(0.004)),
 (146,"6f12033c",32,.gravity(0.008)),(146,"6f12833c",32,.gravity(0.016)),
 (146,"6f1203bc",32,.gravity(-0.008)),(146,"00004842",32,.gravity(50)),(146,"000048c2",32,.gravity(-50)),
 (157,"0000803f0000004000004040",96,.cameraPosition(SIMD3(1,2,3))),
 (158,"0000803f000000400000404002",104,.cameraLookAt(SIMD3(1,2,3),.cut)),
 (162,"",0,.cameraBehind),
 (124,"01000000",32,.spectating(true)),(124,"00000000",32,.spectating(false)),
 (126,"000001",24,.spectatePlayer(0,.normal)),(127,"010003",24,.spectateVehicle(1,.side)),
 (82,"8000401f80000020000020200000402000005020000060206e0280000080",233,
    .cameraInterpolation(position:true,from:SIMD3(1,2,3),to:SIMD3(4,5,6),milliseconds:1500,cut:.move))]
for(id,bytes,bits,command)in golden {
 let data=hex(bytes),packet=NativeSAMPProtocol.RPC(id:id,data:data,bits:bits)
 check(try NativeSAMPGameplayCommands.decode(packet)==command,"Official command field/bit layout mismatch")
 for length in 0..<bits{check((try?NativeSAMPGameplayCommands.decode(.init(id:id,data:data,bits:length)))==nil,"Truncated command accepted/mutated authority")}
 var extended=data;extended.append(0)
 check((try?NativeSAMPGameplayCommands.decode(.init(id:id,data:extended,bits:bits+1)))==nil,"Trailing command data accepted")
}
for(id,bytes)in [(UInt8(15),"02"),(124,"01"),(124,"02000000"),(158,"0000803f000000400000404000"),(126,"ffff01"),(126,"010004"),(127,"000001"),(157,"0000c07f0000004000004040")] {
 let d=hex(bytes);check((try?NativeSAMPGameplayCommands.decode(.init(id:id,data:d,bits:d.count*8)))==nil,"Malformed typed command accepted")
}
check(try NativeSAMPGameplayCommands.decode(.init(id:250,data:Data(),bits:0))==nil,"Unrelated RPC swallowed")
for data in ["0000807f","000080ff","0100c07f","00004c42","00004cc2"] {
 check((try?NativeSAMPGameplayCommands.decode(.init(id:146,data:hex(data),bits:32)))==nil,"Invalid/unsupported gravity accepted or clamped")
}
let spectator=try NativeSAMPGameplayCommands.spectator(position:SIMD3(1,2,3),keys:0x1234,axes:SIMD2(-128,128))
check(spectator==hex("d480ff800034120000803f0000004000004040"),"Spectator212 layout or physical point changed")
check((try?NativeSAMPGameplayCommands.spectator(position:SIMD3(.nan,0,0)))==nil,"Nonfinite spectator position accepted")
check((try?NativeSAMPGameplayCommands.spectator(position:.zero,axes:SIMD2(129,0)))==nil,"Invalid spectator analog axis accepted")
var authority=NativeSAMPGameplayCommands.Authority()
func event(_ generation:UInt64,_ sequence:UInt64,_ command:C)->NativeSAMPGameplayCommands.Event{.init(generation:generation,sequence:sequence,command:command)}
check(!authority.apply(event(4,1,.controllable(false))),"Authority accepted command before session reset")
check(authority.apply(event(4,0,.reset)) && !authority.inputBlocked,"Fresh reset failed")
check(authority.apply(event(4,1,.controllable(false))) && authority.inputBlocked,"Server freeze not authoritative")
check(authority.apply(event(4,2,.cameraBehind)) && authority.inputBlocked,"Camera reset unfroze controls")
check(authority.apply(event(4,3,.spectating(true))) && authority.inputBlocked,"Spectating failed to block input")
check(authority.apply(event(4,4,.controllable(true))) && authority.inputBlocked,"Unfreeze bypassed spectator input block")
check(!authority.apply(event(3,0,.reset)) && authority.inputBlocked,"Old reset released replacement authority")
check(authority.apply(event(5,0,.reset)) && !authority.inputBlocked,"New session retained old freeze/spectator")
check(!authority.apply(event(4,100,.spectating(true))) && !authority.inputBlocked,"Old generation retargeted camera/input")
check(authority.apply(event(5,1,.controllable(false))) && !authority.apply(event(5,1,.controllable(true))) && authority.inputBlocked,"Duplicate callback changed authority")
check(!authority.apply(event(5,0,.reset)) && authority.inputBlocked,"Duplicate reset released current freeze")
check(authority.apply(event(5,2,.gravity(0.004))) && authority.gravity==0.004 && authority.inputBlocked,"Gravity changed input ownership or was lost")
check(!authority.apply(event(5,100,.gravity(.nan))) && authority.sequence==2 && authority.gravity==0.004,"Invalid gravity advanced authority")
check(!authority.apply(event(4,999,.gravity(0.016))) && authority.gravity==0.004,"Stale gravity crossed session")
check(authority.apply(event(5,3,.gravity(0))) && authority.gravity==0,"Zero gravity lost")
check(authority.apply(event(6,0,.reset)) && authority.gravity==nil,"Retired gravity leaked into replacement connection")

// Actual Client→adapter→NMP callback and generation admission. No socket is
// opened in this decoder test; the live owned-server gate is separate.
let client=NativeSAMPClient(address:"127.0.0.1:1",nickname:"Local_QA",version:.v037,installationID:"A")
let adapter=NativeSAMPWorldConnection(client:client)
let network=NativeMultiplayerClient(server:ServerAddress("http://127.0.0.1:1")!,automaticRecoveryTimer:false,legacy:adapter)
var received=[NativeSAMPGameplayCommands.Event]()
network.onLegacyEvent={if let e=$0["event"]as?NativeSAMPGameplayCommands.Event{received.append(e)}}
client.disconnect();let generation=client.gameplayGeneration
func receive(_ id:UInt8,_ bytes:Data,_ bits:Int?=nil)throws{var w=NativeSAMPProtocol.Writer();w.bytes(bytes,bits:bits);try client.receive(NativeSAMPProtocol.rpc(id,w))}
try receive(15,hex("00"));check(network.serverInputBlocked && network.originalInputBlocked && !client.controllable,"Actual NMP legacy freeze gate ignored15")
try receive(157,hex("0000803f0000004000004040"));check(received.last?.command == .cameraPosition(SIMD3(1,2,3)),"Camera world point received a pedestrian offset")
try receive(124,hex("01000000"));check(network.legacySpectating && network.serverInputBlocked,"Actual NMP spectator authority ignored124U32")
try receive(15,hex("01"));check(network.serverInputBlocked,"Controllable true erased independent spectator gate")
try receive(146,hex("6f12833b"));check(client.gravity==0.004 && received.last?.command == .gravity(0.004) && network.serverInputBlocked,"Actual Client/adapter/NMP dropped gravity or released spectator freeze")
let beforeInvalidGravity=received.count
do {try receive(146,hex("0100c07f"));preconditionFailure("Malformed gravity accepted by actual Client")}catch NativeSAMPProtocol.Error.invalid{}
check(received.count==beforeInvalidGravity && client.gravity==0.004,"Malformed gravity mutated actual Client/adapter")
let before=received.count
adapter.onEvent?(["t":"sampGameplay","event":event(generation-1,1000,.cameraBehind)])
check(received.count==before && network.legacySpectating,"NMP forwarded stale camera event")
client.disconnect();check(!network.serverInputBlocked && !network.legacySpectating,"Reconnect retained old server input authority")
check(client.gravity==nil,"Client disconnect retained server gravity")
adapter.onEvent?(["t":"sampGameplay","event":event(generation,9999,.controllable(false))])
check(!network.serverInputBlocked,"Delayed prior-session freeze crossed reset")
// Minimal authored InitGame bits reach the real Client/adapter/NMP before
// class/state/environment callbacks. This decoder fixture opens no socket.
func introduction(_ gravity:Float)->NativeSAMPProtocol.Writer {
 var w=NativeSAMPProtocol.Writer()
 for _ in 0..<4{w.bit(false)};w.float(0);w.bit(false);w.float(0)
 for _ in 0..<3{w.bit(false)};w.integer(2,size:4);w.integer(7,size:2);w.bit(false);w.integer(0,size:4)
 w.integer(12,size:1);w.integer(10,size:1);w.float(gravity);return w
}
for version in [NativeSAMPProtocol.Version.v037,.dl] {
 let c=NativeSAMPClient(address:"127.0.0.1:1",nickname:"Gravity_QA",version:version,installationID:"A")
 let a=NativeSAMPWorldConnection(client:c)
 let n=NativeMultiplayerClient(server:ServerAddress("http://127.0.0.1:1")!,automaticRecoveryTimer:false,legacy:a)
 var log=[String](),last:NativeSAMPGameplayCommands.Event?
 n.onLegacyEvent={if let e=$0["event"]as?NativeSAMPGameplayCommands.Event{last=e;log.append("command")}}
 c.disconnect();log=[]
 c.onPlayers={_ in check(c.gravity==0.016 && last?.command == .gravity(0.016),"Initial gravity arrived after a physical/class callback");log.append("players")}
 c.onVehicles={_ in check(c.gravity==0.016,"Initial vehicle snapshot preceded gravity");log.append("vehicles")}
 c.onEnvironment={_,_,_,_ in check(c.gravity==0.016,"Initial environment preceded gravity");log.append("environment")}
 try c.receive(NativeSAMPProtocol.rpc(139,introduction(0.016)))
 check(log.first=="command" && log.contains("environment") && c.gravity==0.016,"Actual InitGame dropped/reordered gravity")
 c.onPlayers=nil;c.onVehicles=nil;c.onEnvironment=nil
 var afterRetirement=0
 c.onEnvironment={_,_,_,_ in afterRetirement+=1}
 n.onLegacyEvent={if let e=$0["event"]as?NativeSAMPGameplayCommands.Event,case .gravity=e.command{c.disconnect()}}
 let oldEpoch=c.gameplayGeneration
 try c.receive(NativeSAMPProtocol.rpc(139,introduction(0.004)))
 check(c.gameplayGeneration>oldEpoch && c.gravity==nil && c.localID==nil && afterRetirement==0,"Retired initial-gravity callback resumed stale InitGame work")
}
let independent=NativeMultiplayerClient(server:ServerAddress("http://127.0.0.1:1")!,automaticRecoveryTimer:false)
check(!independent.serverInputBlocked && !independent.originalInputBlocked,"Legacy authority contaminated selfhost")
print("PASS: \(checks) primary command goldens, truncations, spectator212 and actual NMP generation/input ownership checks")
