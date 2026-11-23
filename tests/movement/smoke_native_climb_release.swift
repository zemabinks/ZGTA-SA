// SPDX-License-Identifier: AGPL-3.0-only
@main enum ClimbReleaseSmoke {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]),output=URL(fileURLWithPath:CommandLine.arguments[2])
  let legacy=CommandLine.arguments.contains("legacy")
  var rows=[[String:Any]](),differences=0,checks=0
  let rates=legacy ? [30,60,120]:[15,30,60,120,144]
  let kinds=legacy ? ["requested-abort","carrier-removed","vault-finish"]:["requested-abort","carrier-removed","vault-finish","stand-finish","death-abort"]
  for hz in rates {for kind in kinds {for angle in (legacy ? [0.0]:[0.0,0.7,-2.3]) {
   let stand=kind=="stand-finish",finishes=stand || kind=="vault-finish"
   let task=try ClimbRuntimeHarness(root:root,top:stand ? 1.2:2.7,depth:kind=="vault-finish" ? 0.2:2,angle:angle,
                                    carrier:kind=="carrier-removed" ? .kinematicPosition:nil)
   task.footLaunchRemaining=nil;task.jump();task.jumpHeld=finishes
   for _ in 0..<(hz*3){_=task.frame(1/Double(hz));if task.climb != nil{break}}
   precondition(task.climb != nil,"The actual query must admit the handhold")
   let floor=task.world.raycast(origin:SIMD3(20,3,20),direction:SIMD3(0,-1,0),distance:5)!
   precondition(task.world.removeCollider(floor.collider))
   if stand {
    let wall=task.world.raycast(origin:SIMD3(Float(-sin(angle)),4,Float(-cos(angle))),direction:SIMD3(0,-1,0),distance:6)!
    var removed=false;let after=task.world.afterStep
    task.world.afterStep = {[unowned task] dt in
     after?(dt)
     // Finish the accepted task before removing its authored stand surface.
     // An ordinary surface-contact stand is covered by retained climb tests.
     if !removed,task.completedFeet != nil {precondition(task.world.removeCollider(wall.collider));removed=true}
    }
   }
   if !finishes {
    for _ in 0..<(hz*3){_=task.frame(1/Double(hz));if task.climb?.part == .hang{break}}
    precondition(task.climb?.part == .hang)
    for _ in 0..<hz{_=task.frame(1/Double(hz))}
   }
   var velocities=[Double](),overrides=[Double?](),travel=[SIMD3<Float>]()
   let before=task.world.beforeStep
   task.world.beforeStep = {[unowned task] dt in
    before?(dt)
    if velocities.count<3,task.completedFeet != nil,task.expectedHeld==nil {
     velocities.append(task.character!.motor.rising);overrides.append(task.observedVerticalOverride);travel.append(task.observedTravel)
    }
   }
   if kind=="requested-abort"{task.letGoOfLedge()}
   if kind=="carrier-removed"{precondition(task.world.removeBody(task.carrierBody!))}
   if kind=="death-abort"{task.health=0}
   for _ in 0..<(hz*8){_=task.frame(1/Double(hz));if velocities.count==3{break}}
   precondition(velocities.count==3,"Three actual free physics ticks must be observed")
   if finishes {precondition(task.completedPart == (stand ? .stand:.vault))}
   let expected=stand ? -0.5:-2.5
   let differs=abs(velocities[0]-expected)>0.000001 || overrides[0] != expected
   if differs{differences += 1}
   if !legacy {
    precondition(!differs,"First free tick lost its cause-specific vertical release")
    precondition(overrides[1]==nil && overrides[2]==nil,"Exit override replayed on subsequent physics ticks")
    precondition(velocities[1]<velocities[0] && velocities[2]<velocities[1],"Ordinary gravity did not resume")
    let speed:Double=stand ? 2.5:kind=="vault-finish" ? 1:0
    let expectedTravel=SIMD2(-sin(angle),cos(angle))*speed
    let actualTravel=SIMD2(Double(travel[0].x),Double(travel[0].y))*60
    precondition(simd_distance(actualTravel,expectedTravel)<0.005,"Release inherited, reversed or lost horizontal momentum")
    precondition(task.climb==nil && !task.footJumped && task.footCalls>0,"The normal foot owner did not resume")
    #if CLIMB_RELEASE_CURRENT
    precondition(task.pendingClimbRelease==nil)
    #endif
    checks += 7
   }
   rows.append(["hz":hz,"kind":kind,"angle":angle,"firstFreeRising":velocities[0],"firstFreeVerticalOverride":overrides[0].map{$0 as Any} ?? NSNull(),"secondFreeRising":velocities[1],"firstFreeTravel":[travel[0].x,travel[0].y,travel[0].z],"differs":differs])
  }}}
  #if CLIMB_RELEASE_CURRENT
  // These instantiate the real task with an unreachable authored target.
  // Only failure-to-settle may push back; a requested abort must not do so.
  for high in [false,true] {for angle in [0.0,0.4,1.5,-2.1,Double.pi] {
   let direction=SIMD3<Double>(-sin(angle),0,-cos(angle))
   let ledge=NativeClimbController.Ledge(hold:SIMD3(0,3,0),into:direction,heading:angle,high:high,vault:false)
   let task=NativeClimbController(ledge:ledge,feet:SIMD3(100,0,100),durations:.init(jump:0.3,pull:0.3,stand:0.3,vault:0.3))
   var ended:NativeClimbController.End?
   for _ in 0..<180 {ended=task.step(delta:1/60,pull:false,drop:false);if ended != nil{break}}
   precondition(ended == .drop)
   precondition(simd_distance(task.releaseVelocity!,direction*(-5)+SIMD3(0,-2.5,0))<1e-12)
   let requested=NativeClimbController(ledge:ledge,feet:.zero,durations:.init(jump:0.3,pull:0.3,stand:0.3,vault:0.3))
   precondition(requested.step(delta:1/60,pull:false,drop:true) == .drop)
   precondition(requested.releaseVelocity==SIMD3(0,-2.5,0))
   rows.append(["kind":"timeout-versus-request","high":high,"angle":angle,"differs":false]);checks += 4
  }}
  #endif
  let result:[String:Any]=["status":legacy ? "ACTUAL_OLD_RELEASE_DIFFERENCES":"PASS","cases":rows,"differences":differences,"checks":checks,
   "scope":"Actual selected Renderer, local original CLP, task, motor and native Rapier. Authored geometry isolation; timeout uses actual task with unreachable target. No executed retail/caller-order, UI, GPU or physical-device acceptance."]
  try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]).write(to:output)
  print("Actual climb release:",rows.count,"cases;",differences,"differences;",checks,"checks")
  exit(legacy ? (differences==9 ? 42:1):(differences==0 ? 0:1))
 }
}
