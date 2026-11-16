@main enum NativeHitRuntimeGate {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]);var checks=0,physics=0
  func check(_ ok:Bool,_ message:String){checks+=1;if !ok{FileHandle.standardError.write(Data("FAIL hit runtime: \(message)\n".utf8));exit(1)}}
  func make()->ClimbRuntimeHarness {
   let app=try! ClimbRuntimeHarness(root:root,top:4.2,depth:2);app.footLaunchRemaining=nil;return app
  }
  func event(_ weapon:Int,_ damage:Double,_ from:SIMD3<Double>,piece:Int=3,health:Int?=nil)->NativeIncomingHit {
   var packet:[String:Any]=["w":weapon,"d":damage,"fromAt":[from.x,from.y,from.z],"piece":piece,"beforeHealth":100]
   if let health{packet["health"]=health;packet["healthAck"]=["connection":"controlled","revision":1,"processed":0]}
   return NativeIncomingHit(packet)!
  }
  func clip(_ kind:String)->String {
   guard let value=ClimbRuntimeHarness.sharedLibrary!.canonicalName(forWire:"ped/"+NativeFootAnimation.actions[kind]!) else{check(false,"Missing original clip \(kind)");return ""}
   return value
  }
  for bad:[String:Any] in [["w":true,"d":1],["w":22,"d":true],["w":1.5,"d":1],["w":22,"d":Double.nan],["w":22,"d":-1]] {
   check(NativeIncomingHit(bad)==nil,"Malformed feedback became an actor response")
  }
  let defaults=NativeIncomingHit(["d":1])!
  check(defaults.weapon==0 && defaults.piece==3 && defaults.authoritativeHealth==nil,"Original missing-field defaults changed")
  check(NativeIncomingHit(["d":1,"piece":9])!.piece==9,"Head hit decoded as torso")
  check(NativeIncomingHit(["d":1,"fromAt":[true,0,0]],fallbackSource:SIMD3(1,2,3))!.source==SIMD3(1,2,3),"Invalid event source hid a valid tracked source")
  check(NativeIncomingHit(["d":1],fallbackSource:SIMD3(.infinity,0,0))!.source==nil,"Nonfinite source reached physics")
  let predicted=make();predicted.health=0;predicted.footAnimator!.die()
  predicted.receiveHit(event(24,5,SIMD3(-2,0,0),health:95))
  check(predicted.footDeathKind==nil && predicted.pendingFootHit==nil,"Nonfatal server hit replaced a pending local fatal loss")
  for rate in [20,30,60,90,120] {
   let app=make(),rest=make();app.health=70;app.weaponTriggerHeld=true;rest.health=70
   app.receiveHit(event(24,30,SIMD3(-2,0,0)))
   rest.receiveHit(event(24,30,SIMD3(-2,0,0)))
   check(app.health==70,"Visual feedback applied damage a second time")
   check(app.footAnimator!.stunned && !app.weaponTriggerHeld,"Stun did not cancel an unconsumed trigger")
   for _ in 0..<max(1,rate/5){_ = app.frame(1/Double(rate),forward:1);_ = rest.frame(1/Double(rate))}
   check(app.footAnimationFrame!.blends.contains{$0.clip==clip("damStomachLt") && $0.weight>0},"Directional torso reaction did not reach real clips")
   check(app.footAnimationFrame!.shots.isEmpty,"Stun emitted a queued shot")
   check(simd_distance(app.character!.state.feet,rest.character!.state.feet)<0.00001,"Stunned input changed animation-owned physical travel")
   physics += app.fixedSteps

   let partial=make();partial.health=95;partial.weaponTriggerHeld=true
   partial.receiveHit(event(22,5,SIMD3(0,-2,0)))
   check(!partial.footAnimator!.stunned && partial.weaponTriggerHeld,"Partial flinch cancelled unrelated input")
   _ = partial.frame(1/30)
   check(partial.footAnimationFrame!.blends.contains{$0.clip==clip("flinchB") && $0.weight>0},"Rear partial flinch missing")

   let dead=make();dead.health=0;dead.footAnimator!.die("koFront")
   _ = dead.frame(0.1)
   let prior=dead.footAnimationFrame!.blends.first{$0.clip==clip("koFront")}!.time
   dead.receiveHit(event(24,150,SIMD3(-2,0,0),piece:9,health:0))
   check(dead.footDeathKind=="koSpinR" && dead.pendingFootHit != nil,"Accepted death cause/impulse not dispatched")
   let input=dead.pendingFootHit!
   check(input.x>3.5 && abs(input.y-5.0/70*50)<1e-12,"Death impulse axes/scale differ")
   let beforeStep=dead.fixedSteps
   for _ in 0..<3 {
    _ = dead.frame(1/Double(rate));if dead.fixedSteps>beforeStep{break}
   }
   guard let death=dead.footAnimationFrame!.blends.first(where:{$0.clip==clip("koSpinR")}) else{check(false,"Corrected death missing after a motor tick at \(rate)Hz");return}
   check(death.time>=prior,"Late authoritative hit restarted the death clock")
   check(dead.pendingFootHit==nil && dead.character!.state.feet.x>0 && dead.character!.state.rising>0,"Fatal impulse did not enter the actual motor once")
   check(!dead.footAnimationFrame!.hiddenBones.isEmpty,"Head reaction did not reach the real animation frame")
   physics += dead.fixedSteps

   let flying=make();flying.personalFlight.wear(true);flying.personalFlight.takeOff(heading:0);flying.health=0
   flying.receiveHit(event(24,150,SIMD3(-2,0,0),health:0))
   check(!flying.personalFlight.on,"Death retained flight ownership")
  }
  for rate in [20,30,60,90,120] {
   let app=make();app.equippedWeapon=0;app.footAnimator!.arm(app.footWeaponDefinitions[0]);app.weaponTriggerHeld=true
   var guardInput=NativeFootAnimation.Input();guardInput.guarding=true;guardInput.block=true
   for _ in 0..<rate{_ = app.footAnimator!.update(delta:1/Double(rate),input:guardInput)}
   var packet:[String:Any]=["w":0,"d":8,"beforeHealth":100,"health":100,"healthAck":["connection":"controlled"],"parried":true]
   let parried=NativeIncomingHit(packet)!
   check(parried.parried,"Parry feedback not decoded")
   app.receiveHit(parried)
   check(app.health==100 && app.weaponTriggerHeld && !app.footAnimator!.stunned,"Parry cancelled input, damaged health or stunned")
   let definition=app.footWeaponDefinitions[0]!,name=definition.clip("guardBlock")!
   var elapsed=0.0
   for _ in 0..<rate/2 {
    let dt=1/Double(rate);elapsed += dt
    let frame=app.footAnimator!.update(delta:dt,input:guardInput)
    let pose=frame.blends.first{$0.clip==name}!
    let offset=elapsed<0.3 ? (1-abs(1-elapsed/0.3*2))*(definition.guardTo!-definition.guardAt!):0
    check(abs(pose.time-(definition.guardAt!+offset))<1e-10,"Parry block clip clock differs at \(rate)Hz")
    check(frame.shots.isEmpty && app.footAnimator!.reportedAction==28,"Parry emitted attack or lost block tag")
   }
   packet["parried"]=1
   check(!NativeIncomingHit(packet)!.parried,"Numeric parry flag accepted as Boolean")
  }
  for (index,kind) in ["koSkidBack","koSpinR","koSkidFront","koSpinL","floorHit","floorHitF"].enumerated(){
   let app=make();check(app.footAnimator!.knock(kind),"Knock fixture rejected valid action")
   check(app.footWireDown==index+1,"Outgoing knock tag differs from original order")
   check(!app.footAnimator!.knock("koSpinL") && app.footWireDown==index+1,"Rejected knock replaced the live tag")
   var recovery=false,finished=false
   for _ in 0..<600 {
    _ = app.frame(1/120)
    if app.footAnimator!.floored {
     check(app.footWireDown==index+1,"Get-up lost its knock tag")
     recovery = recovery || (app.footAnimationFrame?.blends.contains{$0.clip==clip("getUp") || $0.clip==clip("getUpFront")} ?? false)
    }else{check(app.footWireDown==0,"Recovered character retained knockdown");finished=true;break}
   }
   check(recovery && finished,"Knock/get-up did not complete")
   physics += app.fixedSteps
  }
  print("PASS actual hit runtime: \(checks) checks, \(physics) native ticks; real flinch/stun/death clocks/impulse/head masks and knock/get-up tags")
 }
}
