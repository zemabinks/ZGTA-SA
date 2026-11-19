import Foundation
import simd

@main enum VehicleSupportSmoke {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1])
  let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [String:Any]
  let raw=(try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/vehicles.physics.json")))) as! [String:Any]
  let models=raw["models"] as! [String:[String:Any]]
  let definitions=models.compactMapValues { row -> NativeGroundVehicle.Definition? in var row=row;row["solverSupported"]=true;return .init(row) }
  let catalog=(try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("local-only/selfhost/coupling-catalog.json")))) as! [String:Any]
  let coupling=(catalog["models"] as! [String:[String:Any]]).compactMapValues(NativeGroundVehicle.CouplingDefinition.init)
  var checks=0,frames=0,maximum=0.0
  func check(_ ok:Bool,_ label:String){checks+=1;precondition(ok,label)}
  func v(_ raw:Any)->SIMD3<Float>{let a=raw as! [Double];return SIMD3(Float(a[0]),Float(a[1]),Float(a[2]))}
  func make(_ model:Int,floor:Bool=false)->(SwiftRapierWorld,NativeOtherVehicles){
   let world=SwiftRapierWorld(gravity:SIMD3(0,-18,0))!
   if floor {
    let ground=world.addBox(halfExtents:SIMD3(1000,0.1,1000),position:SIMD3(0,-0.1,0),friction:0.8)!
    world.setColliderGroups(ground,collision:131071,solver:0xffffffff)
    world.setColliderFrictionCombine(ground,.average);world.step()
   }
   let pool=NativeOtherVehicles(world:world);pool.load(definitions);pool.setCouplingDefinitions(coupling);pool.random={0.37}
   let row=NativeOtherVehicles.Pose(id:"fixture",code:String(model),position:SIMD3(0,0,1.1),heading:0,pitch:0,roll:0)
   pool.park(row,physicalPose:.init(position:SIMD3(0,1.1,0),rotation:simd_quatd(ix:0,iy:0,iz:0,r:1)))
   return(world,pool)
  }
  func support(_ world:SwiftRapierWorld,_ pool:NativeOtherVehicles,_ model:Int)->UInt64? {
   let chassis=definitions[String(model)]!.chassis.count
   let ids=pool.colliders.sorted();return ids.count==chassis+1 ? ids.last:nil
  }
  for profile in fixture["profiles"] as! [[String:Any]] {
   let model=profile["id"] as! Int,(world,pool)=make(model),original=pool.bodyID("fixture")!
   let expected=profile["descriptor"] as? [String:Any],leg=support(world,pool,model)
   check((leg != nil)==(expected != nil),"Support eligibility differs for model\(model)")
   if let leg,let expected {
    let info=world.colliderInfo(leg)!
    if case .sphere(let radius)=info.shape {check(abs(radius-Float(expected["radius"] as! Double))<1e-7,"Support sphere radius differs")}else{check(false,"Support is not a sphere")}
    check(simd_distance(info.translation,v(expected["world"]!))<1e-6,"Support world/body coordinates differ")
    // Additional rigid-body mass is deferred until a physics update. Compare
    // recomputed states on both sides, without advancing gravity or the pose.
    world.recomputeMassProperties(original);let withSupport=world.mass(of:original)!
    world.removeCollider(leg);world.recomputeMassProperties(original)
    let withoutSupport=world.mass(of:original)!
    check(withSupport>0 && withoutSupport==withSupport,"Support sphere added mass")
    pool.setCouplingDefinitions(coupling);world.recomputeMassProperties(original)
    check(support(world,pool,model) != nil && world.mass(of:original)==withoutSupport,"Support restoration changed mass")
   }
   world.setVelocities(original,linear:SIMD3(3,1,-2),angular:SIMD3(0.1,0.2,0.3))
   check(pool.haul("fixture"),"Haul failed")
   let held=pool.bodyID("fixture")!,state=world.bodyState(held)!,oracle=profile["haul"] as! [String:Any]
   check((world.bodyState(original) != nil)==(oracle["originalBodyValid"] as! Bool),"Haul retained stale ordinary body")
   check(support(world,pool,model)==nil,"Hauled body retained support")
   check(simd_distance(state.linearVelocity,v(oracle["linear"]!))<1e-7 && simd_distance(state.angularVelocity,v(oracle["angular"]!))<1e-7,"Haul velocity reset differs")
   world.setVelocities(held,linear:SIMD3(2,3,4),angular:SIMD3(0.3,0.2,0.1));pool.unhaul("fixture")
   check(pool.bodyID("fixture")==held,"Unhaul replaced the held body")
   check(world.bodyState(held)!.linearVelocity==SIMD3(2,3,4),"Unhaul erased momentum")
   check((support(world,pool,model) != nil)==(expected != nil),"Unhaul failed to restore support eligibility")
   let all=pool.colliders;pool.remove("fixture")
   check(all.allSatisfy{world.colliderInfo($0)==nil},"Despawn retained body/support colliders")
  }
  for scenario in fixture["trajectories"] as! [[String:Any]] {
   let model=scenario["id"] as! Int,(world,pool)=make(model,floor:true)
   if scenario["removeSupport"] as! Bool,let id=support(world,pool,model){world.removeCollider(id)}
   for (index,frame) in (scenario["frames"] as! [[String:Any]]).enumerated() {
    pool.beforeStep(delta:1/60);world.step();pool.afterStep(delta:1/60)
    let state=pool.bodyState("fixture")!
    for (actual,key) in [(state.position,"position"),(state.linearVelocity,"linear"),(state.angularVelocity,"angular")] {
     let error=Double(simd_distance(actual,v(frame[key]!)));maximum=max(maximum,error)
     check(error<1e-6,"Support physical trajectory differs model\(model)/\(index)/\(key):\(error)")
    }
    let q=frame["rotation"] as! [Double],expected=SIMD4<Float>(Float(q[0]),Float(q[1]),Float(q[2]),Float(q[3]))
    let error=Double(min(simd_length(state.rotation.vector-expected),simd_length(state.rotation.vector+expected)))
    maximum=max(maximum,error);check(error<1e-6,"Support rotation differs model\(model)/\(index):\(error)");frames+=1
   };pool.clear()
  }
  do {
   let world=SwiftRapierWorld(gravity:SIMD3(0,-18,0))!
   let mesh=SwiftRapierWorld.TriangleMesh(vertices:[SIMD3(-100,0,-100),SIMD3(100,0,-100),SIMD3(100,0,100),SIMD3(-100,0,100)],indices:[0,2,1,0,3,2],surfaces:[2,2])
   check(world.addTriangleMesh(mesh) != nil,"Source terrain mesh failed")
   let body=world.addBody(position:SIMD3(0,0.31,0),mass:.init(value:25,turnMass:25),gravityScale:1)!
   let sphere=world.addSphere(radius:0.3,body:body,friction:1)!
   world.setColliderFrictionCombine(sphere,.average);world.setVelocities(body,linear:SIMD3(2,0,0),angular:.zero)
   for (index,frame) in (fixture["friction"] as! [[String:Any]]).enumerated() {
    world.step();let state=world.bodyState(body)!
    for (actual,key) in [(state.position,"position"),(state.linearVelocity,"linear"),(state.angularVelocity,"angular")] {
     let error=Double(simd_distance(actual,v(frame[key]!)));maximum=max(maximum,error)
     check(error<1e-6,"Default-average terrain contact differs at\(index)/\(key):\(error)")
    };frames+=1
   }
  }
  print("PASS vehicle support: \(checks) checks, \(frames) actual archived physical frames, maximum error\(maximum); support eligibility, body replacement, release momentum, cleanup and average terrain contacts")
 }
}
