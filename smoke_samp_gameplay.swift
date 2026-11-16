// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
var checks=0
func check(_ condition:Bool,_ message:String){checks+=1;precondition(condition,message)}
func hex(_ value:String)->Data{let a=Array(value);return Data(stride(from:0,to:a.count,by:2).map{UInt8(String(a[$0...$0+1]),radix:16)!})}
typealias C=NativeSAMPGameplayCommands.Command
let golden:[(UInt8,String,Int,C)]=[
 (15,"00",8,.controllable(false)),(15,"01",8,.controllable(true)),
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
let before=received.count
adapter.onEvent?(["t":"sampGameplay","event":event(generation-1,1000,.cameraBehind)])
check(received.count==before && network.legacySpectating,"NMP forwarded stale camera event")
client.disconnect();check(!network.serverInputBlocked && !network.legacySpectating,"Reconnect retained old server input authority")
adapter.onEvent?(["t":"sampGameplay","event":event(generation,9999,.controllable(false))])
check(!network.serverInputBlocked,"Delayed prior-session freeze crossed reset")
let independent=NativeMultiplayerClient(server:ServerAddress("http://127.0.0.1:1")!,automaticRecoveryTimer:false)
check(!independent.serverInputBlocked && !independent.originalInputBlocked,"Legacy authority contaminated selfhost")
print("PASS: \(checks) primary command goldens, truncations, spectator212 and actual NMP generation/input ownership checks")
