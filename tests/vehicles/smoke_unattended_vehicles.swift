import Foundation
import simd
@main enum UnattendedSmoke {
 static func main() throws {
  let base=URL(fileURLWithPath:CommandLine.arguments[1]),doc=try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent("local-only/physics-fixtures/unattended-vehicles.json"))) as! [String:Any]
  let models=(try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent("local-only/site/game/native/vehicles.physics.json"))) as! [String:Any])["models"] as! [String:[String:Any]]
  func number(_ d:[String:Any],_ k:String)->Double{(d[k] as? NSNumber)?.doubleValue ?? 0}
  func v(_ raw:Any)->SIMD3<Double>{let a=raw as! [Double];return SIMD3(a[0],a[1],a[2])}
  func q(_ raw:Any)->simd_quatd{let a=raw as! [Double];return .init(ix:a[0],iy:a[1],iz:a[2],r:a[3])}
  var report:[[String:Any]]=[]
  for scenario in doc["cases"] as! [[String:Any]] where scenario["farAfter"] == nil && scenario["deferPromotion"] == nil {
   let definition=NativeGroundVehicle.Definition(models[String(Int(number(scenario,"model")))]!)!,world=SwiftRapierWorld(gravity:SIMD3(0,-18,0))!
   let roll=number(scenario,"floorRoll"),floorRotation=simd_quatf(vector:SIMD4(0,0,Float(sin(roll/2)),Float(cos(roll/2))))
   let ground=world.addBox(halfExtents:SIMD3(1000,0.1,1000),position:SIMD3(0,-0.1,0),rotation:floorRotation,friction:0.8)!
   world.setColliderGroups(ground,collision:131071,solver:0xffffffff);world.step()
   let initial=scenario["initial"] as! [String:Any]
   let controller=NativeUnattendedVehicle(world:world,definition:definition,pose:.init(position:v(initial["position"]!),rotation:q(initial["rotation"]!)),linear:v(initial["linearVelocity"]!),health:1000,damage:"")!
   controller.random={0.37};var health=1000.0,pe=0.0,ve=0.0,qe=0.0,he=0.0,se=0.0,mismatches=0
   for frame in scenario["frames"] as! [[String:Any]] {
    let previous=controller.state!,reference=NativeUnattendedVehicle.Pose(position:SIMD3<Double>(previous.position),rotation:NativeUnattendedVehicle.quaternion(previous.rotation))
    controller.beforeStep(delta:1/60)
    if let press=frame["press"] as? [String:Any] {let d=press["direction"] as! [Double];controller.shove(direction:SIMD2(d[0],d[1]),point:v(press["point"]!),speed:number(press,"speed"))}
    world.step();controller.afterStep(delta:1/60,reference:reference)
    health=max(1,min(health,floor(controller.damage.health+0.5)))
    let actual=controller.state!,target=q(frame["rotation"]!),aq=NativeUnattendedVehicle.quaternion(actual.rotation).vector
    pe=max(pe,simd_distance(SIMD3<Double>(actual.position),v(frame["position"]!)));ve=max(ve,simd_distance(SIMD3<Double>(actual.linearVelocity),v(frame["linearVelocity"]!)))
    qe=max(qe,min(simd_length(aq-target.vector),simd_length(aq+target.vector)));he=max(he,abs(health-number(frame,"health")))
    se=max(se,abs(controller.frontSpin-number(frame,"frontSpin")),abs(controller.rearSpin-number(frame,"rearSpin")))
    if controller.damage.text() != frame["damage"] as! String {mismatches += 1}
   }
   let name=scenario["name"] as! String;print(name,"position",pe,"velocity",ve,"rotation",qe,"health",he,"spin",se,"damage",mismatches)
   report.append(["case":name,"maxPositionError":pe,"maxVelocityError":ve,"maxQuaternionError":qe,"maxHealthError":he,"maxSpinError":se,"damageMismatches":mismatches]);controller.dispose()
  }
  try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:base.appendingPathComponent("local-only/native-physics/tests/unattended-controllers.json"))
  precondition(!report.contains{($0["maxPositionError"] as! Double)>1e-9 || ($0["maxVelocityError"] as! Double)>1e-9 || ($0["maxHealthError"] as! Double)>0 || ($0["damageMismatches"] as! Int)>0})
  print("PASS original19737 unattended controllers")
 }
}
