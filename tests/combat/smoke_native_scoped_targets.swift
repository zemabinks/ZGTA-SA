// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
// Explicit non-rendering boundaries: authored actor rows/model readiness,
// clear world coverage and no vehicle/physics owners. Actual resolver follows.
private struct Person {
 let id:String,position:SIMD3<Float>
 var code="s7",skin=7,life:Float=100,heading:Float=0,crouching=false
 var ridingVehicleID:String?,vehicleID:String?
}
private struct NPC {
 struct State{let mood:Int}
 let targetID:String,position:SIMD3<Double>,heading:Double,dead:Bool,state:State?
}
private final class Bodies {
 let colliders=Set<UInt64>(),otherColliders=Set<UInt64>(),chassisColliders=Set<UInt64>()
 func shotVehicleColliders(id:String)->Set<UInt64>{[]}
 func colliderIDs(id:UInt16,generation:UInt64)->Set<UInt64>{[]}
}
private final class Renderer {
 struct Frame {var source=SIMD3<Float>(0,-3,1.6),aimSource:SIMD3<Float>?,hidesPlayer=true}
 struct VehicleFrame {enum Owner{case player(String,String),registered(String,String),traffic(UInt16,UInt64)};let owner:Owner}
 enum World {struct Hit{let distance:Float};case clear,hit(Hit),unavailable(Float)}
 var equippedWeapon=34,gameCameraFrame:Frame?=Frame(),shotFeet=SIMD3<Float>.zero
 var camera=SIMD3<Float>.zero,scenePosition=SIMD3<Float>.zero
 var presentedRemotePlayers:[Person]=[],presentedAmbientPedestrians:[NPC]=[]
 var skeletalActors=["authored":1],pedModels=["7":"authored"]
 var ambientBodies:Bodies?,ambientTrafficBodies:Bodies?,groundVehicle:Bodies?
 let localShots=NativeLocalShots()
 var remotePlayers:[Person]{presentedRemotePlayers}
 func actorName(code:String)->String?{code=="s7" ? "authored":nil}
 func remoteSupportPosition(_ person:Person)->SIMD3<Float>?{nil}
 func currentLocalShotVehicleFrames()->[VehicleFrame]{[]}
 func localVehicleShotHits(_ ray:NativeLocalShots.Ray,frames:[VehicleFrame])->[NativeLocalShots.Hit]{[]}
 func worldRay(from:SIMD3<Float>,direction:SIMD3<Float>,distance:Float,groups:UInt32,excluding:Set<UInt64>)->World{.clear}
 // ACTUAL_FOOT_ROLE
 // ACTUAL_DRAW_RADIUS
 // ACTUAL_RESOLVE
 func demandedModels()->Set<String>{var names=Set<String>();
 // ACTUAL_RESOURCE_DEMAND
 return names}
 func canDraw(_ player:Person)->Bool {
 // ACTUAL_DRAW_GUARD
 return true}
}
@main private enum Main {
 static func main(){
  var checks=0
  func check(_ condition:Bool,_ why:String){checks+=1;if !condition{print("FAIL \(why)");exit(1)}}
  func input(_ scoped:Bool=true)->NativeLocalShots.Input{
   .init(weapon:34,range:100,pellets:1,accuracy:1,damage:0,feet:.zero,heading:0,crouched:false,
     camera:SIMD3(0,-3,1.6),forward:SIMD3(0,1,0),up:SIMD3(0,0,1),verticalFov:55,aspect:2,
     muzzle:SIMD3(0,0,1.6),hipOrigin:nil,scoped:scoped,hip:false,milliseconds:1000)
  }
  let renderer=Renderer()
  for distance in [Float(150),500,799] {
   renderer.presentedRemotePlayers=[Person(id:"far",position:SIMD3(0,distance,0))]
   check(renderer.canDraw(renderer.presentedRemotePlayers[0]),"Scoped drawing retained the near-only distance gate at \(distance)")
   check(renderer.demandedModels()==["authored"],"Scoped resource demand omitted an admitted far model")
   let frame=renderer.resolveLocalShot(input())
   check(frame?.claims.contains{$0.target?.id=="far"}==true,"Actual resolver discarded a loaded scoped human at \(distance)")
  }
  renderer.presentedRemotePlayers=[Person(id:"outside",position:SIMD3(0,900,0))]
  check(renderer.resolveLocalShot(input())?.claims.allSatisfy{$0.target==nil}==true,"Scope invented a target beyond its ray")
  renderer.presentedRemotePlayers=[Person(id:"far",position:SIMD3(0,200,0))]
  renderer.equippedWeapon=0
  check(renderer.resolveLocalShot(input())?.claims.contains{$0.target?.id=="far"}==true,"Captured final scoped marker depended on post-spend equipment")
  renderer.equippedWeapon=34;renderer.gameCameraFrame?.hidesPlayer=false
  check(!renderer.canDraw(renderer.presentedRemotePlayers[0])&&renderer.demandedModels().isEmpty,"Ordinary view changed its existing resource/draw budget")
  check(renderer.resolveLocalShot(input(false))?.claims.allSatisfy{$0.target==nil}==true,"Ordinary short ray invented a distant hit")
  renderer.gameCameraFrame?.hidesPlayer=true;renderer.skeletalActors=[:]
  check(renderer.resolveLocalShot(input())?.claims.allSatisfy{$0.target==nil}==true,"Unloaded resource became an invented human target")
  renderer.skeletalActors=["authored":1];renderer.presentedRemotePlayers[0].life=0
  check(renderer.resolveLocalShot(input())?.claims.allSatisfy{$0.target==nil}==true,"Dead remote became a live bullet target")
  renderer.presentedRemotePlayers[0].life=100;renderer.presentedRemotePlayers[0].ridingVehicleID="car"
  check(renderer.resolveLocalShot(input())?.claims.allSatisfy{$0.target==nil}==true,"Seated actor acquired a second standing target")
  check(NativeLocalShots.scopedRange(camera:SIMD3(.nan,0,0),feet:.zero)==nil,"Invalid scope source produced a range")
  print("PASS \(checks) actual scoped target/draw/resource predicates and gun geometry; explicit actor/world/vehicle boundaries, no GPU/App/server/retail claim")
 }
}
