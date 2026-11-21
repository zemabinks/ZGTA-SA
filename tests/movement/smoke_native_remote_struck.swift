// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
import Darwin
enum Failure:Error{case failed(String)}
var checks=0
func check(_ value:Bool,_ text:String)throws{checks+=1;if !value{throw Failure.failed(text)}}
func fixture()->NativeSkeletalAnimationLibrary {
 var data=Data()
 func word(_ value:UInt32){var n=value.littleEndian;withUnsafeBytes(of:&n){data.append(contentsOf:$0)}}
 func float(_ value:Float){word(value.bitPattern)}
 func string(_ value:String){var n=UInt16(value.utf8.count).littleEndian;withUnsafeBytes(of:&n){data.append(contentsOf:$0)};data.append(contentsOf:value.utf8)}
 let names=["idle_stance","walk_player","run_player","sprint_civi","shot_partial","shot_partial_b","shot_leftp","shot_rightp",
  "dam_arml_frmbk","dam_arml_frmft","dam_arml_frmlt","ko_shot_front","ko_skid_front","ko_skid_back","ko_spin_l","ko_spin_r",
  "floor_hit","floor_hit_f"].map{"ped/"+$0}+["knife/kill_knife_ped_damage","knife/kill_knife_ped_die"]
 [UInt32(0x31504c43),UInt32(names.count),0,1].forEach{word($0)}
 for name in names {
  string(name);float(1);word(1);word(0);word(2);word(1)
  for time in [Float(0),Float(1)]{float(time);[Float(0),0,0,1,0,0,0].forEach{float($0)}}
 }
 return NativeSkeletalAnimationLibrary(data:data)!
}
func owner(_ library:NativeSkeletalAnimationLibrary)->NativeRemoteFootAnimation {
 NativeRemoteFootAnimation(library:library,style:.init(),weapons:[:],random:{0.5})
}
func reference(_ path:String)throws->Int {
 let doc=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:path)))as![String:Any]
 func v(_ value:Any?)->SIMD3<Double>? {
  guard let values=value as?[NSNumber],values.count==3 else{return nil}
  return SIMD3(values[0].doubleValue,values[1].doubleValue,values[2].doubleValue)
 }
 var count=0
 for row in doc["directions"]as![[String:Any]] {
  let side=v(row["fromGTA"]).map{NativePedestrianReaction.incomingSide(from:$0,position:v(row["positionGTA"])!,heading:(row["nativeHeading"]as!NSNumber).doubleValue)} ?? 0
  try check(side==(row["expectedSide"]as!NSNumber).intValue,"Actual archived direction "+(row["name"]as!String));count+=1
 }
 for row in doc["deaths"]as![[String:Any]]{
  try check(NativePedestrianReaction.deathKind(weapon:(row["weapon"]as!NSNumber).intValue,side:(row["side"]as!NSNumber).intValue)==row["expectedClip"]as!String,"Actual archived death selector");count+=1
 }
 for row in doc["heads"]as![[String:Any]]{
  try check(NativePedestrianReaction.losesHead(weapon:(row["weapon"]as!NSNumber).intValue,piece:(row["piece"]as!NSNumber).intValue)==row["expectedPredicate"]as!Bool,"Actual archived head predicate");count+=1
 }
 return count
}
func run()throws {
 let library=fixture(),shots=NativeHumanShots()
 let packet=NativeHumanShots.Packet(["from":"7","id":"8","w":31,"o":[-10.0,0,1.3],"h":[0.0,0,1.3],"ht":1,"bp":9])!
 shots.observeStrike(packet,targetReady:false,at:1);try check(shots.recentStrike("8",at:1)==nil,"Missing target owner invented strike metadata")
 shots.observeStrike(packet,targetReady:true,at:1)
 try check(shots.recentStrike("8",at:1.999999)?.weapon==31,"Recent hit expired before1s")
 try check(shots.recentStrike("8",at:2)==nil,"Exact1s old hit stayed active")
 shots.observeStrike(packet,targetReady:true,at:3);shots.clearStrike("8")
 try check(shots.recentStrike("8",at:3)==nil,"Model owner replacement retained old hit")
 shots.observeStrike(packet,targetReady:true,at:3);shots.retain(["7"])
 try check(shots.recentStrike("8",at:3)==nil,"Removed target retained old hit")
 shots.observeStrike(packet,targetReady:true,at:3);shots.clear()
 try check(shots.recentStrike("8",at:3)==nil,"World reset retained old hit")
 let actor=owner(library)
 var state=NativeRemoteFootAnimation.Snapshot();state.armour=20
 _=actor.update(delta:0,nowMilliseconds:1000,snapshot:state)
 state.struck = .init(weapon:31,origin:SIMD3(-10,0,0),piece:3,atMilliseconds:1000)
 let unchanged=actor.update(delta:1/60,nowMilliseconds:1016,snapshot:state)
 try check(!unchanged.blends.contains{$0.clip.contains("shot_") && $0.weight>0},"Shot metadata alone applied a hit reaction")
 try check(!actor.animator.dead && state.life==100 && state.armour==20,"Shot metadata changed health")
 state.armour=10
 let hurt=actor.update(delta:1/60,nowMilliseconds:1032,snapshot:state)
 try check(hurt.blends.contains{$0.clip=="ped/shot_leftp" && $0.weight>0},"Authoritative armour drop lost incoming left sector")
 try check(!actor.animator.stunned,"Remote flinch incorrectly acquired local input stun")
 let stale=owner(library);var old=NativeRemoteFootAnimation.Snapshot()
 _=stale.update(delta:0,nowMilliseconds:1000,snapshot:old)
 old.struck = .init(weapon:24,origin:SIMD3(0,-10,0),piece:5,atMilliseconds:1000);old.life=90
 let expired=stale.update(delta:1/60,nowMilliseconds:2000,snapshot:old)
 try check(expired.blends.contains{$0.clip=="ped/shot_partial"},"Expired cause did not fall back to ordinary front flinch")
 let recent=owner(library);var newest=NativeRemoteFootAnimation.Snapshot()
 _=recent.update(delta:0,nowMilliseconds:1000,snapshot:newest)
 newest.struck=old.struck;newest.life=90
 let directed=recent.update(delta:1/60,nowMilliseconds:1999.999,snapshot:newest)
 try check(directed.blends.contains{$0.clip=="ped/dam_arml_frmbk"},"Current piece/strong weapon did not choose arm/back reaction")
 try check(!recent.animator.stunned,"Remote strong hit froze snapshot input")
 let names=["ko_skid_front","ko_spin_r","ko_skid_back","ko_spin_l"]
 let sources=[SIMD3<Double>(0,10,0),SIMD3(-10,0,0),SIMD3(0,-10,0),SIMD3(10,0,0)]
 for (side,source)in sources.enumerated() {
  let dead=owner(library);var input=NativeRemoteFootAnimation.Snapshot()
  _=dead.update(delta:0,nowMilliseconds:1000,snapshot:input)
  input.life=0;input.struck = .init(weapon:31,origin:source,piece:9,atMilliseconds:1000)
  let frame=dead.update(delta:1/60,nowMilliseconds:1032,snapshot:input)
  try check(dead.animator.dead && frame.blends.contains{$0.clip=="ped/"+names[side]},"Directional death animation")
  try check(dead.animator.lostHead && frame.hiddenBones.contains(5),"Protocol HEAD9 did not hide skeletal HEAD5")
  input.struck = .init(weapon:22,origin:source,piece:3,atMilliseconds:1040)
  let held=dead.update(delta:1/60,nowMilliseconds:1050,snapshot:input)
  try check(held.hiddenBones.contains(5),"Repeated dead snapshot restored the head")
  input.life=100
  let revived=dead.update(delta:1/60,nowMilliseconds:1066,snapshot:input)
  try check(!dead.animator.dead && !dead.animator.lostHead && revived.hiddenBones.isEmpty,"Revive retained head/death presentation")
 }
 let down=owner(library);var floored=NativeRemoteFootAnimation.Snapshot()
 _=down.update(delta:0,nowMilliseconds:1000,snapshot:floored)
 floored.life=0;floored.down=1;floored.struck = .init(weapon:31,origin:SIMD3(0,10,0),piece:9,atMilliseconds:1000)
 let onFloor=down.update(delta:1/60,nowMilliseconds:1032,snapshot:floored)
 try check(onFloor.blends.contains{$0.clip=="ped/ko_skid_back"} && down.animator.lostHead,"Server down pose did not outrank shot death selector")
 let late=owner(library);var deadState=NativeRemoteFootAnimation.Snapshot()
 _=late.update(delta:0,nowMilliseconds:1000,snapshot:deadState);deadState.life=0
 _=late.update(delta:1/60,nowMilliseconds:1032,snapshot:deadState)
 deadState.struck = .init(weapon:31,origin:SIMD3(0,10,0),piece:9,atMilliseconds:1040)
 _=late.update(delta:1/60,nowMilliseconds:1050,snapshot:deadState)
 try check(!late.animator.lostHead,"Late packet retroactively removed an already dead actor's head")
 let infos:[String:Any]=["emlife":["life":[[0,1]]],"size":["sizex":[[0,1]],"sizey":[[0,1]]],
  "colour":["red":[[0,1]],"green":[[0,1]],"blue":[[0,1]],"alpha":[[0,1]]]]
 let system:[String:Any]=["systems":["prt_blood":["length":0.2,"emitters":[["texture":"prt_blood","infos":infos]]]]]
 let particles=try NativeParticleEffects(data:JSONSerialization.data(withJSONObject:system),textures:["prt_blood"],random:{0.5})
 let fx=NativeOrdinaryShotEffects(random:{0.5});fx.particles=particles
 fx.blood(at:SIMD3(3,4,5),direction:SIMD3(0,0,1),count:40)
 try check(particles.shown.count==40,"Head-loss blood did not use the existing generic particle core")
 try check(particles.shown.allSatisfy{$0.position==SIMD3(3,4,5) && $0.velocity==SIMD3(0,0,1.5) && $0.life==0.8 && $0.big==0.85},"Head-loss blood origin, direction or multipliers")
 var referenceCount=0
 if CommandLine.arguments.count>1{referenceCount=try reference(CommandLine.arguments[1])}
 print("PASS \(checks) actual remote struck/animation checks; \(referenceCount) archived scalar cases; authored CLP, no damage authority, rendered blood/bones, app or retail claim")
}
do{try run()}catch{print("FAIL \(error)");exit(1)}
