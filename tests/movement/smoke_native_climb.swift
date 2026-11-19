import Foundation
import simd

@main enum ClimbReplay {
 static func main() throws {
  let path=CommandLine.arguments[1]
  let doc=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:path))) as! [String:Any]
  let d=doc["durations"] as! [String:NSNumber]
  let durations=NativeClimbController.Durations(jump:d["jump"]!.doubleValue,pull:d["pull"]!.doubleValue,stand:d["stand"]!.doubleValue,vault:d["vault"]!.doubleValue)
  var maximum=0.0,checks=0,frames=0,queryCount=0
  func number(_ row:[String:Any],_ key:String)->Double {(row[key] as! NSNumber).doubleValue}
  func vector(_ value:Any)->SIMD3<Double> {let a=(value as! [NSNumber]).map(\.doubleValue);return SIMD3(a[0],a[1],a[2])}
  func check(_ actual:Double,_ expected:Double,_ label:String) {
   let error=abs(actual-expected);maximum=max(maximum,error);precondition(error<1e-10,"\(label): \(actual) vs \(expected)");checks += 1
  }
  func checkVector(_ actual:SIMD3<Double>,_ expected:Any,_ label:String){let v=vector(expected);for i in 0..<3{check(actual[i],v[i],label)}}
  func ledge(_ p:[String:Any])->NativeClimbController.Ledge {
   .init(hold:vector(p["hold"]!),into:vector(p["into"]!),heading:number(p,"heading"),high:p["high"] as! Bool,vault:p["vault"] as! Bool)
  }
  for row in doc["cases"] as! [[String:Any]] {
   let controller=NativeClimbController(ledge:ledge(row["ledge"] as! [String:Any]),feet:vector(row["initial"]!),durations:durations)
   for frame in row["frames"] as! [[String:Any]] {
    let result=controller.step(delta:number(frame,"delta"),pull:frame["pull"] as! Bool,drop:frame["drop"] as! Bool)
    checkVector(controller.feet,frame["feet"]!,"\(row["name"]!) feet frame\(frames)")
    precondition(controller.part.rawValue==(frame["part"] as! Int));checks += 1
    precondition(result?.rawValue==frame["result"] as? String);checks += 1;frames += 1
   }
  }
  for row in doc["probeCases"] as! [[String:Any]] {
   let queries=row["queries"] as! [[String:Any]];var next=0
   func consume(_ type:String,_ origin:SIMD3<Double>,_ groups:UInt32)->[String:Any] {
    precondition(next<queries.count,"Extra \(type) query in \(row["name"]!)")
    let query=queries[next];next += 1
    precondition(query["type"] as! String==type);precondition(UInt32(number(query,"groups"))==groups)
    checkVector(origin,query["origin"]!,"\(row["name"]!) query\(next) origin");checks += 2
    return query
   }
   func collider(_ p:[String:Any])->NativeClimbProbe.Collider {.init(fixed:p["fixed"] as! Bool,speed:number(p,"speed"),material:p["material"] as! Int)}
   let probe=NativeClimbProbe(ray:{origin,direction,distance,groups in
    let query=consume("ray",origin,groups)
    checkVector(direction,query["direction"]!,"ray direction");check(distance,number(query,"distance"),"ray distance")
    guard let hit=query["hit"] as? [String:Any] else{return nil}
    return .init(distance:number(hit,"distance"),normal:vector(hit["normal"]!),collider:collider(hit["collider"] as! [String:Any]))
   },overlaps:{origin,radius,groups in
    let query=consume("sphere",origin,groups);check(radius,number(query,"radius"),"sphere radius")
    return (query["colliders"] as! [[String:Any]]).map(collider)
   })
   let result=probe.find(feet:vector(row["feet"]!),heading:number(row,"heading"),extended:row["extended"] as! Bool)
   precondition(next==queries.count,"Missing queries \(row["name"]!)")
   if let expected=row["result"] as? [String:Any] {
    precondition(result != nil);checkVector(result!.hold,expected["hold"]!,"ledge hold");checkVector(result!.into,expected["into"]!,"ledge inward")
    check(result!.heading,number(expected,"heading"),"ledge heading")
    precondition(result!.high==expected["high"] as! Bool && result!.vault==expected["vault"] as! Bool);checks += 1
   } else {precondition(result==nil,"Unexpected ledge \(row["name"]!)");checks += 1}
   queryCount += next
  }
  let report:[String:Any]=["authority":"Archived browser secondary reference; not a retail GTA SA replay","frames":frames,"queryCalls":queryCount,"checks":checks,"maximumDoubleError":maximum,"status":"candidate-isolated-pass","limitations":["No App integration or Simulator build","Replay consumes original engine query hits; it tests exact query construction/order, not the native query adapter","No retail executable/capture supplied","Moving ledge attachment and rooted skeletal action integration untested"]]
  let destination=URL(fileURLWithPath:path).deletingLastPathComponent().appendingPathComponent("report.json")
  try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:destination)
  print("PASS isolated climb candidate:",frames,"controller frames,",queryCount,"actual-engine query calls,",checks,"checks; max error",maximum)
 }
}
