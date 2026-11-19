import Foundation
import simd

@main enum NativeClimbGeometryReplay {
 static func main() throws {
  let path=CommandLine.arguments[1],doc=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:path))) as! [String:Any]
  var checks=0,queries=0,maximum=0.0
  func n(_ p:[String:Any],_ key:String,_ fallback:Double=0)->Double{(p[key] as? NSNumber)?.doubleValue ?? fallback}
  func v(_ p:Any)->SIMD3<Double>{let a=(p as! [NSNumber]).map(\.doubleValue);return SIMD3(a[0],a[1],a[2])}
  func check(_ a:Double,_ b:Double,_ label:String){let error=abs(a-b);maximum=max(maximum,error);precondition(error<0.000001,"\(label) \(a) vs \(b)");checks += 1}
  func checkVector(_ a:SIMD3<Double>,_ b:Any,_ label:String){let expected=v(b);for i in 0..<3{check(a[i],expected[i],label)}}
  // Types are local to one world and appear only after successful creation.
  do {
   let world=SwiftRapierWorld()!
   precondition(world.bodyKind(0)==nil && world.bodyKind(UInt64.max)==nil);checks += 2
   for kind in [SwiftRapierWorld.BodyKind.fixed,.dynamic,.kinematicPosition,.kinematicVelocity] {
    let id=world.addBody(kind:kind,position:.zero)!
    precondition(world.bodyKind(id)==kind);checks += 1
    precondition(world.removeBody(id) && world.bodyKind(id)==nil);checks += 1
    precondition(!world.removeBody(id) && world.bodyKind(id)==nil);checks += 1
   }
   let other=SwiftRapierWorld()!
   precondition(other.bodyKind(1)==nil);checks += 1
  }
  // Unknown bodies are neither static targets nor transparent clearance.
  do {
   let unknown=NativeClimbProbe.Collider(fixed:false,speed:.infinity,material:0,known:false)
   let blockedTarget=NativeClimbProbe(ray:{_,_,_,_ in .init(distance:0.8,normal:SIMD3(0,0,1),collider:unknown)},overlaps:{_,_,_ in []})
   precondition(blockedTarget.find(feet:.zero,heading:0)==nil);checks += 1
   var unknownClearanceCalls=0
   let blockedClearance=NativeClimbProbe(ray:{origin,direction,_,_ in
    if direction.y>0 || origin.y>1.8 {return nil}
    return .init(distance:0.8,normal:SIMD3(0,0,1),collider:.init(fixed:true,speed:0,material:0))
   },overlaps:{_,_,_ in unknownClearanceCalls += 1;return [unknown]})
   precondition(blockedClearance.find(feet:.zero,heading:0)==nil && unknownClearanceCalls>0);checks += 1
  }
  for row in doc["probeCases"] as! [[String:Any]] {
   let world=SwiftRapierWorld()!,scenario=row["scenario"] as! [String:Any];var fixedBodies=Set<UInt64>()
   func box(_ x:Float,_ y:Float,_ z:Float,_ hx:Float,_ hy:Float,_ hz:Float,_ material:Int32=0,_ speed:Float?=nil,_ parent:String?=nil){
    let kind:SwiftRapierWorld.BodyKind=parent=="fixed" ? .fixed:parent=="kinematic" ? .kinematicVelocity:.dynamic
    let body=(speed != nil || parent != nil) ? world.addBody(kind:kind,position:SIMD3(x,y,z)):nil
    if let body,kind == .fixed {fixedBodies.insert(body)}
    if let body,let speed {var state=world.bodyState(body)!;state.linearVelocity=SIMD3(speed,0,0);world.setBodyState(state,for:body)}
    let collider=world.addBox(halfExtents:SIMD3(hx,hy,hz),body:body,position:body == nil ? SIMD3(x,y,z):.zero)!
    world.setColliderGroups(collider,collision:0x0087ffff,solver:0xffffffff)
    world.setColliderQueryMetadata(collider,surface:2,material:material)
   }
   let depth=Float(n(scenario,"depth")),top=Float(n(scenario,"top"))
   if depth>0 {box(0,top/2,-0.8-depth/2,1,top/2,depth/2,Int32(n(scenario,"material")),(scenario["speed"] as? NSNumber)?.floatValue,scenario["parent"] as? String)}
   if scenario["pedFront"] as? Bool == true {box(0,1.6,-0.4,0.15,1.6,0.1,62)}
   if scenario["fastFront"] as? Bool == true {box(0,1.6,-0.4,0.15,1.6,0.1,0,1)}
   if scenario["ceiling"] as? Bool == true {box(0,2.6,0,1,0.1,1)}
   if scenario["bodyBlock"] as? Bool == true {box(0,2.8,-1.02,0.1,0.15,0.1)}
   world.step()
   func classify(_ p:SwiftRapierWorld.ColliderInfo)->NativeClimbProbe.Collider {
    .init(fixed:p.body == nil || fixedBodies.contains(p.body!),speed:p.body.flatMap{world.bodyState($0)}.map{simd_length(SIMD3<Double>($0.linearVelocity))} ?? 0,material:p.material)
   }
   func same(_ a:NativeClimbProbe.Collider,_ b:[String:Any]) {
    precondition(a.fixed==b["fixed"] as! Bool && a.material==b["material"] as! Int);checks += 1;check(a.speed,n(b,"speed"),"body speed")
   }
   for q in row["queries"] as! [[String:Any]] {
    let origin=SIMD3<Float>(v(q["origin"]!)),groups=UInt32(n(q,"groups"))
    if q["type"] as! String=="ray" {
     var ignored=Set<UInt64>(),actual:SwiftRapierWorld.QueryHit?
     while let hit=world.queryRay(origin:origin,direction:SIMD3<Float>(v(q["direction"]!)),distance:Float(n(q,"distance")),groups:groups,excludingColliders:ignored) {
      if hit.collider.material==62 {ignored.insert(hit.collider.id);continue};actual=hit;break
     }
     if let expected=q["hit"] as? [String:Any] {
      precondition(actual != nil,"Missing native ray in \(row["name"]!)");let hit=actual!
      check(Double(hit.distance),n(expected,"distance"),"ray distance");checkVector(SIMD3<Double>(hit.normal),expected["normal"]!,"ray normal")
      same(classify(hit.collider),expected["collider"] as! [String:Any])
     } else {precondition(actual==nil,"Extra native ray in \(row["name"]!)");checks += 1}
    } else {
     let expected=q["colliders"] as! [[String:Any]],actual=world.intersections(center:origin,halfHeight:0,radius:Float(n(q,"radius")),groups:groups).filter{$0.material != 62}.map(classify)
     // Original callback terminates after first stable overlap. Other native
     // hits after that have no semantic effect and do not represent a mismatch.
     let originalBlocked=expected.contains{$0["fixed"] as! Bool || n($0,"speed")<0.5}
     let nativeBlocked=actual.contains{$0.fixed || $0.speed<0.5}
     precondition(originalBlocked==nativeBlocked,"Sphere/capsule0 clearance differs in \(row["name"]!)");checks += 1
    }
    queries += 1
   }
   let adapter=NativeRapierClimbQueries(world:world,excluded:[])
   let actual=adapter.find(feet:v(row["feet"]!),heading:n(row,"heading"),extended:row["extended"] as! Bool)
   if let expected=row["result"] as? [String:Any] {
    precondition(actual != nil);checkVector(actual!.hold,expected["hold"]!,"actual native ledge hold");checkVector(actual!.into,expected["into"]!,"actual native ledge inward")
    check(actual!.heading,n(expected,"heading"),"native heading");precondition(actual!.high==expected["high"] as! Bool && actual!.vault==expected["vault"] as! Bool);checks += 1
    let parent=scenario["parent"] as? String
    let fixed=parent=="fixed" || (parent==nil && scenario["speed"]==nil)
    precondition(actual!.fixed==fixed,"Carrier classification mismatch in \(row["name"]!)");checks += 1
   } else {precondition(actual==nil,"Extra native ledge in \(row["name"]!)");checks += 1}
  }
  let report:[String:Any]=["authority":"Original archived Rapier-WASM vs native engine in controlled synthetic scenes; not retail GTA SA","queryCalls":queries,"checks":checks,"maximumNumericError":maximum,"status":"native-geometry-candidate-pass","sphereBoundary":"Zero-height capsule matched original Ball overlap decisions in these scenes only"]
  try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:URL(fileURLWithPath:path).deletingLastPathComponent().appendingPathComponent("native-report.json"))
  print("PASS native climb geometry:",queries,"queries,",checks,"checks; max error",maximum)
 }
}
