import Foundation
import simd
func vector(_ raw:Any)->SIMD3<Float>{let a=raw as! [Double];return SIMD3(Float(a[0]),Float(a[1]),Float(a[2]))}
let root=CommandLine.arguments[1]
let data=try Data(contentsOf:URL(fileURLWithPath:root+"/local-only/site/game/native/vehicles.physics.json"))
let document=try JSONSerialization.jsonObject(with:data) as! [String:Any]
let definitions=(document["models"] as! [String:[String:Any]]).compactMapValues{row->NativeGroundVehicle.Definition? in var value=row;value["solverSupported"]=true;return .init(value)}
let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:root+"/local-only/physics-fixtures/other-vehicles.json"))) as! [String:Any]
var rays=0,hits=0,maxDistance:Float=0,maxNormal:Float=0
for item in fixture["cases"] as! [[String:Any]]{
 let world=SwiftRapierWorld(gravity:.zero)!,pool=NativeOtherVehicles(world:world),model=String(item["model"] as! Int)
 pool.load(definitions)
 let pose=NativeOtherVehicles.Pose(id:"peer-car",code:model+".6.1.0.",position:.zero,heading:Float(item["heading"] as! Double),pitch:Float(item["pitch"] as! Double),roll:Float(item["roll"] as! Double))
 pool.synchronize([pose],excluding:nil,near:.zero);world.step()
 precondition(pool.colliders.count==item["count"] as! Int)
 precondition(pool.rhinos.isEmpty == (model != "432"))
 for ray in item["rays"] as! [[String:Any]]{
  let hit=world.raycast(origin:vector(ray["origin"]!),direction:vector(ray["direction"]!),distance:Float(ray["distance"] as! Double));rays += 1
  if let expected=ray["expected"] as? [String:Any]{
   guard let hit else{fatalError("Missing \(model) chassis contact")};hits += 1
   maxDistance=max(maxDistance,abs(hit.distance-Float(expected["distance"] as! Double)));maxNormal=max(maxNormal,simd_distance(hit.normal,vector(expected["normal"]!)))
   precondition(hit.material==63 && world.colliderInfo(hit.collider)!.piece==expected["piece"] as! Int)
  }else{precondition(hit==nil,"Unexpected \(model) chassis contact")}
 }
 pool.synchronize([pose],excluding:"peer-car",near:.zero);world.step();precondition(pool.colliders.isEmpty && pool.rhinos.isEmpty)
 pool.synchronize([pose],excluding:nil,near:.zero);world.step();precondition(!pool.colliders.isEmpty)
 pool.synchronize([pose],excluding:nil,near:SIMD3(200,0,0));world.step();precondition(pool.colliders.isEmpty)
}
precondition(maxDistance<0.0001 && maxNormal<0.0001,"Remote chassis rays diverged: \(maxDistance), \(maxNormal)")
// Live boundary: the motor receives actual parked-car IDs and stands on its
// original chassis roof, rather than walking through a rendered-only model.
let world=SwiftRapierWorld(gravity:SIMD3(0,-18,0))!,pool=NativeOtherVehicles(world:world)
world.addBox(halfExtents:SIMD3(30,0.1,30),position:SIMD3(0,-0.1,0));pool.load(definitions)
pool.synchronize([.init(id:"taxi",code:"420",position:.zero,heading:0,pitch:0,roll:0)],excluding:nil,near:.zero);world.step()
let character=NativeCharacterController(world:world)!;character.otherColliders=pool.colliders;character.reset(feet:SIMD3(0,0,4))
for _ in 0..<180{character.update(delta:1/60,displacement:.zero,geometryReady:true)}
precondition(character.state.grounded && character.state.feet.z>1,"Character fell through original parked car chassis")
pool.clear();for _ in 0..<180{character.update(delta:1/60,displacement:.zero,geometryReady:true)}
precondition(character.state.grounded && character.state.feet.z<0.2,"Removed car left invisible collision")
print("PASS remote/parked native chassis: \(rays) actual source rays / \(hits) hits, max distance \(maxDistance), normals \(maxNormal); own exclusion, culling, Rhino tags and character roof/removal")
