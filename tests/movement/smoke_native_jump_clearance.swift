// SPDX-License-Identifier: AGPL-3.0-only
@main enum JumpClearanceSmoke {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1])
  let reportURL=URL(fileURLWithPath:CommandLine.arguments[2])
  let legacy=CommandLine.arguments.dropFirst(3).contains("legacy")
  var rows=[[String:Any]](),differences=0
  for hz in [30,60,120] {
   for kind in ["open","high-roof","low-static-roof","low-vehicle-roof","disabled-roof","side-wall"] {
    let task=try ClimbRuntimeHarness(root:root,top:0.1,depth:2)
    task.footLaunchRemaining=nil
    task.character!.reset(feet:SIMD3(50,0,0),active:true,grounded:true)
    if kind != "open" {
     let bottom:Float=kind == "high-roof" ? 4:2
     let body=kind == "low-vehicle-roof" ? task.world.addBody(kind:.kinematicPosition,position:SIMD3(50,bottom+0.1,0)):nil
     let roof=task.world.addBox(halfExtents:SIMD3(3,0.1,3),body:body,position:body == nil ? (kind == "side-wall" ? SIMD3(53.5,bottom+0.1,0):SIMD3(50,bottom+0.1,0)):.zero)!
     task.world.setColliderGroups(roof,collision:0x0087ffff,solver:0xffffffff)
     task.world.setColliderQueryMetadata(roof,surface:2,material:0)
     if body != nil {task.character!.otherColliders.insert(roof)}
     if kind == "disabled-roof" {task.world.setCollider(roof,enabled:false)}
    }
    task.world.step()
    let excluded:Set<UInt64>=[task.character!.queries.walker,task.character!.queries.probe]
    // Authored roof geometry independently confirms the raised clearance
    // region. This does not execute the original engine collision virtuals.
    let referenceOverlaps=[Float(-0.2),0.2,0.6].map { z in
     task.world.sphereIntersections(center:SIMD3(50,1+0.75+z,0),radius:0.3,excludingColliders:excluded).count
    }
    let expectedBlocked=kind.hasPrefix("low-")
    precondition(referenceOverlaps.contains(where:{$0>0}) == expectedBlocked,"Reference fixture roof was not positioned as specified")
    task.jump()
    precondition(task.footLaunchRemaining != nil,"Actual jump input did not start its actual CLP launch task")
    let launchDelay=task.footLaunchRemaining!
    var launches=0,peak=Float.zero,groundFrames=0
    for _ in 0..<hz {
     task.observedRequestedJump=0
     let state=task.frame(1/Double(hz))
     if task.observedRequestedJump>0 {launches += 1}
     peak=max(peak,state.feet.z)
     if state.grounded {groundFrames += 1}
    }
    precondition(task.climb==nil,"This is a ceiling fixture, not an accepted ledge")
    if !expectedBlocked {precondition(launches==1 && peak>0.3,"Open-space positive control must actually launch and rise")}
    let differs=expectedBlocked && launches>0
    if differs {differences += 1}
    rows.append(["hz":hz,"kind":kind,"launchDelay":launchDelay,"referenceSphereOverlaps":referenceOverlaps,"referenceBlocked":expectedBlocked,"actualRequestedLaunches":launches,"actualPeakFeetZ":peak,"groundFrames":groundFrames,"differs":differs])
    // Exercise the actual no-animation input branch as a distinct boundary.
    task.footAnimator=nil;task.footLaunchRemaining=nil
    task.character!.reset(feet:SIMD3(50,0,0),active:true,grounded:true)
    task.verticalSpeed=0;task.pendingNativeJump=0;task.jump()
    let fallbackLaunched=task.pendingNativeJump>0
    if expectedBlocked && fallbackLaunched {differences += 1}
    if !expectedBlocked {precondition(fallbackLaunched && task.verticalSpeed>0)}
    rows.append(["hz":hz,"kind":kind,"mode":"no-animation-input","referenceBlocked":expectedBlocked,"actualPendingJump":task.pendingNativeJump,"differs":expectedBlocked && fallbackLaunched])
   }
  }
  for hz in [30,60,120] {
   let task=try ClimbRuntimeHarness(root:root,top:1.8,depth:2)
   let roof=task.world.addBox(halfExtents:SIMD3(3,0.1,0.1),position:SIMD3(0,2.1,0.05))!
   task.world.setColliderGroups(roof,collision:0x0087ffff,solver:0xffffffff)
   task.world.step();task.footLaunchRemaining=nil;task.jump()
   for _ in 0..<hz {
    _=task.frame(1/Double(hz))
    if task.climb != nil {break}
   }
   precondition(task.climb != nil,"A valid ledge lost precedence to overhead launch clearance")
   rows.append(["hz":hz,"kind":"accepted-climb-precedence","accepted":true])
  }
  let report:[String:Any]=["status":differences>0 ? "ACTUAL_NATIVE_PRELAUNCH_DIFFERENCES":"PASS","cases":rows,"differences":differences,"scope":"Actual byte-preserved native Renderer jump and foot/climb methods, actual CLP decoder/animation and real native Rapier controller. Roofs are authored. Pinned community source establishes the prelaunch requirement; this does not execute the original PC binary or resolve its unreversed CPed collision virtuals."]
  try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:reportURL)
  print("Native prelaunch witness:",rows.count,"actual cases;",differences,"differences")
  precondition(legacy ? differences==12: differences==0,"Unexpected launch admission result")
  exit(differences>0 ? 42:0)
 }
}
