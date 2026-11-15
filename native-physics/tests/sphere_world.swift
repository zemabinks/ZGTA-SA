import Foundation
import simd

// The method body below is inserted verbatim from current NativeGroundVehicle;
// vehicle forces are intentionally absent from this static query acceptance.
final class Cells {
 let world:SwiftRapierWorld
 var cellData:[String:Data]=[:],loadedCells=Set<String>(),cells:[String:[UInt64]]=[:]
 var materialClasses:[Int]
 struct CollisionPart:Equatable {let indexStart:Int;let indexCount:Int}
 var collisionFallbackParts:[String:[CollisionPart]]=[:]
 init(world:SwiftRapierWorld,materialClasses:[Int]){self.world=world;self.materialClasses=materialClasses}
 // ACTUAL_INSTALL_CELL
}

@main enum NativeSphereWorldReplay {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]),directory=URL(fileURLWithPath:CommandLine.arguments[2])
  let doc=try JSONSerialization.jsonObject(with:Data(contentsOf:directory.appendingPathComponent("world-trimesh-reference.json"))) as! [String:Any]
  let metadata=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/vehicles.physics.json"))) as! [String:Any]
  let world=SwiftRapierWorld(gravity:SIMD3(0,-18,0))!;world.enableArchivedStepping()
  let sea=world.addBox(halfExtents:SIMD3(150,1,150),position:SIMD3(0,-71,0))!;world.setColliderGroups(sea,collision:131071,solver:0xffffffff)
  let cells=Cells(world:world,materialClasses:metadata["materialClasses"] as! [Int])
  for cell in doc["cells"] as! [String] {cells.installCell(cell,data:try Data(contentsOf:root.appendingPathComponent("local-only/site/game/world/\(cell).col.bin")))}
  precondition(cells.cells.values.reduce(1){$0+$1.count}==doc["colliderCount"] as! Int,"Actual COL grouping/residency differs")
  world.step()
  let query=NativeRapierClimbQueries(world:world,excluded:[])
  var checks=0,rays=0,spheres=0,maximumDistance=0.0,maximumNormal=0.0,maximumLedge=0.0,accepted=0
  var mismatches:[[String:Any]]=[]
  func n(_ p:[String:Any],_ k:String)->Double{(p[k] as! NSNumber).doubleValue}
  func v(_ p:Any)->SIMD3<Double>{let a=(p as! [NSNumber]).map(\.doubleValue);return SIMD3(a[0],a[1],a[2])}
  func ray(_ q:[String:Any]) {
   var excluded=Set<UInt64>(),actual:SwiftRapierWorld.QueryHit?
   while let hit=world.queryRay(origin:SIMD3<Float>(v(q["origin"]!)),direction:SIMD3<Float>(v(q["direction"]!)),distance:Float(n(q,"distance")),groups:UInt32(n(q,"groups")),excludingColliders:excluded) {
    if hit.collider.material==62 {excluded.insert(hit.collider.id);continue};actual=hit;break
   }
   if let expected=q["hit"] as? [String:Any] {
    if let actual {
     maximumDistance=max(maximumDistance,abs(Double(actual.distance)-n(expected,"distance")))
     maximumNormal=max(maximumNormal,simd_distance(SIMD3<Double>(actual.normal),v(expected["normal"]!)))
     precondition(actual.collider.material==expected["material"] as! Int);checks += 1
    } else {mismatches.append(["type":"missing-ray","origin":q["origin"]!])}
   } else if actual != nil {mismatches.append(["type":"extra-ray","origin":q["origin"]!])}
   rays += 1;checks += 1
  }
  func sphere(_ q:[String:Any],_ context:String) {
   let hits=world.sphereIntersections(center:SIMD3<Float>(v(q["origin"]!)),radius:Float(n(q,"radius")),groups:UInt32(n(q,"groups"))).filter{$0.material != 62}
   let blocked=hits.contains{collider in
    guard let body=collider.body else{return true}
    guard let kind=world.bodyKind(body),let state=world.bodyState(body) else{return true}
    return kind == .fixed || simd_length(SIMD3<Double>(state.linearVelocity))<0.5
   }
   if blocked != q["blocked"] as! Bool {mismatches.append(["type":"sphere-clearance","context":context,"origin":q["origin"]!,"native":blocked,"original":q["blocked"]!])}
   spheres += 1;checks += 1
  }
  for row in doc["cases"] as! [[String:Any]] {
   for q in row["queries"] as! [[String:Any]] {if q["type"] as! String=="ray"{ray(q)}else{sphere(q,row["kind"] as! String)}}
   let actual=query.find(feet:v(row["feet"]!),heading:n(row,"heading"),extended:true)
   if let expected=row["result"] as? [String:Any] {
    if let actual {
     maximumLedge=max(maximumLedge,simd_distance(actual.hold,v(expected["hold"]!)),simd_distance(actual.into,v(expected["into"]!)),abs(NativeHeadingContinuity.difference(actual.heading,from:n(expected,"heading"))))
     if actual.high != expected["high"] as! Bool || actual.vault != expected["vault"] as! Bool {mismatches.append(["type":"state","kind":row["kind"]!])}
     accepted += 1
    } else {mismatches.append(["type":"missing-ledge","kind":row["kind"]!,"feet":row["feet"]!])}
   } else if actual != nil {mismatches.append(["type":"extra-ledge","kind":row["kind"]!,"feet":row["feet"]!])}
   checks += 1
  }
  for q in doc["grazing"] as! [[String:Any]] {sphere(q,"grazing\(q["delta"]!)")}
  let report:[String:Any]=["authority":"Actual archived COL grouping+WASM Ball/probe vs native literal-Ball query with current installCell over supplied SCL2 reference geometry; not retail GTA evidence",
   "cells":cells.loadedCells.sorted(),"colliders":cells.cells.values.reduce(1){$0+$1.count},"rays":rays,"sphereQueries":spheres,"checks":checks,"acceptedLedges":accepted,
   "maximumDistanceError":maximumDistance,"maximumNormalError":maximumNormal,"maximumLedgeError":maximumLedge,"mismatches":mismatches,
   "limits":["Original QA aliases keep complete cells resident; not a streaming-scheduler test","No live Metal/hand-placement evidence"]]
  try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:directory.appendingPathComponent("world-trimesh-report.json"))
  print("Real-world trimesh replay:",checks,"checks",rays,"rays",spheres,"sphere queries",accepted,"ledges; errors",maximumDistance,maximumNormal,maximumLedge,"mismatches",mismatches)
  precondition(mismatches.isEmpty && maximumDistance<0.000001 && maximumNormal<0.000001 && maximumLedge<0.000001,"Actual-world geometry parity gate failed; inspect ignored report")
 }
}
