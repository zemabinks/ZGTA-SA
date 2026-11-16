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
 lazy var legacyCollisionWorld=groundVehicle.flatMap{try?NativeRenderWareCollisionWorld(world:$0.world)}
 var legacyCollisionHandles:[UInt16:[NativeRenderWareCollisionWorld.Handle]]=[:]
 var legacyObjectClock=NativeSAMPObjectSimulationClock()
 var stepProbeHandle:NativeRenderWareCollisionWorld.Handle?,stepProbeOrigin:Double?
 var stepProbeTimes:[Double]=[],stepProbeOrder:[String]=[]
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
 func installAuthoredObject(_ id:UInt16=900)throws->NativeRenderWareCollisionWorld.Handle {
  let surface=NativeRenderWareCollision.Surface(material:0,flags:nil,brightness:nil,lighting:255)
  let mesh=NativeRenderWareCollision.Mesh(vertices:[SIMD3(-4,-4,0),SIMD3(4,-4,0),SIMD3(4,4,0),SIMD3(-4,4,0)],
   faces:[.init(a:0,b:1,c:2,surface:surface),.init(a:0,b:2,c:3,surface:surface)])
  let model=NativeRenderWareCollision.Model(version:.col3,name:"own_support_fixture",modelID:0,
   bounds:.init(minimum:SIMD3(-4,-4,0),maximum:SIMD3(4,4,0),center:.zero,radius:6),flags:2,
   spheres:[],boxes:[],mesh:mesh,faceGroups:[],shadowMesh:nil)
  let handle=try legacyCollisionWorld!.insert(.init(id:UInt64(id)<<32,model:model,transform:.init(position:SIMD3(0,0,3)),cameraCollision:false))
  legacyCollisionHandles[id]=[handle]
  precondition(groundVehicle!.world.step());synchronizeMovingSupport();return handle
 }
 func moveAuthoredObject(_ handle:NativeRenderWareCollisionWorld.Handle,x:Float,yaw:Float)throws {
  try legacyCollisionWorld!.move(handle,to:.init(position:SIMD3(x,0,3),rotation:simd_quatf(angle:yaw,axis:SIMD3(0,0,1))))
 }
 func removeAuthoredObject(_ id:UInt16=900) {
  for handle in legacyCollisionHandles.removeValue(forKey:id) ?? []{precondition(legacyCollisionWorld!.remove(handle))}
  synchronizeMovingSupport()
 }
 func configureObjectStepProbe(_ handle:NativeRenderWareCollisionWorld.Handle) {
  stepProbeHandle=handle;stepProbeOrigin=nil;legacyObjectClock.reset()
  // ACTUAL_KINEMATIC_CALLBACK
  let prior=groundVehicle!.onCouplingStep
  groundVehicle!.onCouplingStep = {[weak self] delta in self?.stepProbeOrder.append("coupling");prior?(delta)}
 }
 /// Narrow staging delegate: the Renderer callback and fixed-step dispatcher
 /// remain actual source. Full Store/import resolution has its own gates.
 private func synchronizeLegacyObjectPhysics(at timestamp:Double) {
  stepProbeTimes.append(timestamp);stepProbeOrder.append("kinematic")
  if stepProbeOrigin==nil{stepProbeOrigin=timestamp}
  guard let handle=stepProbeHandle else{return}
  let elapsed=Float(timestamp-stepProbeOrigin!)
  try! legacyCollisionWorld!.move(handle,to:.init(position:SIMD3(elapsed*0.2,0,3),rotation:simd_quatf(angle:elapsed*0.05,axis:SIMD3(0,0,1))))
 }
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
  // Use the actual updated Renderer callback to discover an authored COL object,
  // then carry/turn the real controller on its true parented Rapier triangles.
  let objectApp=try SupportRuntime(root),objectCharacter=objectApp.character!,objectSupport=objectApp.movingSupport!
  let objectHandle=try objectApp.installAuthoredObject(),objectWorld=objectApp.legacyCollisionWorld!
  let objectBody=objectWorld.bodyID(for:objectHandle.entityID)!,objectColliders=objectWorld.colliderIDs(for:objectHandle)!
  objectCharacter.reset(feet:SIMD3(0.75,0.25,3.02),grounded:true)
  for _ in 0..<6{_ = objectApp.tick()}
  check(objectSupport.riding && !objectSupport.held,"Actual object callback failed to acquire ordinary standing support")
  check(objectApp.supportScene!.entries.contains{$0.id=="object:900" && $0.handle==objectBody && $0.standing && $0.vehicle==nil},"Actual callback omitted authored object body")
  check(objectApp.footWireSupport?.id=="object:900","Standing object attachment lost its separate wire identity")
  let objectOffset=objectApp.footWireSupport!.offset
  for frame in 1...120 {
   try objectApp.moveAuthoredObject(objectHandle,x:Float(frame)*0.01,yaw:Float(frame)*0.003)
   _ = objectApp.tick()
   check(objectSupport.riding && objectSupport.through==objectBody,"Authored moving object lost its real support body")
   let wire=objectApp.footWireSupport!,motion=objectWorld.motion(entityID:objectHandle.entityID)!
   let expected=motion.transform.rotation.act(wire.offset)+motion.transform.position
   check(simd_distance(wire.offset,objectOffset)<0.003,"Stationary character slides in authored object local coordinates")
   check(objectCharacter.supportFeet.map{simd_distance($0,expected)<0.00002} == true,"Object carry presentation disagrees with native body pose")
   check(!objectCharacter.supportAfloat,"Ordinary authored object acquired boat water suppression")
  }
  check(abs(objectApp.actorHeading)>0.2,"Authored object rotation did not carry character facing")
  check(objectWorld.cameraExcludedColliderIDs==Set(objectColliders),"Camera-only exclusion disturbed standing support")
  objectApp.removeAuthoredObject()
  for _ in 0..<4{_ = objectApp.tick()}
  check(!objectSupport.riding && objectCharacter.supportFeet==nil && objectApp.footWireSupport==nil,"Removed authored object retained controller/presentation/wire attachment")
  check(objectApp.groundVehicle!.world.bodyState(objectBody)==nil && objectColliders.allSatisfy{objectApp.groundVehicle!.world.colliderInfo($0)==nil},"Object support removal leaked native body/collider")
  let replacement=try objectApp.installAuthoredObject()
  check(replacement.generation != objectHandle.generation && !objectWorld.remove(objectHandle),"Reused object ID accepted stale support handle")
  objectCharacter.reset(feet:SIMD3(0.75,0.25,3.02),grounded:true)
  for _ in 0..<6{_ = objectApp.tick()}
  check(objectSupport.riding && objectSupport.through==objectWorld.bodyID(for:replacement.entityID),"Reused object ID did not acquire its fresh native body")
  objectApp.removeAuthoredObject()
  for rate in [15,20,30,60,90,120,144] {
   let stepped=try SupportRuntime(root),handle=try stepped.installAuthoredObject(),ground=stepped.groundVehicle!
   stepped.configureObjectStepProbe(handle)
   stepped.character!.reset(feet:SIMD3(100,100,10))
   var velocities:[Float]=[]
   let originalAfter=ground.world.afterStep
   ground.world.afterStep = {[weak stepped] delta in
    originalAfter?(delta)
    if let value=stepped?.legacyCollisionWorld?.motion(entityID:handle.entityID){velocities.append(value.linearVelocity.x)}
   }
   for _ in 0..<(rate*2){_ = stepped.tick(1/Double(rate))}
   check(stepped.stepProbeTimes.count==120 && velocities.count==120,"Actual kinematic callback lost/doubled native ticks at \(rate)Hz")
   check(stepped.stepProbeOrder==Array(repeating:["kinematic","coupling"],count:120).flatMap{$0},"Kinematic staging ran after coupling at \(rate)Hz")
   for index in 1..<120 {
    check(abs(stepped.stepProbeTimes[index]-stepped.stepProbeTimes[index-1]-1/60.0)<1e-8,"Catch-up ticks consumed wall/display time at \(rate)Hz")
    check(abs(velocities[index]-0.2)<0.0001,"Kinematic target jumped then stopped within catch-up steps at \(rate)Hz")
   }
   stepped.removeAuthoredObject()
  }
  print("PASS native support runtime: \(checks) physical/controller/Renderer dispatch checks across five display rates plus authored object translate/rotate/remove/reuse carry and 120 fixed kinematic ticks at seven display rates")
 }
}
