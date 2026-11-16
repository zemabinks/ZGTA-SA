import Foundation
import simd
final class SupportAnimatorProbe {
 var floored=false,knocks:[String]=[]
 func knock(_ value:String)->Bool{knocks.append(value);return true}
}
struct SupportModeProbe {var on=false}
struct RemotePlayer {let id:String,vehicleID:String?;var velocity=SIMD3<Float>.zero,angularVelocity=SIMD3<Float>.zero;var ridingVehicleID:String?,supportVehicleID:String?,supportOffset=SIMD3<Float>.zero}
final class SupportRuntime {
 let groundVehicle:NativeGroundVehicle?,character:NativeCharacterController?
 let supportScene:NativeVehicleSupportScene?,movingSupport:NativeMovingSupport?
 var health=100,driving=false,climb:Int?,swimController=SupportModeProbe(),personalFlight=SupportModeProbe()
 let footLocomotion=NativeFootLocomotion()
 var actorHeading:Float=0,crouching=false,footAnimator:SupportAnimatorProbe?=SupportAnimatorProbe()
 var remotePlayers:[RemotePlayer]=[],currentVehicleID:String?
 init(_ root:URL) throws {
  let ground=NativeGroundVehicle()!,scene=NativeVehicleSupportScene(world:ground.world)
  groundVehicle=ground;character=NativeCharacterController(world:ground.world)!;supportScene=scene;movingSupport=NativeMovingSupport(scene:scene)
  let physics=try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/vehicles.physics.json"));precondition(ground.loadDefinitions(physics)==212)
  let coupling=try Data(contentsOf:root.appendingPathComponent("local-only/selfhost/coupling-catalog.json"));precondition(ground.loadCouplingDefinitions(coupling)==212)
  let treads=try Data(contentsOf:root.appendingPathComponent("local-only/selfhost/tread-catalog.json"));precondition(scene.load(treads))
  ground.onOtherCollidersChanged = {[weak self] in self?.character?.otherColliders=ground.otherColliders}
  configureMovingSupport()
 }
 func sync(_ id:String,model:String,x:Float=0,heading:Float=0,work:Int=0) {
  let poses:[NativeOtherVehicles.Pose]=[.init(id:id,code:model,position:SIMD3(x,0,3),heading:heading,pitch:0,roll:0,work:work,occupied:true)]
  groundVehicle!.synchronizeOtherVehicles(poses,excluding:nil,near:SIMD3(x,0,3),delta:1/60)
  character!.otherColliders=groundVehicle!.otherColliders;synchronizeMovingSupport()
 }
 func tick(_ delta:Double=1/60,jump:Double=0,ready:Bool=true)->NativeCharacterController.Output {
  character!.update(delta:delta,displacement:.zero,jump:jump,geometryReady:ready)
 }
 func remoteAt(_ player:RemotePlayer)->SIMD3<Float>?{remoteSupportPosition(player)}
 // ACTUAL_CALLBACKS
}
@main enum SupportRuntimeGate {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]);var checks=0
  func check(_ ok:Bool,_ message:String){checks+=1;precondition(ok,message)}
  for rate in [20,30,60,90,120] {
   let app=try SupportRuntime(root),ground=app.groundVehicle!,character=app.character!,scene=app.supportScene!,support=app.movingSupport!
   app.remotePlayers=[.init(id:"driver",vehicleID:"truck",velocity:SIMD3(1,0,0))]
   app.sync("truck",model:"403")
   let frame=ground.supportFrames().first!,origin=frame.position+SIMD3(0,8,0)
   guard let distance=scene.treadRay(body:frame.body,origin:origin,distance:20) else{preconditionFailure("Imported truck has no central support surface")}
   let feet=origin-SIMD3(0,distance-0.02,0)
   character.reset(feet:SwiftRapierWorld.rapierToGTA(SIMD3<Float>(feet)),grounded:true)
   for _ in 0..<5{_ = app.tick()}
   check(support.riding && support.held,"Actual Renderer callbacks failed to acquire occupied vehicle support")
   let attached=support.attachment!.at
   for index in 0..<rate*2 {
    app.sync("truck",model:"403",x:Float(index+1)/Float(rate),heading:Float(index+1)/Float(rate)*0.15)
    _ = app.tick(1/Double(rate))
    check(support.riding && support.held,"Moving support detached without a source release condition")
    check(simd_distance(support.attachment!.at,attached)<0.003,"Stationary character slides in vehicle-local axes")
    check(character.supportFeet != nil && simd_distance(character.supportFeet!,SwiftRapierWorld.rapierToGTA(SIMD3<Float>(support.drawnAt!)))<1e-6,"Post-step support presentation is stale")
    let wire=app.footWireSupport!
    check(wire.id=="truck" && simd_distance(wire.offset,SIMD3<Float>(support.attachment!.at))<1e-6,"Native wire lost body-local origin/axes")
    let remote=RemotePlayer(id:"walker",vehicleID:nil,supportVehicleID:wire.id,supportOffset:wire.offset)
    check(app.remoteAt(remote).map{simd_distance($0,character.supportFeet!)<0.00001} == true,"Remote support presentation disagrees with native carried character")
   }
   check(abs(app.actorHeading)>0.1,"Platform yaw was not applied to character facing")
   check(abs(NativeHeadingContinuity.difference(Double(app.actorHeading),from:app.footLocomotion.heading))<1e-6,"Locomotion kept a stale heading after platform rotation")
   let saved=character.state.feet;_ = app.tick(ready:false)
   check(character.state.feet==saved && !character.movementAvailable,"Missing terrain replayed carry or gameplay input")
   _ = app.tick(jump:6.07)
   check(!support.riding && character.state.rising>0,"Jump launch retained vehicle attachment")
   // The ordinary support task must relinquish both display and network
   // attachment when another gameplay owner takes control.
   for mode in ["climb","swim","flight","death","drive"] {
    app.sync("truck",model:"403")
    let body=ground.supportFrames().first!,origin=body.position+SIMD3(0,8,0)
    let down=scene.treadRay(body:body.body,origin:origin,distance:20)!
    character.reset(feet:SwiftRapierWorld.rapierToGTA(SIMD3<Float>(origin-SIMD3(0,down-0.02,0))),grounded:true)
    for _ in 0..<5{_ = app.tick()}
    check(support.riding,"Task transition fixture did not acquire vehicle")
    switch mode {
    case "climb":app.climb=1
    case "swim":app.swimController.on=true
    case "flight":app.personalFlight.on=true
    case "death":app.health=0
    default:app.driving=true
    }
    _ = app.tick()
    check(!support.riding && character.supportFeet==nil && app.footWireSupport==nil,"New gameplay owner retained old support: \(mode)")
    app.climb=nil;app.swimController.on=false;app.personalFlight.on=false;app.health=100;app.driving=false
   }
   character.reset(feet:SIMD3(20,20,10));check(!support.riding && character.supportFeet==nil && !character.supportAfloat,"Teleport retained support presentation")
   check(app.footWireSupport==nil,"Teleport retained network support attachment")
   // Source tumble selection and momentum are dispatched by the actual
   // callback; clip playback remains independently tested by the animator.
   app.crouching=true;character.onSupportMotion?(0,SIMD3(8,0,0))
   check(!app.crouching && app.footAnimator!.knocks==["koSpinR"],"Support knock dispatch lost original side/crouch ownership")
   check(app.footLocomotion.groundMomentum(delta:1/60).x>0,"Support throw failed to seed ground momentum")
   app.footAnimator!.floored=true;character.onSupportMotion?(0,SIMD3(-8,0,0))
   check(app.footAnimator!.knocks.count==1,"Already floored actor was knocked again")
  }
  let app=try SupportRuntime(root)
  app.sync("boat",model:"453");let frame=app.groundVehicle!.supportFrames().first!
  check(frame.kind=="boat","Imported boat kind missing")
  let head=frame.position+SIMD3(0,8,0)
  if let distance=app.supportScene!.treadRay(body:frame.body,origin:head,distance:20){
   app.remotePlayers=[.init(id:"captain",vehicleID:"boat")]
   app.character!.reset(feet:SwiftRapierWorld.rapierToGTA(SIMD3<Float>(head-SIMD3(0,distance-0.02,0))),grounded:true)
   for _ in 0..<5{_ = app.tick()}
   check(app.character!.supportAfloat,"Boat support failed to publish water-entry suppression")
   app.swimController.on=true;_ = app.tick()
   check(!app.movingSupport!.riding && app.character!.supportFeet==nil,"Swimming retained a vehicle support task")
  }else{preconditionFailure("Imported boat has no central support surface")}
  print("PASS native support runtime: \(checks) physical/controller/Renderer dispatch checks across five display rates")
 }
}
