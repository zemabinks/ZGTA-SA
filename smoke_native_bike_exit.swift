import Foundation
import simd
final class ExitOwner {func setOwnedVehicle(_ id:String?){};func reset(){}}
final class ExitCollision {func height(x:Float,y:Float,near:Float,maxDrop:Float=1000)->Float?{0}}
final class ExitPlayback {enum State{case stood,seated};var state=State.seated;var chosen:SIMD3<Float>?;var inside:Bool{state == .seated};func beside(side:Int,model:simd_float4x4)->SIMD3<Float>?{chosen}}
struct ExitFeet {var position:SIMD3<Float>;var heading:Float}
final class ExitCamera {var resumedHeading:Float?;func resumeFoot(from:Int?,fallbackHeading:Float,fallbackPitch:Float)->SIMD2<Float>{SIMD2(resumedHeading ?? fallbackHeading,fallbackPitch)}}
final class ExitPedestrian {func perform(_ clip:String,duration:Double){}}
struct ExitVehicle {var id:String;var code:String;var work=0}
final class BikeExitRenderer {
 let groundVehicle:NativeGroundVehicle?,character:NativeCharacterController?
 let ownCameraVisibility=ExitOwner(),vehicleCoupling:ExitOwner?=ExitOwner(),gameCamera=ExitCamera(),pedestrian=ExitPedestrian()
 var ownRiderPlayback:ExitPlayback?=ExitPlayback(),ownRiderFeet:ExitFeet?
 var ownRiderSide = -1
 var pendingExitPlacement:(()->Void)?,vehicleExitSerial:UInt64=0
 var pendingVehicleExit:(()->Void)?
 let collision:ExitCollision?=ExitCollision()
 var camera=SIMD3<Float>(10,20,2),heading:Float=0.7,actorHeading:Float=0.7,verticalSpeed:Float=0
 var currentVehicleID:String?="bike",activeVehicleModel="522",remoteVehicles=[ExitVehicle(id:"bike",code:"522.0.0.0.")]
 var driving=true,drivingSpeed:Float=25,flightVerticalSpeed:Float=1,vehiclePitch:Float=0,vehicleFallbackRoll:Float=0,activeModelOrigin:Float=1
 var activeVehicleDamage="",pendingVehicleBodyPose:Int?,activeHandling:Int?,vehicleKind="bike"
 var climb:Int?,climbPhase:Int?,pendingClimbPull=false,pendingClimbDrop=false,airGrabTicks=0
 var ownRiderPrevious:Int?,ownRiderCapture:Int?,footAnimationFrame:Int?
 var footAirTime=0.0,footAirFall=0.0,footAirFell=false,footJumped=false,footJumpMinimum=0.0,footLaunchRemaining:Double?,footAirVelocity=SIMD2<Double>.zero
 var cameraPitch:Float=0,gameCameraFrame:Int?,cameraWasDriving=true,characterActive=false,crouching=true
 var health=100,vehicleHealth=1000,vehicleDamage="",vehicleWorkingValue:Int?=0
 var onVehicleLostInWater:(()->Void)?
 var onVehicleWrecked:(()->Void)?,onBikeEjection:((NativeBikeEjection.Event)->Void)?
 var footDeathKind:String?,pendingFootHit:SIMD3<Double>?
 var onLocalImpact:((Int)->Void)?
 var onLocalDamage:((Double,Int)->Void)?
 var onLocalHealth:((Int)->Void)?
 let footLocomotion=NativeFootLocomotion(),headingContinuity=NativeHeadingContinuity(),personalFlight=NativePersonalFlightController()
 var footAnimator:NativeFootAnimation?
 var cancelled=false
 var position:SIMD3<Float>{camera}
 var vehicleWirePosition:SIMD3<Float>{groundVehicle!.bodyPosition}
 var direction:Float{driving ? heading:actorHeading};var vehicleNose:Float{vehiclePitch};var vehicleRoll:Float{vehicleFallbackRoll}
 func prepareFootAnimation(){}
 func resolveVehicleExit(wanted:SIMD3<Float>?)->NativeVehicleExitPlanner.Placement{.ready(wanted)}
 func deferVehicleExit(_ retry:@escaping()->Void){pendingExitPlacement=retry}
 func cancelGameplayInput(){cancelled=true;footAnimator?.cancelInput();footAnimator?.cancelMeleeInput()}
 init(root:URL,model:String,library:NativeSkeletalAnimationLibrary,profile:NativeFootWeaponAnimation)throws {
  let fleet=NativeGroundVehicle()!;groundVehicle=fleet
  let data=try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/vehicles.physics.json"))
  precondition(fleet.loadDefinitions(data)==212)
  precondition(fleet.enter(model:model,modelPosition:SIMD3(10,20,2),heading:0.7))
  character=NativeCharacterController(world:fleet.world)
  footAnimator=NativeFootAnimation(library:library,random:{0.37});footAnimator!.arm(profile)
  activeVehicleModel=model;remoteVehicles=[ExitVehicle(id:"bike",code:model+".0.0.0.")]
  footLocomotion.reset(heading:Double(actorHeading))
 }
 func dispatch(){dispatchOwnedVehicleExit()}
 // ACTUAL_RENDERER_EXIT
}
final class ExitNetwork {
 struct Packet {let feet:SIMD3<Float>,parked:SIMD3<Float>,heading:Float,pitch:Float,roll:Float;let health:Int,damage:String,work:Int?;let footHeading:Float?}
 var packets:[Packet]=[]
 func sendExit(_ feet:SIMD3<Float>,parked:SIMD3<Float>,heading:Float,pitch:Float,roll:Float,vehicle:ExitVehicle,vehicleHealth:Int,vehicleDamage:String,vehicleWork:Int?,footHeading:Float?=nil){
  packets.append(.init(feet:feet,parked:parked,heading:heading,pitch:pitch,roll:roll,health:vehicleHealth,damage:vehicleDamage,work:vehicleWork,footHeading:footHeading))
 }
}
enum ExitButtonState {case normal}
final class ExitButton {var title="";func setTitle(_ text:String,for state:ExitButtonState){title=text}}
final class ExitHUD {var hidden=false;func updateVehicle(name:String?,speed:Float){hidden=name==nil}}
final class ExitRadio {var stops=0;func stop(){stops+=1}}
final class BikeExitController {
 var renderer:BikeExitRenderer?,currentVehicle:ExitVehicle?=ExitVehicle(id:"bike",code:"522.0.0.0.")
 let network=ExitNetwork(),vehicleButton=ExitButton(),gameHUD=ExitHUD(),radio=ExitRadio()
 var drivingControls=true
 func setDrivingControls(_ on:Bool){drivingControls=on}
 // ACTUAL_CONTROLLER_EXIT
 func leave(_ event:NativeBikeEjection.Event?,afterExit:(()->Void)?=nil){completeVehicleExit(ejection:event,afterExit:afterExit)}
 func wreck(afterExit:(()->Void)?=nil){completeVehicleExit(wrecked:true,afterExit:afterExit)}
 func waterExit(afterExit:(()->Void)?=nil){completeVehicleExit(water:true,afterExit:afterExit)}
}
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/models/animations.clips.bin")))!
let profiles=try NativeFootWeaponAnimation.load(data:Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/foot-animation.json")))
var checks=0
func check(_ ok:Bool,_ message:String){checks+=1;if !ok{FileHandle.standardError.write(Data("FAIL bike exit: \(message)\n".utf8));exit(1)}}
for model in ["522","481"]{for force in [0.0,100,2500]{for velocity:SIMD3<Double> in [SIMD3(12,0,0),SIMD3(-12,0,0),SIMD3(0,0,12),SIMD3(0,0,-12)]{
 let app=try BikeExitRenderer(root:root,model:model,library:library,profile:profiles[0]!)
 let feet=SIMD3<Float>(10.5,20.2,2.3);app.ownRiderFeet=ExitFeet(position:feet+SIMD3(0,0,0.5),heading:app.actorHeading);app.ownRiderPlayback!.chosen=feet
 var losses:[Int]=[];app.onLocalHealth={losses.append($0)}
 let controller=BikeExitController();controller.renderer=app
 let parked=app.vehicleWirePosition
 let body=app.groundVehicle!.chassisColliders.first.flatMap{app.groundVehicle!.world.colliderInfo($0)?.body}!
 app.groundVehicle!.world.setVelocities(body,linear:SIMD3(4,0,-6),angular:SIMD3(0,0.3,0))
 controller.leave(.init(force:force,velocity:velocity))
 check(!app.driving && app.currentVehicleID==nil && controller.currentVehicle==nil,"Forced exit retained driving ownership")
 check(app.camera==feet && simd_distance(app.character!.state.feet,feet)<0.000002,"Ejection used normal door offset or lost rider feet")
 check(app.characterActive && !app.character!.state.grounded,"Ejection left an inactive/grounded foot motor")
 check(app.cancelled && !app.crouching,"Forced exit retained held gameplay state")
 check(app.health==max(0,100-Int(ceil(force*0.05))),"Independent integer health boundary")
 check(losses==(force>0 ? [app.health]:[]),"Ejection damage reported more than once")
 if app.health>0 {
  let side=NativeFootLocomotion.supportKnockSide(velocity:velocity,heading:0.7)
  check(app.footAnimator!.reportedDown==side+1,"Ejection did not use source directional knock code")
 }else{check(app.footAnimator!.dead && app.footAnimator!.reportedDown==0,"Fatal ejection retained live knock")}
 check(!controller.drivingControls && controller.gameHUD.hidden && controller.radio.stops==1,"Forced exit left vehicle HUD/input/audio active")
 check(controller.network.packets.count==1 && controller.network.packets[0].feet==feet && controller.network.packets[0].parked==parked,"Exit did not publish actual parked/foot snapshots once")
 check(app.groundVehicle!.otherVehicle("bike") != nil && !app.groundVehicle!.active,"Ejection lost the parked physical bike")
 let otherBody=app.groundVehicle!.otherColliders.first.flatMap{app.groundVehicle!.world.colliderInfo($0)?.body}!
 let otherState=app.groundVehicle!.world.bodyState(otherBody)!
 check(simd_distance(SIMD3<Double>(otherState.linearVelocity),SIMD3(4,0,-6))<1e-5,"Ejection discarded vehicle momentum")
 controller.leave(.init(force:100,velocity:velocity))
 check(controller.network.packets.count==1 && losses.count<=1,"Duplicate forced exit replayed ownership/damage")
}}}
print("PASS actual bike Renderer/controller exit: \(checks) checks; real animation/motor/parked physics with explicit network and UI spies")

for model in ["420","522","481","430","519","487"]{for wasAlive in [true,false]{
 let app=try BikeExitRenderer(root:root,model:model,library:library,profile:profiles[0]!)
 let controller=BikeExitController();controller.renderer=app
 let feet=SIMD3<Float>(11,20,2.1);app.ownRiderPlayback!.chosen=feet
 var losses:[Int]=[];app.onLocalHealth={losses.append($0)}
 app.onVehicleWrecked={controller.wreck()}
 app.groundVehicle!.damageController!.state.load(health:0,text:"")
 app.dispatch();check(app.driving && losses.isEmpty,"Disabled vehicle was confused with a completed wreck")
 if !wasAlive {app.health=0;app.footDeathKind="koSpinL";app.footAnimator!.die("koSpinL")}
 app.groundVehicle!.damageController!.state.blowUp(random:{0.37});app.vehicleHealth=0
 app.dispatch()
 check(!app.driving && app.health==0 && app.footAnimator!.dead,"Completed wreck did not kill/eject occupant")
 check(app.camera==feet && simd_distance(app.character!.state.feet,feet)<0.000002,"Wreck exit lost adjacent/native foot placement")
 check(losses==(wasAlive ? [0]:[]),"Completed wreck duplicated an existing death")
 check(app.footDeathKind==(wasAlive ? "koFront":"koSpinL"),"Wreck overwrote an already accepted death cause")
 check(controller.currentVehicle==nil && controller.network.packets.count==1 && !controller.drivingControls,"Wreck retained vehicle transport/control ownership")
 check(controller.network.packets[0].health==0,"Wreck exit published a healthy hull")
 app.dispatch();controller.wreck()
 check(losses.count<=1 && controller.network.packets.count==1,"Repeated wreck replayed death/exit")
}}
print("PASS completed-wreck foot handoff: \(checks) combined checks; cars/bikes/bicycle/boat/aircraft, disabled-vs-wrecked and existing-death preservation")

for model in ["522","481","468"] {
 let app=try BikeExitRenderer(root:root,model:model,library:library,profile:profiles[0]!)
 let controller=BikeExitController();controller.renderer=app
 let feet=SIMD3<Float>(11,20,-2);app.ownRiderPlayback!.chosen=feet
 var losses:[Int]=[];app.onLocalHealth={losses.append($0)};app.onVehicleLostInWater={controller.waterExit()}
 app.groundVehicle!.waterLevel={_ in 0}
 let body=app.groundVehicle!.chassisColliders.first.flatMap{app.groundVehicle!.world.colliderInfo($0)?.body}!
 let state=app.groundVehicle!.world.bodyState(body)!
 app.groundVehicle!.world.setBodyState(.init(position:SIMD3(state.position.x,-10,state.position.z),rotation:state.rotation,linearVelocity:.zero,angularVelocity:.zero),for:body)
 check(app.groundVehicle!.lostInWater,"Deep bike did not use original fallback water threshold")
 app.dispatch()
 check(!app.driving && app.health==100 && losses.isEmpty,"Water exit killed a live occupant")
 check(app.camera==feet && app.characterActive && !app.footAnimator!.dead,"Water exit did not release to native foot/swim owner")
 check(controller.currentVehicle==nil && !controller.drivingControls && controller.network.packets.count==1,"Water exit retained vehicle/controller ownership")
 app.dispatch();controller.waterExit();check(controller.network.packets.count==1 && losses.isEmpty,"Water exit repeated death/transport")
}
print("PASS lost-water forced handoff: \(checks) combined checks; bike/BMX/Sanchez release without manufactured damage")

for shield in [0,25,100]{for force in [100.0,1000,2500,5000]{
 let app=try BikeExitRenderer(root:root,model:"522",library:library,profile:profiles[0]!)
 let controller=BikeExitController();controller.renderer=app
 var prediction=NativeHealthPrediction();prediction.begin(connection:"real-owner",health:100,armour:shield,revision:0,processed:0)
 var callbacks=0,healthOnlyCalls=0
 app.onLocalImpact={damage in callbacks+=1;_ = prediction.impact(damage);app.health=prediction.health}
 app.onLocalHealth={_ in healthOnlyCalls+=1}
 controller.leave(.init(force:force,velocity:SIMD3(12,0,0)))
 let amount=min(200,Int(ceil(force*0.05))),absorbed=min(shield,amount),hp=max(0,100-(amount-absorbed))
 check(callbacks==1 && healthOnlyCalls==0,"Crash sent damage through both health owners")
 check(app.health==hp && prediction.armour==shield-absorbed,"Real forced exit bypassed armour")
 check(app.footAnimator!.dead==(hp==0),"Crash chose death before applying armour")
 if hp>0{check(app.footAnimator!.reportedDown>0,"Absorbed crash lost its directional knock")}
}}
print("PASS armour-aware real forced exit: \(checks) combined checks; one ordered prediction owner and correct knock/death")
