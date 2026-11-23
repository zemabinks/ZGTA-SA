// SPDX-License-Identifier: AGPL-3.0-only
// Actual native owners and authored accepted carriers, not original retail play.
@main enum ClimbCarrierSmoke {
 typealias V=SIMD3<Double>
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1])
  let output=URL(fileURLWithPath:CommandLine.arguments[2])
  let historical=CommandLine.arguments.dropFirst(3).contains("legacy")
  var rows=[[String:Any]](),differences=0,checks=0,failures=[String]()
  func check(_ condition:Bool,_ label:String){checks += 1;if !condition{failures.append(label)}}
  for hz in [30,60,120] {
   for kind in ["translate","rotate","remove"] {
    let task=try ClimbRuntimeHarness(root:root,top:2.7,depth:2,carrier:.kinematicPosition)
    task.footLaunchRemaining=nil;task.jump()
    for _ in 0..<(hz*3) {
     _=task.frame(1/Double(hz));if task.climb?.part == .hang{break}
    }
    precondition(task.climb?.part == .hang,"Normal query/animation must accept a high handhold first")
    let body=task.carrierBody!,initialBody=task.world.bodyState(body)!
    let initialFeet=task.climb!.feet,initialHeading=task.climb!.heading
    var vanished=false
    if kind=="remove" {
     precondition(task.world.removeBody(body))
     for _ in 0..<hz{_=task.frame(1/Double(hz))};vanished=task.climb==nil
    }else{
     for frame in 1...hz {
      var state=initialBody
      if kind=="translate"{state.position.x += Float(frame)/Float(hz)}
      else{state.rotation=simd_quatf(angle:Float.pi/2*Float(frame)/Float(hz),axis:SIMD3(0,1,0))}
      precondition(task.world.setBodyState(state,for:body));_=task.frame(1/Double(hz))
     }
    }
    let feet=task.climb?.feet ?? V(SwiftRapierWorld.gtaToRapier(task.character!.state.feet))
    let heading=task.climb?.heading ?? -Double(task.actorHeading)
    let turn=abs(NativeHeadingContinuity.difference(heading,from:initialHeading))
    let differs=kind=="remove" ? !vanished:kind=="translate" ? abs(feet.x-initialFeet.x)<0.5:turn<0.5
    if differs{differences += 1}
    rows.append(["hz":hz,"kind":kind,"travel":simd_length(feet-initialFeet),"turn":turn,"ended":vanished,"differs":differs])
   }
  }
  if !historical{check(differences==0,"Moving/removal baseline still differs")}
  // Retain the preceding actual controller's static stand/vault phase traces.
  // The Python gate compares these rows exactly when given a negative root.
  for hz in [30,60,120] {
   for top:Float in [1.2,2.7] {
    for depth:Float in [0.2,2] {
     let task=try ClimbRuntimeHarness(root:root,top:top,depth:depth)
     task.footLaunchRemaining=nil;task.jump();task.jumpHeld=true
     var frames=0
     for _ in 0..<(hz*8){_=task.frame(1/Double(hz));frames += 1;if task.completedFeet != nil{break}}
     precondition(task.completedFeet != nil,"Static authored ledge did not complete")
     let feet=task.completedFeet!
     rows.append(["kind":"static-retained-phase","hz":hz,"top":top,"depth":depth,"frames":frames,
                  "part":task.completedPart!.rawValue,"feet":[feet.x,feet.y,feet.z],"phases":task.seen.sorted()])
    }
   }
  }
  #if CLIMB_CARRIER_CURRENT
  func settle(_ hz:Int,_ kind:SwiftRapierWorld.BodyKind = .kinematicVelocity)throws->ClimbRuntimeHarness {
   let task=try ClimbRuntimeHarness(root:root,top:2.7,depth:2,carrier:kind)
   task.footLaunchRemaining=nil;task.jump()
   for _ in 0..<(hz*3){_=task.frame(1/Double(hz));if task.climb?.part == .hang{break}}
   precondition(task.climb?.part == .hang)
   for _ in 0..<hz{_=task.frame(1/Double(hz))}
   return task
  }
  // Real velocity-driven bodies advance in the same shared world.step as the
  // suspended motor. Pose travel and point-velocity prediction must count once.
  for hz in [15,30,60,120,144] {
   for rotating in [false,true] {
    let task=try settle(hz),body=task.carrierBody!,initial=task.world.bodyState(body)!
    let local=initial.rotation.inverse.act(SIMD3<Float>(task.climb!.feet)-initial.position)
    precondition(task.world.setVelocities(body,linear:rotating ? .zero:SIMD3(1,0,0),angular:rotating ? SIMD3(0,1,0):.zero))
    var maximum=0.0,maximumTurn=0.0,previous=task.climb!.heading
    for _ in 0..<(hz*4) {
     _=task.frame(1/Double(hz));precondition(task.climb?.part == .hang)
     let state=task.world.bodyState(body)!,feet=task.climb!.feet
     maximum=max(maximum,simd_distance(feet,V(state.rotation.act(local)+state.position)))
     maximumTurn=max(maximumTurn,abs(task.climb!.heading-previous));previous=task.climb!.heading
    }
    check(maximum<0.003,"Carrier relative-root drift at \(hz)Hz rotating=\(rotating): \(maximum)")
    check(maximumTurn<max(1/Double(hz),1/60.0)*1.05,"Carrier yaw snapped at \(hz)Hz")
    if rotating{check(abs(task.climb!.heading)>3.9,"Rotation did not continue through the angle wrap")}
    rows.append(["hz":hz,"kind":rotating ? "point-velocity-rotation":"point-velocity-translation","maximumRelativeDrift":maximum,"maximumPublishedTurn":maximumTurn])
   }
  }
  // Authored logical resolver, real replacement body and actual query/task/
  // motor. Separate Renderer-owner cases verify the real pool/generation
  // resolvers; this case catches dropping that resolver at the query boundary.
  for hz in [30,60,120] {
   let task=try ClimbRuntimeHarness(root:root,top:2.7,depth:2,carrier:.kinematicPosition)
   let original=task.carrierBody!
   var selected:UInt64?=original,requests=0
   task.climbQueries=NativeRapierClimbQueries(world:task.world,excluded:[task.character!.queries.walker,task.character!.queries.probe],resolverFactory:{body in
    precondition(body==original);requests += 1;return{selected}
   })
   task.footLaunchRemaining=nil;task.jump()
   for _ in 0..<(hz*3){_=task.frame(1/Double(hz));if task.climb?.part == .hang{break}}
   precondition(task.climb?.part == .hang)
   let start=task.climb!.feet,state=task.world.bodyState(original)!
   let replacement=task.world.addBody(kind:.kinematicPosition,position:state.position+SIMD3(1,0,0),rotation:state.rotation)!
   let shape=task.world.addBox(halfExtents:SIMD3(1,1.35,1),body:replacement)!
   precondition(task.world.setColliderGroups(shape,collision:0x0087ffff,solver:0xffffffff))
   selected=replacement;precondition(task.world.removeBody(original))
   for _ in 0..<hz{_=task.frame(1/Double(hz))}
   check(task.climb?.part == .hang,"Actual task dropped a resolver's replacement body")
   check(task.climb.map{abs($0.feet.x-start.x-1)<0.001} == true,"Replacement body did not move the bound root")
   let before=task.fixedSteps;selected=nil
   // A 120-Hz display frame may contain no physical tick. Logical lifetime
   // is consumed by the fixed task, so wait until it has actually advanced.
   for _ in 0..<3{_=task.frame(1/Double(hz));if task.fixedSteps>before{break}}
   check(task.climb==nil && task.world.bodyState(replacement) != nil && requests==1,"Logical removal retained or rebound a valid physical body")
   rows.append(["hz":hz,"kind":"query-resolver-replacement-and-logical-removal","factoryRequests":requests,"physicalTicksAfterRemoval":task.fixedSteps-before])
  }
  // Actual high and low query paths finish on the moving surface. Existing
  // harness assertions also hold motor ownership and unchanged pose clocks.
  for hz in [30,60,120] {
   for top:Float in [1.2,2.7] {
    let task=try ClimbRuntimeHarness(root:root,top:top,depth:2,carrier:.kinematicVelocity)
    let ledge=task.climbQueries!.find(feet:.zero,heading:0)!,body=task.carrierBody!
    let initial=task.world.bodyState(body)!,local=initial.rotation.inverse.act(SIMD3<Float>(ledge.hold)-initial.position)
    // Bind through the same actual Renderer query used above. Sampling a
    // separate pre-jump ray from a different feet height changes its refined
    // top by millimetres and is not the task's accepted handhold.
    task.footLaunchRemaining=nil;precondition(task.attemptClimbForTest())
    var completionBody:SwiftRapierWorld.BodyState?
    task.world.afterStep = {[unowned task] _ in
     if task.climb==nil,task.completedFeet != nil,completionBody==nil{completionBody=task.world.bodyState(body)}
    }
    precondition(task.world.setVelocities(body,linear:SIMD3(1,0,0),angular:.zero));task.jumpHeld=true
    for _ in 0..<(hz*8){_=task.frame(1/Double(hz));if task.climb==nil{break}}
    check(task.climb==nil && task.completedPart == .stand,"Moving stand completion missing at \(hz)Hz top=\(top)")
    // A 30-Hz display frame can advance another physical tick after the task
    // finishes. Compare the held completion root to its own physical tick.
    let state=completionBody!,hold=state.rotation.act(local)+state.position
    var expected=V(hold)+ledge.into*0.15;expected.y=Double(hold.y)
    let actual=V(SwiftRapierWorld.gtaToRapier(task.completedFeet!)),error=simd_distance(actual,expected)
    check(error<0.003,"Moving completion root lost its carrier: \(error)")
    if top>2{check(task.seen.contains(22),"Accepted high carrier skipped the pull pose")}
    rows.append(["hz":hz,"kind":"moving-stand-completion","top":top,"rootError":error,"sample":"first-completion-physical-tick"])
   }
  }
  #endif
  let report:[String:Any]=["status":historical ? "ACTUAL_OLD_CARRIER_DIFFERENCES":failures.isEmpty ? "PASS":"FAIL",
   "baselineCases":9,"cases":rows,"differences":differences,"checks":checks,"failures":failures,
   "scope":"Actual Renderer/climb/animation/Rapier owners. Authored already-admitted carriers and physical velocity; no natural train/boat/surface admission, complete drop momentum, GPU or retail claim."]
  try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output)
  print("Climb carriers:",rows.count,"cases;",checks,"checks;",differences,"baseline differences;",failures)
  exit(historical ? (differences==9 ? 42:1):failures.isEmpty ? 0:1)
 }
}
