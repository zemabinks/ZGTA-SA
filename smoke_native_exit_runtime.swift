let root=URL(fileURLWithPath:CommandLine.arguments[1])
let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/models/animations.clips.bin")))!
let profiles=try NativeFootWeaponAnimation.load(data:Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/foot-animation.json")))
let riders=try JSONDecoder().decode(NativeRiderDefinitions.self,from:Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/riders.json")))
var checks=0
func check(_ ok:Bool,_ message:String){checks+=1;if !ok{print("FAIL exit runtime:",message);exit(1)}}
func instance(_ model:String="420",metadata:Bool=true)throws->BikeExitRenderer {
 let app=try BikeExitRenderer(root:root,model:model,library:library,profile:profiles[0]!)
 let floor=app.groundVehicle!.world.addBox(halfExtents:SIMD3(100,0.25,100),position:SIMD3(0,-0.25,0))!
 app.groundVehicle!.world.setColliderGroups(floor,collision:131071,solver:0xffffffff)
 app.riderDefinitions=metadata ? riders:nil
 app.character!.otherColliders=app.groundVehicle!.otherColliders
 return app
}
for model in ["420","411","522","481","430","519","487","406","610","407"] {for metadata in [true,false] {
 let app=try instance(model,metadata:metadata)
 app.ownRiderPlayback=nil;app.ownRiderFeet=nil
 let controller=BikeExitController();controller.renderer=app
 guard case .ready(let first?)=app.resolve(wanted:nil) else{check(false,"Known scene did not yield a placement");fatalError()}
 let old=app.camera,world=app.groundVehicle!.world,body=app.groundVehicle!.chassisColliders.first.flatMap{world.colliderInfo($0)?.body}!
 let physical=SwiftRapierWorld.gtaToRapier(first)
 check(app.character!.motor.fits(SIMD3<Double>(physical),widening:0.2,excludingBody:body),"Placement overlaps static geometry")
 check(abs(first.z)<0.00001,"Flat ground placement did not use actual downward query")
 let wall=world.addBox(halfExtents:SIMD3(0.4,2,0.4),position:physical+SIMD3(0,1,0))!
 world.setColliderGroups(wall,collision:131071,solver:0xffffffff)
 var completions=0
 controller.leave(nil,afterExit:{
  completions+=1
  check(!app.driving && controller.currentVehicle==nil && controller.network.packets.count==1,"Completion preceded vehicle/network commit")
  check(controller.gameHUD.hidden && !controller.drivingControls && controller.radio.stops==1,"Completion preceded UI/radio commit")
 })
 check(!app.driving && controller.currentVehicle==nil,"Normal/missing-metadata exit did not complete")
 check(simd_distance(app.camera,first)>0.4,"Blocked first exit was reused")
 check(app.character!.motor.fits(SIMD3<Double>(SwiftRapierWorld.gtaToRapier(app.camera)),excludingBody:body),"Exit ended inside the wall")
 check(app.characterActive && simd_distance(app.character!.state.feet,app.camera)<0.00001,"Placed foot/motor state differ")
 check(controller.network.packets.count==1 && controller.network.packets[0].feet==app.camera,"Exit packet differs from placed feet")
 check(app.pendingExitPlacement==nil && !controller.drivingControls && controller.gameHUD.hidden,"Exit retained pending ownership or UI")
 check(simd_distance(old,app.camera)>0.1,"Missing metadata left actor at seated origin")
 check(completions==1,"Normal exit completion was not exactly once")
}}
for mode in ["normal","bike","wreck","water"] {
 let app=try instance(mode=="bike" ? "522":"420")
 let controller=BikeExitController();controller.renderer=app
 var losses:[Int]=[];app.onLocalHealth={losses.append($0)}
 app.geometryReady=false
 let event:NativeBikeEjection.Event?=mode=="bike" ? .init(force:100,velocity:SIMD3(12,0,0)):nil
 var completions=0
 let completed={completions+=1;check(!app.driving && controller.currentVehicle==nil && controller.network.packets.count==1 && controller.gameHUD.hidden && !controller.drivingControls,"Deferred completion preceded full commit")}
 if mode=="wreck"{controller.wreck(afterExit:completed)}else if mode=="water"{controller.waterExit(afterExit:completed)}else{controller.leave(event,afterExit:completed)}
 check(app.driving && app.groundVehicle!.active && controller.currentVehicle != nil,"Unknown geometry released the hull")
 check(controller.network.packets.isEmpty && controller.drivingControls && !controller.gameHUD.hidden,"Unknown geometry changed transport/UI")
 check(app.health==100 && losses.isEmpty && !app.footAnimator!.dead,"Deferred forced exit applied damage early")
 check(app.pendingExitPlacement != nil && !app.requestedCells.isEmpty,"Unknown cells were not requested/retried")
 check(completions==0,"Completion ran before geometry became available")
 let retry=app.pendingExitPlacement;app.pendingExitPlacement=nil;app.geometryReady=true;retry?()
 check(!app.driving && !app.groundVehicle!.active && controller.currentVehicle==nil,"Loaded retry failed to complete")
 check(controller.network.packets.count==1,"Deferred exit did not publish exactly once")
 check(app.health==(mode=="wreck" ? 0:mode=="bike" ? 95:100),"Deferred exit lost its damage cause")
 check(app.pendingExitPlacement==nil,"Completed exit retained a replay")
 retry?();check(controller.network.packets.count==1 && completions==1,"Consumed retry replayed exit or completion")
}
for changed in ["renderer","vehicleID","sameIDnewGeneration","discard"] {
 let app=try instance(),controller=BikeExitController();controller.renderer=app;app.geometryReady=false
 var completions=0;controller.leave(nil,afterExit:{completions+=1})
 let retry=app.pendingExitPlacement
 if changed=="renderer" {controller.renderer=try instance()}
 else if changed=="vehicleID" {controller.currentVehicle=ExitVehicle(id:"other",code:"420.0.0.0.")}
 else if changed=="sameIDnewGeneration" {app.vehicleExitSerial &+= 1}
 else {app.discard()}
 app.geometryReady=true;retry?()
 check(controller.network.packets.isEmpty,"Stale exit released replacement ownership: "+changed)
 check(changed=="discard" || app.driving,"Stale retry exited old live vehicle: "+changed)
 check(completions==0,"Discarded vehicle identity ran completion: "+changed)
}
// Place the preferred side just inside a loaded cell. Only its widened
// capsule corner crosses the boundary; unknown space must still defer.
do {
 let app=try instance();app.ownRiderSide=1;app.ownRiderPlayback=nil
 guard case .ready(let first?)=app.resolve(wanted:nil) else{fatalError()}
 let position=app.groundVehicle!.modelPosition+SIMD3(-first.x-0.1,0,0)
 check(app.groundVehicle!.enter(model:"420",modelPosition:position,heading:0.7),"Boundary setup")
 guard case .ready(let feet?)=app.resolve(wanted:nil) else{fatalError()}
 check(feet.x<0 && feet.x > -0.3,"Boundary exit not just inside cell")
 let corner=feet+SIMD3(0.55,-0.55,0)
 let cells=NativeWorldRay.coverage(from:corner,to:corner+SIMD3(0,0,0.001),interior:false,loaded:{_ in true})!.cells
 app.missingCells=cells;app.requestedCells=[]
 let controller=BikeExitController();controller.renderer=app;controller.leave(nil)
 check(app.driving && controller.network.packets.isEmpty && app.pendingExitPlacement != nil,"Capsule corner crossed missing geometry")
 check(cells.isSubset(of:app.requestedCells),"Missing capsule corner cell was not requested")
}
print("PASS actual native exit runtime: \(checks) checks; real Rapier walls/floors, ten models with/without rider metadata, normal/crash/wreck/water deferred exits, stale identities and capsule-cell edges")
// A delayed normal exit can become a wreck before geometry arrives. Resolve
// the current stronger cause before choosing living foot animation/damage.
do {
 let app=try instance(),controller=BikeExitController();controller.renderer=app
 var losses:[Int]=[];app.onLocalHealth={losses.append($0)}
 app.geometryReady=false;controller.leave(nil)
 let retry=app.pendingExitPlacement
 app.groundVehicle!.damageController!.state.blowUp(random:{0.37});app.vehicleHealth=0
 app.geometryReady=true;retry?()
 check(!app.driving && app.health==0 && app.footAnimator!.dead,"Deferred normal exit ignored a completed wreck")
 check(losses==[0] && controller.network.packets.count==1,"Stronger delayed exit duplicated health/transport")
}
do {
 let app=try instance(),controller=BikeExitController();controller.renderer=app
 app.geometryReady=false;controller.leave(nil);app.geometryReady=true;app.dispatch()
 RunLoop.current.run(until:Date(timeIntervalSinceNow:0.1))
 check(!app.driving && controller.network.packets.count==1,"Display dispatch did not run deferred exit")
}
do {
 let app=try instance(),controller=BikeExitController();controller.renderer=app
 app.ownRiderPlayback!.state = .stood
 app.ownRiderFeet=ExitFeet(position:app.camera,heading:1.9)
 controller.leave(nil)
 check(!app.driving && abs(app.actorHeading-1.9)<0.00001,"Placement overwrote completed exit facing")
 check(app.characterActive && simd_distance(app.camera,app.character!.state.feet)<0.00001,"Completed animation root was not reconciled with the motor")
}
print("PASS delayed cause, display retry and completed-animation facing: \(checks) combined runtime checks")

// Preserve three separate roles at an ordinary exit: physical chassis yaw,
// final actor root facing and the player's resumed camera orbit.
do {
 let app=try instance(),controller=BikeExitController();controller.renderer=app
 app.heading=0.7;app.actorHeading=0.7;app.gameCamera.resumedHeading = -2.4
 app.ownRiderPlayback!.state = .stood
 app.ownRiderFeet=ExitFeet(position:app.camera,heading:1.9)
 controller.leave(nil)
 check(controller.network.packets.count==1,"Normal exit did not publish once")
 let packet=controller.network.packets[0]
 check(abs(packet.heading-0.7)<0.00001,"Foot facing overwrote parked body yaw")
 check(packet.footHeading.map{abs($0-1.9)<0.00001} == true,"Exit packet lost the final actor facing")
 check(abs(app.heading-(-2.4))<0.00001 && abs(app.actorHeading-1.9)<0.00001,"Camera/actor heading roles collapsed")
}
print("PASS first exit packet facing: \(checks) combined runtime checks; separate actor/body/camera angles")
