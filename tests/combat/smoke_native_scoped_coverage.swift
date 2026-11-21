// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
private final class Renderer {
 struct Frame {var source=SIMD3<Float>(0,-103,1.6),target=SIMD3<Float>(0,-102,1.6),aimSource:SIMD3<Float>?,hidesPlayer=true}
 struct Override {var active=true}
 var driving=false,equippedWeapon=34,isInterior=false
 var legacyCameraSample:Override?,gameCameraFrame:Frame?=Frame()
 var shotFeet=SIMD3<Float>(0,-100,0)
 var collisionRequests=NativeCollisionRequests()
 var activeDetails:Set<String>=["c120"],desiredPhysicsCells=Set<String>()
 var requested=Set<String>(),loaded:Set<String>=["c120"],sharpRequests=0
 // Loader records pending work. It never grants coverage before completion.
 func loadCollision(name:String){requested.insert(name)}
 func loadWorldSharpIfNeeded(){sharpRequests+=1}
 // ACTUAL_PREFETCH
 func drawPhase(){
 // ACTUAL_DRAW_HOOK
 }
 func query()->NativeWorldRay.Result {
  let frame=gameCameraFrame!,origin=frame.aimSource ?? frame.source,forward=simd_normalize(frame.target-frame.source)
  let range=Float(NativeLocalShots.scopedRange(camera:SIMD3<Double>(origin),feet:SIMD3<Double>(shotFeet))!)
  return NativeWorldRay.query(from:origin,direction:forward,distance:range,interior:isInterior,loaded:{self.loaded.contains($0)}){_,_,limit in
   limit>=650 ? .init(distance:650,normal:SIMD3(0,-1,0)):nil
  }
 }
}
@main private enum Main {
 static func main(){
  var checks=0
  func check(_ ok:Bool,_ why:String){checks+=1;if !ok{print("FAIL \(why)");exit(1)}}
  let renderer=Renderer()
  if case .unavailable(let distance)=renderer.query(){check(abs(distance-103)<0.01,"Cold ray did not stop at the first missing cell")}
  else{check(false,"Cold fixture invented complete distant coverage")}
  renderer.drawPhase()
  check(renderer.requested==["c120","c136","c152"],"Scoped view did not request forward collision before the first shot")
  check(renderer.desiredPhysicsCells==renderer.requested,"Scope request lost the current actor floor or forward cells")
  check(renderer.sharpRequests==1,"Existing original collision-detail admission was bypassed")
  if case .unavailable=renderer.query(){check(true,"Pending cells remain unavailable")}
  else{check(false,"Requesting geometry fabricated loaded collision")}
  renderer.loaded.formUnion(renderer.requested)
  if case .hit(let hit)=renderer.query(){check(hit.distance==650,"Completed coverage changed the authored trace")}
  else{check(false,"Completed forward cells did not admit the same distant ray")}
  let expiry=ProcessInfo.processInfo.systemUptime+2.1
  check(renderer.collisionRequests.retained(now:expiry,visible:renderer.activeDetails)==renderer.activeDetails,"Scope cells acquired an unlimited lifetime")
  func inactive(_ configure:(Renderer)->Void){let value=Renderer();configure(value);value.drawPhase();check(value.requested.isEmpty&&value.sharpRequests==0,"Inactive scope requested long-distance physics")}
  inactive{$0.equippedWeapon=33};inactive{$0.gameCameraFrame?.hidesPlayer=false}
  inactive{$0.driving=true};inactive{$0.legacyCameraSample=Renderer.Override()}
  inactive{$0.gameCameraFrame=nil};inactive{$0.gameCameraFrame?.target.x = .nan}
  let interior=Renderer();interior.isInterior=true;interior.activeDetails=["i120"];interior.drawPhase()
  check(interior.requested==["i120","i136","i152"],"Scope inferred scene identity from ray altitude")
  let aimed=Renderer();aimed.gameCameraFrame?.aimSource=SIMD3(0,1,1.6);aimed.drawPhase()
  check(aimed.requested.contains("c168"),"Retained aim-source range was not warmed")
  print("PASS \(checks) actual scoped draw request and bounded collision coverage; explicit async loader/trace boundaries, no App/retail claim")
 }
}
