import Foundation
import simd

@main enum VehicleCouplingGate {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]),reference=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [String:Any]
  let data=try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/vehicles.physics.json")),catalogData=try Data(contentsOf:root.appendingPathComponent("local-only/selfhost/coupling-catalog.json"))
  let catalog=(try JSONSerialization.jsonObject(with:catalogData) as! [String:Any])["models"] as! [String:[String:Any]]
  var checks=0
  func check(_ condition:Bool,_ message:String){checks+=1;precondition(condition,message)}
  func matches(_ request:NativeVehicleCoupling.Request?,parent:String,trailer:String?,kind:NativeVehicleCoupling.Kind)->Bool {
   request.map{$0.parent==parent && $0.trailer==trailer && $0.kind==kind && $0.generation>0} ?? false
  }
  let sourceControls=reference["controls"] as! [String:[String:Any]]
  for held in [false,true] {for fallen in [false,true] {for speed in [0.0,4.999,5,5.001,20] {
   let expected=sourceControls[held ? "held":fallen ? (speed<5 ? "riderlessBraked":"riderless"):(speed<5 ? "braked":"base")]!
   let actual=NativeUnattendedVehicle.controls(velocity:SIMD3(0,0,speed),wetness:0.3,held:held,fallen:fallen),pedals=expected["pedals"] as! [Double]
   check(actual.nobody==(expected["nobody"] as! Bool),"Original unattended nobody policy")
   check(actual.abandoned==(expected["abandoned"] as! Bool),"Hauled rig inherited abandoned behavior")
   check(actual.riderless==(expected["riderless"] as? Bool ?? false),"Hauled rig inherited riderless behavior")
   check(actual.pedals==SIMD2(pedals[0],pedals[1]) && actual.drive?.pedals==actual.pedals,"Hauled rig retained parked low-speed brake")
   check(actual.wetness==0.3 && actual.drive?.handbrake==false,"Unattended environmental/control contract")
  }}}
  for row in reference["rows"] as! [[String:Any]] {
   let id=row["id"] as! Int,hz=(row["hz"] as! NSNumber).doubleValue,initial=row["initial"] as! Int
   let definition=NativeGroundVehicle.CouplingDefinition(catalog[String(id)]!)!
   var state=NativeGroundVehicle.WorkingState();state.seat(value:initial,tow:definition.working!.tow)
   for frame in row["frames"] as! [[String:Any]] {
    state.update(delta:1/hz,pad:(frame["pad"] as! NSNumber).doubleValue,towed:false,configuration:definition.working!)
    let actual=state.frame(definition,towed:false)!,expected=frame["value"] as! Int
    check(actual.value==expected,"Actual archived working value differs model\(id) \(hz)Hz")
    check(abs(actual.preciseValue-(frame["precise"] as! NSNumber).doubleValue)<1e-9,"Continuous working angle differs from original visual/physics input")
    check(abs(actual.kitValue-((frame["kit"] as! [NSNumber])[0]).doubleValue)<1e-12,"Actual archived work kit differs")
   }
  }
  let forklift=NativeGroundVehicle()!;check(forklift.loadDefinitions(data)==212,"Forklift definitions");check(forklift.loadCouplingDefinitions(catalogData)==212,"Forklift coupling definitions")
  let forkPose=NativeUnattendedVehicle.Pose(position:SIMD3(200,20,-200),rotation:simd_quatd(angle:0.6,axis:simd_normalize(SIMD3(1,2,0.3))))
  check(forklift.enter(model:"530",modelPosition:SIMD3(200,200,20),heading:0,bodyPose:forkPose),"Forklift create")
  check(forklift.hasWorkingControls && forklift.workingPlateColliders.count==2,"Fork plates not created")
  let plateIDs=forklift.workingPlateColliders.sorted(),forkBody=forklift.ownedCouplingVehicle(id:"fork")!.body!
  _=forklift.world.recomputeMassProperties(forkBody);let forkMass=forklift.world.mass(of:forkBody)
  for sample in reference["plates"] as! [[String:Any]] {
   let value=sample["value"] as! Int;forklift.setWorkingValue(value)
   let shapes=sample["shapes"] as! [[String:Any]],body=forklift.world.bodyState(forkBody)!
   check(forklift.workingPlateColliders.sorted()==plateIDs,"Working height recreated colliders")
   for (index,id) in plateIDs.enumerated(){
    let expected=shapes[index],p=expected["position"] as! [Double],half=expected["half"] as! [Double],info=forklift.world.colliderInfo(id)!
    let world=body.position+body.rotation.act(SIMD3<Float>(Float(p[0]),Float(p[1]),Float(p[2])))
    check(simd_distance(info.translation,world)<0.00005,"Fork plate local motion lost parent transform")
    check(info.body==forkBody,"Fork plate detached from parent")
    if case .box(let actual)=info.shape {check(simd_distance(actual,SIMD3<Float>(Float(half[0]),Float(half[1]),Float(half[2])))<1e-7,"Original fork plate half-extents differ")}else{check(false,"Fork plate not a cuboid")}
   }
   // Parent motion must preserve the just-updated local lift without requiring
   // a physics step or an unrelated body mutation to refresh collision queries.
   var moved=body;moved.position += SIMD3(0.4,0.1,-0.2);moved.rotation=simd_quatf(angle:Float(value)/3000,axis:SIMD3(0,1,0));_=forklift.world.setBodyState(moved,for:forkBody)
   for (index,id) in plateIDs.enumerated(){let p=shapes[index]["position"] as! [Double],expected=moved.position+moved.rotation.act(SIMD3(Float(p[0]),Float(p[1]),Float(p[2])));check(simd_distance(forklift.world.colliderInfo(id)!.translation,expected)<0.00005,"Fork plate failed to follow moving parent")}
  }
  let work=forklift.workingValue;forklift.workingControl=1;forklift.cancelPendingInput()
  _=forklift.world.recomputeMassProperties(forkBody);check(forklift.world.mass(of:forkBody)==forkMass,"Zero-density working plates changed vehicle mass")
  check(forklift.workingControl==0 && forklift.workingValue==work,"Input cancellation reset physical work position")
  forklift.teleport(modelPosition:SIMD3(210,210,20),heading:0.3)
  check(forklift.workingValue==work && forklift.workingPlateColliders.count==2,"Teleport lost working position or plates")
  check(plateIDs.allSatisfy{forklift.world.colliderInfo($0)==nil},"Teleport retained old fork plates")
  let replacement=forklift.workingPlateColliders;forklift.exit();check(forklift.workingPlateColliders.isEmpty && replacement.allSatisfy{forklift.world.colliderInfo($0)==nil},"Exit retained fork colliders")
  let physicsRows=(try JSONSerialization.jsonObject(with:data) as! [String:Any])["models"] as! [String:[String:Any]]
  for model in reference["moving"] as! [[String:Any]] {
   let id=model["id"] as! Int,mover=NativeGroundVehicle()!;_=mover.loadDefinitions(data);_=mover.loadCouplingDefinitions(catalogData)
   let pose=NativeUnattendedVehicle.Pose(position:SIMD3(50,10,-50),rotation:simd_quatd(angle:0.4,axis:simd_normalize(SIMD3(0.2,1,0.3))))
   check(mover.enter(model:String(id),modelPosition:SIMD3(50,50,10),heading:0,bodyPose:pose),"Moving working vehicle create")
   let bodyID=mover.ownedCouplingVehicle(id:"owned")!.body!,ids=mover.chassisColliders.sorted(),base=physicsRows[String(id)]!["chassis"] as! [[String:Any]]
   for sample in model["frames"] as! [[String:Any]] {
    let value=sample["value"] as! Int;mover.setWorkingValue(value)
    let changed=Dictionary(uniqueKeysWithValues:(sample["shapes"] as! [[String:Any]]).map{($0["index"] as! Int,$0["position"] as! [Double])}),body=mover.world.bodyState(bodyID)!
    for (index,collider) in ids.enumerated(){
     let point=changed[index] ?? (base[index]["centre"] as! [Double]),local=SIMD3<Float>(Float(point[0]),Float(point[1]),Float(point[2]))
     check(simd_distance(mover.world.colliderInfo(collider)!.translation,body.position+body.rotation.act(local))<0.00002,"Material65 collider/untagged baseline differs from actualvh")
    }
   }
   // The same source work value is retained by a parked dynamic rig, then by
   // its kinematic demotion and subsequent native solver promotion.
   mover.setWorkingValue(1250);let finalPose=mover.ownedCouplingVehicle(id:"owned")!.pose
   mover.parkCurrentVehicle(id:"parked",code:String(id),health:1000,damage:"",work:1250)
   func checkParked(){
    let vehicle=mover.otherCouplingVehicle(id:"parked")!,body=mover.world.bodyState(vehicle.body!)!,profile=vehicle.configuration
    let ordered=mover.otherColliders.sorted()
    for shape in profile.working!.movingShapes {
     let local=NativeGroundVehicle.workingPosition(shape.at,value:1250,configuration:profile)
     check(simd_distance(mover.world.colliderInfo(ordered[shape.index])!.translation,body.position+body.rotation.act(SIMD3<Float>(local)))<0.00002,"Parked working collider lost its imported pose")
    }
   }
   checkParked()
   var parked=NativeOtherVehicles.Pose(id:"parked",code:String(id),position:SwiftRapierWorld.rapierToGTA(SIMD3<Float>(finalPose.position)),heading:0,pitch:0.001,roll:0,work:1250);parked.kept=true
   mover.synchronizeOtherVehicles([parked],excluding:nil,near:parked.position,delta:0);check(mover.otherCouplingVehicle(id:"parked")?.dynamic==false,"Working rig did not demote");checkParked()
   parked.kept=false;mover.synchronizeOtherVehicles([parked],excluding:nil,near:parked.position,promoteNear:parked.position,delta:0);check(mover.otherCouplingVehicle(id:"parked")?.dynamic==true,"Working rig did not re-promote");checkParked()
  }
  func floorData()->Data {
   var bytes=Data();func word(_ value:UInt32){var little=value.littleEndian;withUnsafeBytes(of:&little){bytes.append(contentsOf:$0)}}
   [UInt32(0x324c4353),4,2,1].forEach(word)
   for value:Float in [-1000,-1000,0,1000,-1000,0,1000,1000,0,-1000,1000,0]{word(value.bitPattern)}
   [UInt32(0),1,2,0,2,3].forEach(word);bytes.append(contentsOf:[2,2,0,0,1,1,0,0]);return bytes
  }
  func coast(hauled:Bool)->Double {
   let scene=NativeGroundVehicle()!;_=scene.loadDefinitions(data);_=scene.loadCouplingDefinitions(catalogData);scene.installCell("floor",data:floorData())
   var hookSteps=0;scene.onCouplingStep={delta in check(abs(delta-1/60)<1e-12,"Coupling hook did not use the fixed step");hookSteps+=1}
   let source=NativeOtherVehicles.Pose(id:"coast",code:"400",position:SIMD3(0,0,3),heading:0,pitch:0.001,roll:0)
   scene.synchronizeOtherVehicles([source],excluding:nil,near:source.position,promoteNear:source.position,delta:0)
   if hauled {check(scene.haulOtherVehicle(id:"coast") != nil,"Coast fixture haul failed")}
   for _ in 0..<180 {scene.synchronizeOtherVehicles([source],excluding:nil,near:source.position,promoteNear:source.position,delta:1/60);_=scene.world.step()}
   let body=scene.otherCouplingVehicle(id:"coast")!.body!,before=scene.world.bodyState(body)!
   _=scene.world.setVelocities(body,linear:SIMD3(0,0,-2),angular:.zero)
   for _ in 0..<60 {scene.synchronizeOtherVehicles([source],excluding:nil,near:source.position,promoteNear:source.position,delta:1/60);_=scene.world.step()}
   let after=scene.world.bodyState(body)!
   check(hookSteps==240,"Coupling hook replaced or skipped the parked-force step")
   return Double(before.position.z-after.position.z)
  }
  let heldDistance=coast(hauled:true),parkedDistance=coast(hauled:false)
  // The archived held profile also changes abandoned axle friction. Do not
  // invent a monotonic stopping-distance rule: the source constants above
  // establish the correct inputs; this real pool test establishes that its
  // hauled flag actually reaches the force controller rather than being lost.
  check(abs(heldDistance-parkedDistance)>0.01,"Actual hauled pool ignored its distinct original force profile: held\(heldDistance), parked\(parkedDistance)")
  let fleet=NativeGroundVehicle()!;check(fleet.loadDefinitions(data)==212,"Vehicle physics load");check(fleet.loadCouplingDefinitions(catalogData)==212,"Coupling metadata load")
  let start=NativeUnattendedVehicle.Pose(position:SIMD3(1000,10,-1000),rotation:simd_quatd(angle:0,axis:SIMD3(0,1,0)))
  check(fleet.enter(model:"485",modelPosition:SIMD3(1000,1000,10),heading:0,bodyPose:start),"Tow tractor creation")
  let head=fleet.ownedCouplingVehicle(id:"cab")!,firstConfig=NativeGroundVehicle.CouplingDefinition(catalog["606"]!)!,secondConfig=NativeGroundVehicle.CouplingDefinition(catalog["607"]!)!
  let firstAt=start.position+head.configuration.rearAnchor!-firstConfig.trailerAnchor!,secondAt=firstAt+firstConfig.rearAnchor!-secondConfig.trailerAnchor!
  func park(_ id:String,_ model:String,_ at:SIMD3<Double>,linear:SIMD3<Double> = .zero) {
   let source=NativeOtherVehicles.Pose(id:id,code:model,position:SwiftRapierWorld.rapierToGTA(SIMD3<Float>(at)),heading:0,pitch:0.001,roll:0)
   // Use the production streamed pool, without a mock body/solver carrier.
   // A temporary owned body is unnecessary: source synchronization promotes
   // the actual unattended solver at the requested physical pose.
   fleet.synchronizeOtherVehicles([source],excluding:"cab",near:source.position,promoteNear:source.position,delta:0)
   if let body=fleet.otherCouplingVehicle(id:id)?.body,let state=fleet.world.bodyState(body){
    _=fleet.world.setBodyState(.init(position:SIMD3<Float>(at),rotation:simd_quatf(angle:0,axis:SIMD3(0,1,0)),linearVelocity:SIMD3<Float>(linear),angularVelocity:state.angularVelocity),for:body)
   }
  }
  park("first","606",firstAt)
  let coupler=NativeVehicleCoupling(ground:fleet);var requests:[NativeVehicleCoupling.Request]=[]
  coupler.onRequest={requests.append($0);return true};coupler.setOwnedVehicle("cab");coupler.update(nowMilliseconds:0)
  check(requests.isEmpty && coupler.activeJointCount==0,"Unconnected coupling acquired")
  coupler.reset(connection:"fixture-A");coupler.setOwnedVehicle("cab");coupler.update(nowMilliseconds:0)
  check(requests.count==1 && matches(requests.first,parent:"cab",trailer:"first",kind:.trailer),"Compatible hitch candidate not requested")
  coupler.update(nowMilliseconds:1);check(requests.count==1 && coupler.activeJointCount==0,"Speculative joint or duplicate request")
  let first=NativeVehicleCoupling.Link(parent:"cab",trailer:"first",kind:.trailer),second=NativeVehicleCoupling.Link(parent:"first",trailer:"second",kind:.trailer)
  check(!coupler.applyTopology([first],revision:1,connection:"foreign",nowMilliseconds:2),"Foreign topology accepted")
  check(coupler.applyTopology([first],revision:1,connection:"fixture-A",nowMilliseconds:3),"Confirmed topology refused")
  check(coupler.activeJointCount==1 && fleet.otherCouplingVehicle(id:"first")?.hauled==true,"Confirmed first joint missing")
  check(!coupler.applyTopology([],revision:0,connection:"fixture-A",nowMilliseconds:4),"Old topology cleared current joint")
  check(!coupler.applyTopology([],revision:1,connection:"fixture-A",nowMilliseconds:4),"Conflicting equal revision accepted")
  check(!coupler.applyTopology([first,.init(parent:"first",trailer:"cab",kind:.trailer)],revision:2,connection:"fixture-A",nowMilliseconds:5),"Cycle accepted")
  // Retain the first source while introducing the next compatible trailer.
  let firstSource=NativeOtherVehicles.Pose(id:"first",code:"606",position:SwiftRapierWorld.rapierToGTA(SIMD3<Float>(firstAt)),heading:0,pitch:0.001,roll:0)
  let secondSource=NativeOtherVehicles.Pose(id:"second",code:"607",position:SwiftRapierWorld.rapierToGTA(SIMD3<Float>(secondAt)),heading:0,pitch:0.001,roll:0)
  fleet.synchronizeOtherVehicles([firstSource,secondSource],excluding:"cab",near:secondSource.position,promoteNear:secondSource.position,delta:0)
  if let body=fleet.otherCouplingVehicle(id:"second")?.body { _=fleet.world.setBodyState(.init(position:SIMD3<Float>(secondAt),rotation:simd_quatf(angle:0,axis:SIMD3(0,1,0))),for:body) }
  coupler.update(nowMilliseconds:10);check(matches(requests.last,parent:"first",trailer:"second",kind:.trailer),"Second trailer candidate missing")
  check(coupler.applyTopology([first,second],revision:2,connection:"fixture-A",nowMilliseconds:11),"Second confirmed topology refused")
  check(coupler.activeJointCount==2 && fleet.otherCouplingVehicle(id:"second")?.hauled==true,"Second physical link missing")
  check(!coupler.applyTopology([first,second,.init(parent:"second",trailer:"third",kind:.trailer)],revision:3,connection:"fixture-A",nowMilliseconds:12),"Three trailers accepted")
  check(coupler.applyTopology([second,first],revision:2,connection:"fixture-A",nowMilliseconds:13),"Equal-revision row reorder was not idempotent")
  for _ in 0..<180 {fleet.synchronizeOtherVehicles([],excluding:"cab",near:SIMD3(3000,3000,3000),delta:1/60)}
  check(fleet.otherCouplingVehicle(id:"first")?.dynamic==true && fleet.otherCouplingVehicle(id:"second")?.dynamic==true,"Hauled rest/distance demoted a live joint endpoint")
  let before1=fleet.otherCouplingVehicle(id:"first")!.body!,before2=fleet.otherCouplingVehicle(id:"second")!.body!
  _=fleet.world.setVelocities(before1,linear:SIMD3(3,1,-2),angular:SIMD3(0.1,0.2,0.3));_=fleet.world.setVelocities(before2,linear:SIMD3(-1,2,4),angular:SIMD3(0.3,0.2,0.1))
  let speed1=fleet.world.bodyState(before1)!,speed2=fleet.world.bodyState(before2)!
  coupler.requestRelease(nowMilliseconds:20);check(coupler.activeJointCount==2,"Release input removed an unconfirmed link")
  check(matches(requests.last,parent:"cab",trailer:nil,kind:.trailer),"Release request missing")
  check(coupler.applyTopology([],revision:3,connection:"fixture-A",nowMilliseconds:21),"Confirmed release refused")
  check(coupler.activeJointCount==0 && fleet.otherCouplingVehicle(id:"first")?.hauled==false && fleet.otherCouplingVehicle(id:"second")?.hauled==false,"Released endpoints retained haul flags")
  check(fleet.world.bodyState(before1)!.linearVelocity==speed1.linearVelocity && fleet.world.bodyState(before1)!.angularVelocity==speed1.angularVelocity,"First release erased momentum")
  check(fleet.world.bodyState(before2)!.linearVelocity==speed2.linearVelocity && fleet.world.bodyState(before2)!.angularVelocity==speed2.angularVelocity,"Second release erased momentum")
  let count=requests.count;coupler.update(nowMilliseconds:22);check(requests.count==count,"Released trailer immediately reacquired")
  coupler.update(nowMilliseconds:2521);check(requests.count==count+1,"Released trailer never became eligible after2500ms")
  check(coupler.applyTopology([first,second],revision:4,connection:"fixture-A",nowMilliseconds:2522),"Reacquire topology")
  check(coupler.activeJointCount==2,"Reacquired constraints missing")
  _=fleet.removeOtherVehicle(id:"first");coupler.update(nowMilliseconds:2523)
  check(coupler.activeJointCount==0 && fleet.otherCouplingVehicle(id:"second")?.hauled==false,"Missing first body retained downstream joint")
  coupler.reset(connection:"fixture-B");check(coupler.activeJointCount==0 && coupler.owner==nil,"Fresh connection retained ownership")
  check(!coupler.applyTopology([first],revision:999,connection:"fixture-A",nowMilliseconds:2524),"Old connection recreated constraints")
  let truck=NativeGroundVehicle()!;_=truck.loadDefinitions(data);_=truck.loadCouplingDefinitions(catalogData)
  check(truck.enter(model:"525",modelPosition:SIMD3(1000,1000,10),heading:0,bodyPose:start),"Towtruck create");truck.setWorkingValue(2500)
  let bar=truck.workingFrame!.localTowAnchor!,car=NativeGroundVehicle.CouplingDefinition(catalog["400"]!)!,carAt=start.position+bar-car.frontAnchor
  let carSource=NativeOtherVehicles.Pose(id:"car",code:"400",position:SwiftRapierWorld.rapierToGTA(SIMD3<Float>(carAt)),heading:0,pitch:0.001,roll:0)
  truck.synchronizeOtherVehicles([carSource],excluding:"truck",near:carSource.position,promoteNear:carSource.position,delta:0)
  let carBody=truck.otherCouplingVehicle(id:"car")!.body!
  _=truck.world.setBodyState(.init(position:SIMD3<Float>(carAt),rotation:simd_quatf(angle:0,axis:SIMD3(0,1,0))),for:carBody)
  let towing=NativeVehicleCoupling(ground:truck);var towRequests:[NativeVehicleCoupling.Request]=[]
  towing.reset(connection:"tow-A");towing.setOwnedVehicle("truck");towing.onRequest={towRequests.append($0);return true}
  towing.update(nowMilliseconds:0,towAnchor:bar,canAcquireTow:false);check(towRequests.isEmpty,"Raised/inactive tow control acquired")
  towing.update(nowMilliseconds:1,towAnchor:bar,canAcquireTow:true);check(matches(towRequests.last,parent:"truck",trailer:"car",kind:.tow),"Towtruck target not requested")
  let tow=NativeVehicleCoupling.Link(parent:"truck",trailer:"car",kind:.tow)
  check(towing.applyTopology([tow],revision:1,connection:"tow-A",nowMilliseconds:2),"Tow topology rejected")
  check(towing.activeJointCount==0,"Tow topology created a joint without its moving anchor")
  towing.update(nowMilliseconds:3,towAnchor:bar,canAcquireTow:true);check(towing.activeJointCount==1 && truck.otherCouplingVehicle(id:"car")?.hauled==true,"Confirmed tow joint missing")
  let raised=bar+SIMD3<Double>(0,0.25,0);towing.update(nowMilliseconds:4,towAnchor:raised,canAcquireTow:false)
  check(towing.activeJointCount==1,"Moving tow anchor broke a close vehicle")
  towing.update(nowMilliseconds:5,towAnchor:SIMD3(.nan,0,0));check(towing.activeJointCount==1,"Invalid anchor poisoned an existing joint")
  var acceptDetach=false;let detachCount=towRequests.count
  towing.onRequest={towRequests.append($0);return $0.trailer != nil || acceptDetach}
  _=truck.world.setBodyState(.init(position:SIMD3<Float>(carAt+SIMD3(3.1,0,0)),rotation:simd_quatf(angle:0,axis:SIMD3(0,1,0))),for:carBody)
  towing.update(nowMilliseconds:6,towAnchor:raised);check(towing.activeJointCount==0 && truck.otherCouplingVehicle(id:"car")?.hauled==false,"Tow separation did not release its solver pin")
  check(matches(towRequests.last,parent:"truck",trailer:nil,kind:.tow),"Broken tow did not request authoritative detach")
  check(towRequests.count==detachCount+1,"Broken constraint sent duplicate cleanup in one fixed step")
  towing.update(nowMilliseconds:7,towAnchor:raised);check(towRequests.count==detachCount+2,"Declined cleanup was lost after its physical joint disappeared")
  acceptDetach=true;towing.update(nowMilliseconds:8,towAnchor:raised);check(towRequests.count==detachCount+3,"Cleanup did not resume when transport accepted delivery")
  towing.update(nowMilliseconds:9,towAnchor:raised);check(towRequests.count==detachCount+3,"Accepted pending cleanup was replayed without an ACK")
  _=towing.applyTopology([],revision:2,connection:"tow-A",nowMilliseconds:10);towing.update(nowMilliseconds:11,towAnchor:raised)
  check(towRequests.count==detachCount+3,"Confirmed topology removal retained obsolete cleanup intent")
  let towDefinition=NativeGroundVehicle.CouplingDefinition(catalog["525"]!)!
  var phase=NativeGroundVehicle.WorkingState();phase.seat(value:2500,tow:true)
  phase.update(delta:1/60,pad:0,towed:true,configuration:towDefinition.working!)
  check(phase.angle==19900,"Tow acquisition phase did not retain source100-unit correction")
  phase.update(delta:1/60,pad:1,towed:true,configuration:towDefinition.working!)
  phase.update(delta:1/60,pad:-1,towed:true,configuration:towDefinition.working!)
  check(phase.frame(towDefinition,towed:true)!.dropRequested && phase.consumeDrop() && !phase.consumeDrop(),"Tow lower/drop latch did not fire exactly once")
  check(!phase.frame(towDefinition,towed:false)!.canAcquireTow,"Dropped tow instantly reattached at the same bar height")
  phase.update(delta:1/60,pad:1,towed:false,configuration:towDefinition.working!);phase.update(delta:1/60,pad:-1,towed:false,configuration:towDefinition.working!)
  check(phase.frame(towDefinition,towed:false)!.canAcquireTow,"Raised/lowered tow never rearmed")
  _=truck.world.setBodyState(.init(position:SIMD3<Float>(carAt),rotation:simd_quatf(angle:0,axis:SIMD3(0,1,0))),for:carBody)
  for hz in [15,30,60,120,144] {
   let retry=NativeVehicleCoupling(ground:truck);retry.reset(connection:"retry");retry.setOwnedVehicle("truck")
   var attempts:[Double]=[],time=0.0,last:NativeVehicleCoupling.Request?
   retry.onRequest={last=$0;attempts.append(time);return true}
   for frame in 0..<(2*hz) {
    time=1000*Double(frame)/Double(hz);last=nil;retry.update(nowMilliseconds:time,towAnchor:bar,canAcquireTow:true)
    if let last {retry.rejectRequest(last)}
   }
   check(attempts.count==4,"Negative ACK reacquisition rate depends on frame rate")
   check(zip(attempts,attempts.dropFirst()).allSatisfy{pair in pair.1-pair.0>=500-1e-8},"Negative ACK retries exceeded2/s")
   let count=attempts.count;time+=1
   _=retry.applyTopology([],revision:1,connection:"retry",nowMilliseconds:time);retry.update(nowMilliseconds:time,towAnchor:bar,canAcquireTow:true)
   check(attempts.count==count+1,"New authority did not clear obsolete denial context")
   if let last {retry.rejectRequest(last)}
   retry.setOwnedVehicle(nil);retry.setOwnedVehicle("truck");retry.update(nowMilliseconds:time,towAnchor:bar,canAcquireTow:true)
   check(attempts.count==count+2,"New owned vehicle context retained old denial")
  }
  let inline=NativeVehicleCoupling(ground:truck);inline.reset(connection:"inline");inline.setOwnedVehicle("truck");var inlineAttempts=0
  inline.onRequest={inlineAttempts+=1;inline.rejectRequest($0);return true}
  inline.update(nowMilliseconds:0,towAnchor:bar,canAcquireTow:true);inline.update(nowMilliseconds:499,towAnchor:bar,canAcquireTow:true)
  check(inlineAttempts==1,"Synchronous rejection escaped acquisition backoff")
  inline.update(nowMilliseconds:500,towAnchor:bar,canAcquireTow:true);check(inlineAttempts==2,"Synchronous rejection never rearmed")
  let scoped=NativeVehicleCoupling(ground:truck);scoped.reset(connection:"scope-A");scoped.setOwnedVehicle("truck");var scopedRequests:[NativeVehicleCoupling.Request]=[]
  scoped.onRequest={scopedRequests.append($0);return true};scoped.update(nowMilliseconds:0,towAnchor:bar,canAcquireTow:true)
  let old=scopedRequests.last!;scoped.setOwnedVehicle(nil);scoped.setOwnedVehicle("truck");scoped.update(nowMilliseconds:1,towAnchor:bar,canAcquireTow:true)
  let current=scopedRequests.last!;check(current.generation != old.generation,"Owner change reused request generation")
  scoped.rejectRequest(old);scoped.update(nowMilliseconds:2,towAnchor:bar,canAcquireTow:true)
  check(scopedRequests.count==2,"Old owner ACK cleared a newer identical pending request")
  scoped.reset(connection:"scope-B");scoped.setOwnedVehicle("truck");scoped.update(nowMilliseconds:3,towAnchor:bar,canAcquireTow:true)
  let fresh=scopedRequests.last!;scoped.rejectRequest(current);scoped.update(nowMilliseconds:4,towAnchor:bar,canAcquireTow:true)
  check(scopedRequests.count==3 && fresh.generation != current.generation,"Old connection ACK changed current pending state")
  scoped.removeVehicle("car");scoped.update(nowMilliseconds:5,towAnchor:bar,canAcquireTow:true)
  let replacementRequest=scopedRequests.last!;scoped.rejectRequest(fresh);scoped.update(nowMilliseconds:6,towAnchor:bar,canAcquireTow:true)
  check(scopedRequests.count==4 && replacementRequest.generation != fresh.generation,"Removed-entity ACK escaped its generation")
  print("PASS vehicle coupling: \(checks) actual native checks; archived working scalar/material65/forkplate/held-input profiles, confirmed chain/tow lifecycle and ACK scope; held coast\(heldDistance)m vs parked\(parkedDistance)m")
 }
}
