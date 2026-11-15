let root=URL(fileURLWithPath:CommandLine.arguments[1]),game=root.appendingPathComponent("local-only/site/game")
let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:game.appendingPathComponent("native/models/animations.clips.bin")))!
let profiles=try NativeFootWeaponAnimation.load(data:Data(contentsOf:game.appendingPathComponent("native/foot-animation.json")))
let metadata=try NativeMeleeDefinitions(data:Data(contentsOf:root.appendingPathComponent("local-only/native/melee.json")))
let document=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [String:Any]
struct Flight {var on=false}
final class RendererHarness {
 var footWeaponDefinitions=profiles,meleeDefinitions:NativeMeleeDefinitions?=metadata,skeletalLibrary:NativeSkeletalAnimationLibrary?=library
 var footAnimator:NativeFootAnimation?=NativeFootAnimation(library:library,random:{0.37})
 var equippedWeapon=0,health=100,driving=false,swimming=false,climb:Int?,personalFlight=Flight()
 var weaponReady=true,weaponReloading=false,weaponTriggerHeld=false,meleeGuardHeld=false,meleeBlockHeld=false
 let meleeInput=NativeMeleeInput(),footLocomotion=NativeFootLocomotion()
 var meleeClock:Double=0,manualAnimation=false,footLaunchRemaining:Double?,actorHeading:Float=0
 var onMeleeGroundTarget:((NativeMeleeProbe)->Bool)?,onMeleeSwing:((Int)->Void)?,onFootMeleeHit:((NativeMeleeEvent)->Bool)?
 var weaponEventFeet:SIMD3<Float>?,acceptedStreamShot=false,acceptedStreamRay:Int?
 var onFootWeaponShot:((Int,Bool)->Bool)?,hasNativeFootWeaponTiming=false
 func prepareFootAnimation(){}
 func controlsForTest()->NativeMeleeInput.Frame {meleeControls(delta:1/60,grounded:true)}
 func advanceForTest(_ frame:NativeMeleeInput.Frame){advanceMelee(frame,feet:.zero,ratio:0,delta:1/60)}
 // ACTUAL_RENDERER_METHODS
 func step(_ row:[String:Any])->(NativeFootAnimation.Frame,NativeMeleeInput.Frame) {
  equippedWeapon=row["weapon"] as! Int;footAnimator!.arm(profiles[equippedWeapon])
  weaponTriggerHeld=row["held"] as! Bool;meleeGuardHeld=row["guard"] as! Bool;meleeBlockHeld=row["block"] as! Bool
  let dt=(row["delta"] as! NSNumber).doubleValue,ratio=(row["ratio"] as! NSNumber).doubleValue
  let flags=meleeControls(delta:dt,grounded:true)
  var movement=NativeFootLocomotion.Input();movement.stick=ratio>0 ? SIMD2(0,1):.zero
  _ = footLocomotion.update(delta:ratio>0 ? 1:0,input:movement)
  onMeleeGroundTarget={_ in row["ground"] as! Bool}
  advanceMelee(flags,feet:SIMD3(1480,-1738,13),ratio:ratio,delta:dt)
  var input=NativeFootAnimation.Input();input.ratio=ratio;input.guarding=flags.guarding;input.block=flags.blocking
  let frame=footAnimator!.update(delta:dt,input:input)
  emitFootWeaponEvents(frame,feet:SIMD3(1480,-1738,13))
  return (frame,flags)
 }
}
var checks=0,frames=0,events=0,acceptedTotal=0
func check(_ value:Bool,_ label:String){precondition(value,label);checks += 1}
for id in 0...15{check(metadata[id]!.compatible(profiles[id]!,duration:{library.duration(of:$0)}),"Original profile/metadata compatibility\(id)")}
for scenario in document["cases"] as! [[String:Any]] {
 let renderer=RendererHarness();renderer.equippedWeapon=scenario["id"] as! Int
 var accepted=false,event:NativeMeleeEvent?
 renderer.onMeleeSwing={_ in accepted=true}
 renderer.onFootMeleeHit={value in event=value;events += 1;return true}
 for row in scenario["rows"] as! [[String:Any]] {
  accepted=false;event=nil
  let (frame,flags)=renderer.step(row)
  check(accepted==row["accepted"] as! Bool,"Weapon\(renderer.equippedWeapon) request acceptance")
  check(frame.shot==row["shot"] as! Bool,"Actual R6 hit marker")
  check(renderer.footAnimator!.swing==row["swing"] as! Int,"Actual combo index")
  check(renderer.footAnimator!.aside==row["aside"] as? String,"Actual running/ground aside")
  check(flags.guarding==row["guarding"] as! Bool && flags.blocking==row["blocking"] as! Bool,"Actual guard/block gates")
  check((event != nil)==frame.shot,"Renderer dispatches each melee marker exactly once")
  if let event{check(event.feet==SIMD3(1480,-1738,13) && event.weapon==renderer.equippedWeapon,"Event-time selected identity/feet");check(event.attack==(event.aside=="ground" ? -1:event.aside=="run" ? 0:renderer.footAnimator!.swing+1),"Source attack identity")}
  if accepted{acceptedTotal += 1};frames += 1
 }
}
let event=NativeMeleeEvent(weapon:0,attack:1,aside:nil,feet:.zero,heading:0,range:1.6,radius:0.4,simulationTime:0)
for row in document["geometry"] as! [[String:Any]] {
 let c=row["candidate"] as! [String:Any],p=(c["feet"] as! [NSNumber]).map(\.floatValue)
 let candidate=NativeMeleeTargeting.Candidate(id:c["id"] as! String,feet:SIMD3(p[0],p[1],p[2]),heading:(c["heading"] as! NSNumber).floatValue,down:true)
 let probe=NativeMeleeProbe(weapon:0,feet:.zero,heading:(row["heading"] as! NSNumber).floatValue,range:1.6,radius:metadata[0]!.ground!.radius)
 check(NativeMeleeTargeting.groundTarget(probe:probe,candidates:[candidate],visible:{_,_ in true})?.id == row["expected"] as? String,"Actual lt ground geometry")
}
func target(_ x:Float,_ y:Float,_ z:Float=0)->NativeMeleeTargeting.Candidate {.init(id:"victim",feet:SIMD3(x,y,z))}
for (candidate,expected) in [(target(0,3),false),(target(1.7,0.7),false),(target(0,1,2),false),(target(0,1),true),(target(0,-0.2),true)] {
 check((NativeMeleeTargeting.select(event:event,candidates:[candidate],visible:{_,_ in true}) != nil)==expected,"Actual archived OY target example")
}
check(NativeMeleeTargeting.select(event:event,candidates:[target(0,1)],visible:{_,_ in false})==nil,"Wall/missing world fails closed")
let near=NativeMeleeTargeting.Candidate(id:"near",feet:SIMD3(0,1,0)),far=NativeMeleeTargeting.Candidate(id:"far",feet:SIMD3(0.4,1.5,0))
check(NativeMeleeTargeting.select(event:event,candidates:[near,far],visible:{$1.x != 0})==nil,"Occluded chosen victim is not replaced around a wall")
let r=RendererHarness();r.footAnimator!.arm(profiles[0]);check(!r.requestFootMeleeAttack(alternate:true),"Do not counterfeit unknown retail special")
check(r.requestFootMeleeAttack(),"Queue primary")
_ = r.footAnimator!.launch();r.footLaunchRemaining=0.2
let flags=r.controlsForTest();r.advanceForTest(flags)
check(r.footLaunchRemaining==nil,"New strike owns simultaneous pending jump")
check(!r.footAnimator!.update(delta:1/60).blends.contains{$0.clip.contains("jump_launch")},"Rejected launch leaves no jump association")
r.cancelWeaponInput()
for _ in 0..<120{check(r.footAnimator!.update(delta:1/120).shots.isEmpty,"Focus cancellation cannot replay an old hit marker")}
check(!r.controlsForTest().attack,"Focus cancellation discards queued tap")
r.cancelWeaponInput();r.weaponTriggerHeld=true
check(!r.controlsForTest().attack,"Cancelled held input must be released or explicitly pressed")
r.weaponTriggerHeld=false;_ = r.controlsForTest();r.weaponTriggerHeld=true
check(r.controlsForTest().attack,"A neutral sample restores a new trigger edge")
r.cancelWeaponInput()
r.meleeDefinitions=nil;check(!r.hasNativeFootMeleeTiming && !r.requestFootMeleeAttack(),"Missing metadata refuses attack")
let switched=RendererHarness();switched.footAnimator!.arm(profiles[0]);check(switched.requestFootMeleeAttack(),"Queue before selection change")
switched.equippedWeapon=5;switched.footAnimator!.arm(profiles[5]);check(!switched.controlsForTest().attack,"Old selected weapon cannot donate buffered attack")
let blocked=RendererHarness();blocked.footAnimator!.arm(profiles[0]);_ = blocked.requestFootMeleeAttack();blocked.health=0
check(!blocked.controlsForTest().attack,"Dead state refuses queued attack")
blocked.health=100;blocked.climb=1;check(!blocked.hasNativeFootMeleeTiming && !blocked.requestFootMeleeAttack(),"Traversal rejects new task")
blocked.climb=nil;blocked.personalFlight.on=true;check(!blocked.hasNativeFootMeleeTiming,"Flying rejects melee")
var mismatch=profiles[0]!;mismatch.swings![0].loop.fire += 0.01
check(!metadata[0]!.compatible(mismatch,duration:{library.duration(of:$0)}),"Inconsistent animation/data metadata fails closed")
let buffer=NativeMeleeInput();buffer.press(weapon:0);_ = buffer.update(delta:0,weapon:0,held:false,ready:true,canAct:false,guardHeld:false,blockHeld:false,canGuard:true,firing:false)
check(!buffer.update(delta:0.41,weapon:0,held:false,ready:true,canAct:true,guardHeld:false,blockHeld:false,canGuard:true,firing:false).attack,"Expired intent cannot fire after a blocked task")
check(events>0 && acceptedTotal>0,"Real R6 cases must emit")
print("PASS native melee:",frames,"actual input/R6 frames,",checks,"checks,",events,"real marker deliveries; accepted",acceptedTotal)
