import Foundation
import simd
let root=URL(fileURLWithPath:CommandLine.arguments[1])
var checks=0
func check(_ condition:Bool,_ label:String){checks+=1;guard condition else{fatalError("Original Renderer: \(label)")}}
let modelIndex=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/models/index.json")))as![String:[String:String]]
let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/models/animations.clips.bin")))!
let definitions=try NativeFootAnimationDefinitions(data:Data(contentsOf:root.appendingPathComponent("local-only/site/game/world/peds.json")))
let weapons=try NativeFootWeaponAnimation.load(data:Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/foot-animation.json")))
func setup()->OriginalRenderer{
 let app=OriginalRenderer();app.pedModels=modelIndex["peds"]!;app.vehicleModels=modelIndex["vehicles"]!;app.skeletalLibrary=library;app.footDefinitions=definitions;app.prepare();return app
}
func snapshot(_ animator:NativeFootAnimation)->[String:String]{
 Dictionary(uniqueKeysWithValues:Mirror(reflecting:animator).children.compactMap{child in
  guard let name=child.label,name != "style",name != "baseStyle"else{return nil}
  return(name,String(reflecting:child.value))
 })
}
func motion(_ app:OriginalRenderer)->String{
 "\(app.actorHeading),\(app.camera),\(app.footAirTime),\(app.footAirFall),\(app.footAirFell),\(app.footJumped),\(app.footJumpMinimum),\(String(describing:app.footLaunchRemaining)),\(app.footAirVelocity)"
}
for scenario in ["walk","sprint","jump","fall","gun","reload","melee","swim","flight","knock","death"]{
 let app=setup(),animator=app.footAnimator!,initial=snapshot(app.footAnimator!);var input=NativeFootAnimation.Input()
 input.ratio=1.7;input.heading=0.7
 if scenario=="sprint"{input.sprint=true}
 if scenario=="jump"{_=animator.launch();input.air="jump"}
 if scenario=="fall"{input.air="fall"}
 if ["gun","reload"].contains(scenario){animator.arm(weapons[22]);input.gun = .init(pitch:0.4,yaw:-0.2);animator.control(.init(fire:scenario=="gun",aim:true,held:true));if scenario=="reload"{_=animator.beginReload()}}
 if scenario=="melee"{animator.arm(weapons[0]);_=animator.fire(held:false)}
 if scenario=="swim"{input.swim = .init(state:5,rate:0.7,pace:1.1,pitch:0.4)}
 if scenario=="flight"{input.fly = .init(state:13,pitch:0.3,roll:-0.4)}
 if scenario=="knock"{_=animator.knock("koSkidBack")}
 if scenario=="death"{animator.die("koSpinL")}
 for i in 0..<8{input.position=SIMD3(Double(i)*0.05,2,3);app.footAnimationFrame=animator.update(delta:1/60,input:input)}
 check(snapshot(animator) != initial,"\(scenario) scenario actually advanced state")
 if scenario=="reload"{check(animator.reloading,"active reload before skin")}
 if scenario=="death"{check(animator.dead,"active death before skin")}
 for skin in [264,1,7,104,7]{
  let before=snapshot(animator),physical=motion(app),dead=animator.dead,reloading=animator.reloading
  check(app.setLocalSkin(skin),"converted skin \(skin)")
  check(app.footAnimator === animator,"\(scenario) kept animator owner")
  check(snapshot(animator)==before,"\(scenario) retained every non-style animation field")
  check(motion(app)==physical,"\(scenario) preserved physics/fall/heading")
  check(animator.dead==dead && animator.reloading==reloading,"\(scenario) did not revive/cancel reload")
  check(app.localSkin==skin && app.loaded.last==modelIndex["peds"]![String(skin)],"actual selected model")
 }
 let count=app.loaded.count
 check(!app.setLocalSkin(0) && app.localSkin==7 && app.loaded.count==count,"unsupported CJ is not another skin")
}
let pending=OriginalRenderer();check(!pending.setLocalSkin(264)&&pending.pendingLocalSkin==264&&pending.localSkin==7,"skin waits for catalogue")
pending.pedModels=modelIndex["peds"]!;check(pending.setLocalSkin(pending.pendingLocalSkin!)&&pending.localSkin==264,"deferred mapped skin applied")
check(!pending.setLocalSkin(-1) && !pending.setLocalSkin(65536),"skin ID bounds")
let legacyData=try Data(contentsOf:root.appendingPathComponent("local-only/original-world-assets/game/native/samp-skins.json"))
let legacyCatalog=try NativeSAMPSkinCatalog(data:legacyData)
check(legacyCatalog.nativeSkin(forLegacy:287)==264 && legacyCatalog.model(forLegacy:287)=="army","retail Army maps by model, not ID offset")
let legacyPending=OriginalRenderer();check(!legacyPending.setLegacySkin(287)&&legacyPending.pendingLegacySkin==287,"legacy skin queues before both catalogues")
check(legacyPending.loadLegacySkinCatalog(legacyData)&&legacyPending.pendingLegacySkin==287,"legacy map waits for model catalogue")
legacyPending.pedModels=modelIndex["peds"]!;check(legacyPending.setLegacySkin(287)&&legacyPending.localSkin==264&&legacyPending.localLegacySkin==287,"real legacy skin selects Army mesh")
check(legacyPending.setLocalSkin(7)&&legacyPending.localLegacySkin==nil,"original browser skin keeps its own namespace")
check(!legacyPending.setLegacySkin(0)&&legacyPending.localSkin==7,"unconverted CJ is explicit gap")
let customRenderer=setup();_=customRenderer.loadLegacySkinCatalog(legacyData)
check(!customRenderer.setLegacySkin(20001)&&customRenderer.pendingLegacySkin==20001,"custom skin waits for a genuinely registered native GPU resource")
customRenderer.legacyPedModels["samp-dl-20001"]=1
customRenderer.pedModels["20001"]="samp-dl-20001";customRenderer.legacyPedStyles["samp-dl-20001"]="army"
let customAnimator=customRenderer.footAnimator!,customState=snapshot(customRenderer.footAnimator!)
check(customRenderer.setLegacySkin(20001)&&customRenderer.localSkin==20001&&customRenderer.localLegacySkin==20001,"registered DL namespace selects the actual resource key")
check(customRenderer.footAnimator === customAnimator && snapshot(customAnimator)==customState,"custom resource selection preserves the locomotion/task owner")
check(!customRenderer.setLegacySkin(20002)&&customRenderer.localSkin==20001,"unavailable custom skin never silently substitutes another model")
for entry in legacyCatalog.mappings.values where entry.nativeID != nil{
 check(legacyPending.setLegacySkin(entry.legacyID),"supported classic model maps")
 check(legacyPending.localSkin==entry.nativeID && legacyPending.loaded.last==entry.model,"correct classic/native model namespace")
}


let physicsData=try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/vehicles.physics.json"))
do{
 let app=setup();app.actorHeading=0;app.camera=SIMD3(0,0,3);app.meleeGuardHeld=true;app.meleeBlockHeld=true
 check(app.canParryOriginalHit(.init(damage:10,weapon:0,point:SIMD3(0,10,3))),"source in actor's front block cone can parry")
 check(!app.canParryOriginalHit(.init(damage:10,weapon:0,point:SIMD3(0,-10,3))) && !app.canParryOriginalHit(.init(damage:10,weapon:0,point:SIMD3(10,0,3))),"back and side cannot parry")
 app.meleeBlockHeld=false;check(!app.canParryOriginalHit(.init(damage:10,weapon:0,point:SIMD3(0,10,3))),"guard alone is not a held block")
 app.meleeBlockHeld=true;app.weaponTriggerHeld=true;check(!app.canParryOriginalHit(.init(damage:10,weapon:0,point:SIMD3(0,10,3))),"attacking does not parry")
 app.weaponTriggerHeld=false;check(!app.canParryOriginalHit(.init(damage:10,weapon:0)),"missing source cannot authorize frontal block")
 app.liftOriginalPlayer(2);check(app.camera==SIMD3(0,0,5)&&app.actorHeading==0,"on-foot slap translates vertically without reversing facing")
}
let emptyCell=Data([0x53,0x43,0x4c,0x32]+Array(repeating:UInt8(0),count:12))
for (altitude,interior,expectedInside) in [(Float(1200),0,false),(Float(3),5,true),(Float(1200),5,true),(Float(3),0,false)] {
 let app=setup(),fleet=app.groundVehicle!;_=fleet.loadDefinitions(physicsData)
 app.camera=SIMD3(10,20,altitude);app.networkInterior=interior
 let wanted=expectedInside ? "i136":"c136",other=expectedInside ? "c136":"i136"
 check(app.activeDetail==wanted && app.activeDetails.allSatisfy{$0.hasPrefix(expectedInside ? "i":"c")},"authoritative scene chooses detailed cells at altitude \(altitude)/interior \(interior)")
 check(app.collisionScene==expectedInside && app.desiredPhysicsCells.contains(wanted),"authoritative scene chooses collision residency")
 check(app.activeFar.isEmpty==expectedInside,"outside high flight retains far world; low interior has no exterior far meshes")
 app.collisions[wanted]=WorldCollision(label:"wanted");app.collisions[other]=WorldCollision(label:"wrong")
 check(app.collision(at:SIMD3(10,20,expectedInside ? 3:1200))?.label=="wanted","ground effect lookup uses actor scene, not sampled point altitude")
 fleet.installCell(other,data:emptyCell)
 check(fleet.isCellLoaded(other),"opposite scene is genuinely resident")
 if case .unavailable(let at)=app.trace(from:app.camera,direction:SIMD3(1,0,0),distance:1){check(at==0,"wrong-scene geometry cannot count as loaded")}
 else{fatalError("Opposite scene incorrectly satisfied authoritative ray")}
 fleet.installCell(wanted,data:emptyCell)
 if case .clear=app.trace(from:app.camera,direction:SIMD3(1,0,0),distance:1){check(true,"matching actual scene geometry is clear")}
 else{fatalError("Correct authoritative scene not used by Renderer ray")}
 app.networkInterior=interior==0 ? 5:0
 check(app.activeDetail==other && app.desiredPhysicsCells.allSatisfy{$0.hasPrefix(expectedInside ? "c":"i")},"stationary interior RPC immediately switches stream and discards old scene requests")
 app.networkInterior=nil
 check(app.activeDetail=="\(altitude>700 ? "i":"c")136","nil preserves browser altitude convention")
}
do {
 let app=setup();app.camera=SIMD3(10,20,3);app.networkInterior=0
 var owner=NativeSAMPGameCamera()
 check(try owner.apply(.init(generation:17,sequence:0,command:.reset),at:1),"server camera reset establishes generation")
 check(try owner.apply(.init(generation:17,sequence:1,command:.cameraPosition(SIMD3(2000,2000,20))),at:1,
    seed:.init(eye:SIMD3(10,15,6),target:SIMD3(10,20,4))),"server camera accepts independent physical world eye")
 app.legacyCameraSample=try owner.sample(at:1,normal:.init(eye:SIMD3(10,15,6),target:SIMD3(10,20,4)))
 app.loadNearby()
 check(app.activeDetail=="c221" && app.activeDetails.contains("c221"),"remote scripted camera streams its actual eye cell")
 check(app.desiredPhysicsCells.contains("c136") && app.desiredPhysicsCells.contains("c221"),"remote camera retains local actor floor alongside remote scene")
 check(app.camera==SIMD3(10,20,3),"server camera never teleports the local actor")
 app.legacyCameraSample=nil;app.loadNearby()
 check(app.activeDetail=="c136","releasing server camera returns scene streaming to local actor")
}
for model in ["420","522","481","430","432","519"]{
 let app=setup(),fleet=app.groundVehicle!;check(fleet.loadDefinitions(physicsData)==212,"real physical definitions")
 check(fleet.enter(model:model,modelPosition:SIMD3(10,20,3),heading:0.7),"enter \(model)")
 app.driving=true;app.activeVehicleModel=model
 let name=modelIndex["vehicles"]![model]!,rigData=try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/models/\(name).rig.json"))
 app.vehicleRigs[name]=NativeVehicleRig(data:rigData)!
 let collider=fleet.chassisColliders.first!,body=fleet.world.colliderInfo(collider)!.body!,base=fleet.world.bodyState(body)!
 for i in 0..<24{
  let axis=simd_normalize(SIMD3<Float>(0.3,1,0.2)),q=simd_quatf(angle:Float(i)*0.27,axis:axis)
  let state=SwiftRapierWorld.BodyState(position:base.position,rotation:q,linearVelocity:SIMD3(2,3,4),angularVelocity:SIMD3(0.1,0.2,0.3))
  check(fleet.world.setBodyState(state,for:body),"set actual live quaternion")
  let actual=app.legacyVehicleQuaternion!,want=SIMD4(q.real,q.imag.x,-q.imag.z,q.imag.y)
  check(simd_distance(actual,want)<0.000002,"full tilted physical quaternion \(model)/\(i)")
  check(simd_distance(actual,SIMD4(cos(Float(0.7)/2),0,0,-sin(Float(0.7)/2)))>0.01 || i==0,"not an Euler yaw reconstruction")
 }
 app.driving=false;check(app.legacyVehicleQuaternion==nil,"no stale quaternion on foot");app.driving=true
 let damage=fleet.damageController!.state
 for weapon in [0,22]{for wheel in [0,1,3,9]{
  damage.fix();app.vehicleHealth=1000;let before=fleet.world.bodyState(body)!
  check(app.receiveOriginalVehicleHit(["t":"vhit","d":25,"w":weapon,"wh":wheel],random:{0.75}) == (model != "432" || weapon==0),"occupied immunity admission")
  let expectedHealth=model=="432" && weapon==22 ? 1000.0:975
  check(damage.health==expectedHealth && app.vehicleHealth==Int(expectedHealth) && app.health==100,"damage uses vehicle owner only \(model)/\(weapon)/\(wheel) actual \(damage.health), \(app.vehicleHealth), actor\(app.health) expected\(expectedHealth)")
  let eligible=model=="420" && wheel<4 || model=="522" && wheel<2
  check(damage.wheels.enumerated().allSatisfy{$0.element == (eligible && $0.offset==wheel ? 1:0)},"original wheel eligibility \(model)/\(wheel)")
  let after=fleet.world.bodyState(body)!
  check((simd_distance(before.linearVelocity,after.linearVelocity)>0)==eligible,"eligible burst gives real physical impulse")
  if eligible{
   check(simd_distance(before.angularVelocity,after.angularVelocity)>0,"eligible burst angular impulse")
   let saved=after;_=app.receiveOriginalVehicleHit(["t":"vhit","d":0,"w":weapon,"wh":wheel],random:{0.75})
   check(simd_distance(saved.linearVelocity,fleet.world.bodyState(body)!.linearVelocity)==0,"already-burst wheel no duplicate impulse")
  }
 }}
 damage.fix();app.driving=false
 check(!app.receiveOriginalVehicleHit(["t":"hit","d":100,"car":true,"w":22]) && damage.health==1000 && app.health==100,"off-foot ownership rejects vehicle hit")
 app.driving=true
 check(!app.receiveOriginalVehicleHit(["t":"hit","d":100,"car":false,"w":22]) && damage.health==1000,"actor hit is not hull damage")
 app.activeModelOrigin=fleet.modelOrigin(model)!
 let beforeLift=fleet.world.bodyState(body)!,beforeTransform=NativeGroundVehicle.transform(position:SIMD3<Double>(beforeLift.position),rotation:simd_quatd(vector:SIMD4<Double>(beforeLift.rotation.vector)),origin:Double(app.activeModelOrigin))
 damage.inflict(0.125);app.liftOriginalPlayer(4)
 let liftedBody=fleet.chassisColliders.first.flatMap{fleet.world.colliderInfo($0)?.body}!,lifted=fleet.world.bodyState(liftedBody)!
 check(simd_distance(lifted.position,beforeLift.position+SIMD3(0,4,0))<0.00001 && simd_distance(lifted.rotation.vector,beforeLift.rotation.vector)<0.000001,"vehicle slap preserves full tilted orientation while raising actual solver")
 check(simd_length(lifted.linearVelocity)==0 && simd_length(lifted.angularVelocity)==0,"vehicle lift rebuilds solver without stale momentum")
 check(abs(damage.health-999.875)<0.000001 && fleet.damageController!.state === damage,"lift retains exact fractional damage owner")
 check(abs(app.camera.z-beforeTransform.columns.3.z-4)<0.00001,"lift model origin matches translated physical pose")
 check(app.flipOriginalVehicle(),"occupied live vehicle can flip")
 let flippedBody=fleet.chassisColliders.first.flatMap{fleet.world.colliderInfo($0)?.body}!,flipped=fleet.world.bodyState(flippedBody)!
 check(simd_distance(flipped.rotation.act(SIMD3(0,1,0)),SIMD3(0,1,0))<0.00001,"flip produces actual upright full solver pose")
 check(abs(app.camera.z-beforeTransform.columns.3.z-5)<0.00001 && damage.health==999.875,"flip raises one metre and preserves damage")
 check(app.repairOriginalVehicle() && damage.health==1000 && app.vehicleHealth==1000 && damage.wheels.allSatisfy{$0==0},"server repair uses actual hull and tyres owner")
 damage.blowUp(random:{0.5});check(!app.flipOriginalVehicle(),"wreck cannot flip")
}
print("PASS actual original Renderer integration: \(checks) checks; skin/task continuity, authoritative interiors/stream/rays, live full quaternion and real vehicle damage/tyre physics")
