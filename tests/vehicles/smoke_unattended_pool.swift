import Foundation
import simd
import Darwin
@main enum UnattendedPoolSmoke {
 static func main() throws {
  let base=URL(fileURLWithPath:CommandLine.arguments[1])
  let doc=try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent("local-only/physics-fixtures/unattended-vehicles.json"))) as! [String:Any]
  let models=(try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent("local-only/site/game/native/vehicles.physics.json"))) as! [String:Any])["models"] as! [String:[String:Any]]
  func n(_ d:[String:Any],_ k:String)->Double{(d[k] as? NSNumber)?.doubleValue ?? 0}
  func v(_ raw:Any)->SIMD3<Double>{let a=raw as! [Double];return SIMD3(a[0],a[1],a[2])}
  var results:[[String:Any]]=[]
  for scenario in doc["cases"] as! [[String:Any]] where scenario["pool"] as? Bool == true {
   let definition=NativeGroundVehicle.Definition(models[String(Int(n(scenario,"model")))]!)!,world=SwiftRapierWorld(gravity:SIMD3(0,-18,0))!
   let roll=n(scenario,"floorRoll"),rotation=simd_quatf(ix:0,iy:0,iz:Float(sin(roll/2)),r:Float(cos(roll/2)))
   let floor=world.addBox(halfExtents:SIMD3(1000,0.1,1000),position:SIMD3(0,-0.1,0),rotation:rotation,friction:0.8)!
   world.setColliderGroups(floor,collision:131071,solver:0xffffffff);world.step()
   let pool=NativeOtherVehicles(world:world),model=String(Int(n(scenario,"model")))
   pool.load([model:definition]);pool.random={0.37}
   var packets:[[String:Any]]=[];pool.onMove={id,state in packets.append(["id":id,"state":state])}
   let source=NativeOtherVehicles.Pose(id:"test",code:model,position:SIMD3(0,0,Float(n(scenario,"height"))),heading:0,pitch:0,roll:0)
   var firstError=true
   var pe=0.0,ve=0.0,qe=0.0,health=0,damage=0,states=0,packetErrors=0,colliderErrors=0
   let frames=scenario["frames"] as! [[String:Any]]
   for (index,frame) in frames.enumerated() {
    let near=(frame["near"] as? [Double]).map{SwiftRapierWorld.rapierToGTA(SIMD3<Float>(v($0)))}
    pool.synchronize([source],excluding:nil,near:SIMD3(0,0,0),promoteNear:near,delta:1/60,now:Double(index)*1000/60)
    if let press=frame["press"] as? [String:Any],let body=pool.bodyID("test") {let d=press["direction"] as! [Double];pool.shove(body:body,direction:SIMD2(d[0],d[1]),point:v(press["point"]!),speed:n(press,"speed"))}
    pool.beforeStep(delta:1/60);world.step();pool.afterStep(delta:1/60)
    let actual=pool.bodyState("test")!,snapshot=pool.snapshot("test")!,target=frame["rotation"] as! [Double],q=SIMD4<Double>(actual.rotation.vector),eq=SIMD4(target[0],target[1],target[2],target[3])
    pe=max(pe,simd_distance(SIMD3<Double>(actual.position),v(frame["position"]!)));ve=max(ve,simd_distance(SIMD3<Double>(actual.linearVelocity),v(frame["linearVelocity"]!)));qe=max(qe,min(simd_length(q-eq),simd_length(q+eq)))
    if firstError && simd_distance(SIMD3<Double>(actual.position),v(frame["position"]!))>1e-10 {
     print("FIRST",scenario["name"]!,index,"native",actual,"expected",frame);firstError=false;fflush(stdout)
    }
    health=max(health,abs(snapshot.health-Int(n(frame,"health"))));if snapshot.damage != frame["damage"] as! String{damage += 1}
    if snapshot.dynamic != frame["dynamic"] as! Bool{states += 1}
    let expected=frame["packets"] as! [[String:Any]]
    if packets.count != expected.count{packetErrors += 1}
    for (a,b) in zip(packets,expected) {let aa=a["state"] as! [String:Any],bb=b["state"] as! [String:Any];if !(aa as NSDictionary).isEqual(to:bb){packetErrors += 1;if packetErrors<3{print("packet",index,aa,bb)}}}
    packets=[]
    if pool.colliders.count != definition.chassis.count{colliderErrors += 1}
   }
   let name=scenario["name"] as! String
   print(name,"position",pe,"velocity",ve,"quaternion",qe,"health",health,"damage",damage,"state",states,"packets",packetErrors)
   fflush(stdout)
   results.append(["case":name,"frames":frames.count,"maxPositionError":pe,"maxVelocityError":ve,"maxQuaternionError":qe,"maxHealthError":health,"damageMismatches":damage,"dynamicMismatches":states,"packetMismatches":packetErrors,"colliderCountMismatches":colliderErrors]);pool.clear()
  }
  try JSONSerialization.data(withJSONObject:results,options:[.prettyPrinted,.sortedKeys]).write(to:base.appendingPathComponent("local-only/native-physics/tests/unattended-pool.json"))
  precondition(!results.contains{($0["maxPositionError"] as! Double)>1e-9 || ($0["maxVelocityError"] as! Double)>1e-9 || ($0["damageMismatches"] as! Int)>0 || ($0["dynamicMismatches"] as! Int)>0 || ($0["packetMismatches"] as! Int)>0 || ($0["colliderCountMismatches"] as! Int)>0})
  print("PASS original19737 unattended lifecycle")
 }
}
