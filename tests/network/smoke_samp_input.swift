// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
var checks=0
func check(_ value:Bool,_ label:String){precondition(value,label);checks+=1}
let axes:[Float]=[-Float.infinity,-2,-1,-0.5,-0.01,0,0.01,0.5,1,2,.infinity,.nan]
let expected:[Int16]=[0,-128,-128,-64,-1,0,1,64,128,128,0,0]
for (value,wanted)in zip(axes,expected){check(NativeSAMPInput.axis(value)==wanted,"Signed128 analog axis boundary")}
for driving in [false,true] {
 var state=NativeSAMPInput.State();state.driving=driving
 state.sideways = -0.5;state.forward=1;state.steering=0.25;state.pitch = -0.75
 let frame=NativeSAMPInput.encode(state)
 check(frame.leftRight==(driving ? 32:-64) && frame.upDown==(driving ? 96:-128),"Analog channels follow actual foot/vehicle context")
 state.enabled=false;state.fire=true;state.special=3
 check(NativeSAMPInput.encode(state) == .init(),"Menu/lifecycle cancellation clears every protocol input channel")
}
let pairs:[(WritableKeyPath<NativeSAMPInput.State,Bool>,UInt16)]=[(\.action,1),(\.crouch,2),(\.fire,4),(\.sprint,8),(\.enterExit,16),(\.jump,32),(\.aim,128),(\.walk,1024)]
for (key,mask)in pairs {
 var state=NativeSAMPInput.State();state[keyPath:key]=true
 check(NativeSAMPInput.encode(state).keys==mask,"Published on-foot key \(mask)")
}
var drive=NativeSAMPInput.State();drive.driving=true
drive.throttle=1;drive.brake=1;drive.horn=true;drive.handbrake=true;drive.look="behind";drive.action=true
check(NativeSAMPInput.encode(drive).keys==683,"Actual simultaneous driving input bits1+2+8+32+128+512")
drive.walk=true;drive.crouch=true;drive.sprint=true;drive.jump=true;drive.aim=true
check(NativeSAMPInput.encode(drive).keys==683,"Foot-only toggles cannot masquerade as vehicle controls")
for (look,mask)in [("left",UInt16(256)),("right",UInt16(64)),("behind",UInt16(512))] {
 var state=NativeSAMPInput.State();state.driving=true;state.look=look
 check(NativeSAMPInput.encode(state).keys==mask,"Vehicle look encoding")
}
check(NativeSAMPInput.specialKey(heldHID:[28])==1 && NativeSAMPInput.specialKey(heldHID:[17])==2 && NativeSAMPInput.specialKey(heldHID:[11])==3,"Y/N/H additional keys")
for weapon in 0...46 { for special in UInt8(0)...3 {
 var foot=NativeSAMPProtocol.Foot(position:SIMD3(1,2,3),heading:0)
 foot.weapon=UInt8(weapon);foot.specialKeys=special;foot.lr = -128;foot.ud=64;foot.keys=0x7fff
 let data=try NativeSAMPProtocol.onFoot(foot)
 check(data.count==69 && data[37]==UInt8(weapon)|(special<<6),"Foot weapon/special2-bit packing")
 check(Array(data[1..<7])==[128,255,64,0,255,127],"Foot analog/key byte order")
 var car=NativeSAMPProtocol.Car(id:1,position:SIMD3(1,2,3),quaternion:SIMD4(1,0,0,0))
 car.weapon=UInt8(weapon);car.specialKeys=special;car.lr = -128;car.ud=64;car.keys=0x7fff
 let vehicle=try NativeSAMPProtocol.car(car)
 check(vehicle.count==64 && vehicle[55]==UInt8(weapon)|(special<<6),"Driver weapon/special2-bit packing")
 check(Array(vehicle[3..<9])==[128,255,64,0,255,127],"Driver analog/key byte order")
}}
var intro=NativeSAMPProtocol.Writer()
for _ in 0..<4{intro.bit(false)};intro.float(200);intro.bit(false);intro.float(70)
for _ in 0..<3{intro.bit(false)};intro.integer(3,size:4);intro.integer(42,size:2);intro.bit(true);intro.integer(1,size:4)
intro.integer(12,size:1);intro.integer(10,size:1);intro.float(0.008)
let minimal=intro
intro.bit(true);intro.integer(0,size:4);intro.bit(false);intro.integer(45,size:4);intro.integer(75,size:4);intro.integer(60,size:4)
var fullReader=try NativeSAMPProtocol.Reader(intro.data,bits:intro.bits)
let full=try NativeSAMPProtocol.introduction(&fullReader)
check(full.id==42 && full.classes==3 && full.footMilliseconds==45 && full.carMilliseconds==75 && full.weaponMilliseconds==60,"Unaligned server-negotiated sync intervals")
var shortReader=try NativeSAMPProtocol.Reader(minimal.data)
check(try NativeSAMPProtocol.introduction(&shortReader).footMilliseconds==30,"Minimal controlled header retains documented default interval")
for tail in 8..<(intro.bits-minimal.bits) {
 var reader=try NativeSAMPProtocol.Reader(intro.data,bits:minimal.bits+tail)
 do{_=try NativeSAMPProtocol.introduction(&reader);preconditionFailure("Accepted truncated negotiated-rate fields")}catch{checks+=1}
}
print("PASS \(checks) semantic input, actual foot/driver wire and server sync-rate checks")
