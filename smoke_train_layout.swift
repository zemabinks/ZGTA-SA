import Foundation
import simd
@main enum TrainLayoutSmoke {
 static func main() throws {
  let root=URL(fileURLWithPath:CommandLine.arguments[1]),data=try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/vehicles.physics.json")),tracks=try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/trains.json"))
  let rows=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [[String:Any]],doc=try JSONSerialization.jsonObject(with:data) as! [String:Any]
  let definitions=doc["models"] as! [String:[String:Any]],names=definitions.mapValues{$0["model"] as! String}
  let fleet=NativeGroundVehicle()!;precondition(fleet.loadDefinitions(data)==212);precondition(fleet.loadTracks(tracks))
  var checks=0,largest=0.0
  func check(_ ok:Bool,_ label:String){precondition(ok,label);checks += 1}
  func vector(_ a:Any)->SIMD3<Float>{let v=a as! [NSNumber];return SIMD3(v[0].floatValue,v[1].floatValue,v[2].floatValue)}
  func n(_ d:[String:Any],_ k:String)->Float{(d[k] as! NSNumber).floatValue}
  func matrix(_ actual:simd_float4x4,_ expected:[NSNumber]) {
   for c in 0..<4 {for r in 0..<4 {let error=abs(Double(actual[c][r])-expected[c*4+r].doubleValue);largest=max(largest,error);check(error<0.0003,"Original91584.wY model transform mismatch")}}
  }
  func equal(_ a:[NativeGroundVehicle.Carriage],_ b:[NativeGroundVehicle.Carriage]) {
   check(a.count==b.count,"Carriage count changed across ownership")
   for (x,y) in zip(a,b){check(x.model==y.model && x.transform==y.transform,"Carriage transform changed across ownership")}
  }
  for (index,row) in rows.enumerated() {
   let model=row["model"] as! String,p=vector(row["position"]!),h=n(row,"heading"),pitch=n(row,"pitch"),roll=n(row,"roll")
   let expected=row["expected"] as! [[String:Any]],id="reference-\(index%3)"
   let result=fleet.trainCarriages(id:id,model:model,bodyPosition:p,heading:h,pitch:pitch,roll:roll)
   check(result.count==expected.count,"Original carriage count mismatch")
   for (car,want) in zip(result,expected){check(car.model==want["model"] as! String,"Carriage model mismatch");matrix(car.transform,want["matrix"] as! [NSNumber])}
   let parked=RemoteVehicle(id:id,code:model,position:p,heading:h,pitch:pitch,roll:roll)
   let plan=rendererTrainPlan(fleet,driving:false,currentVehicleID:nil,camera:p,remoteVehicles:[parked],remotePlayers:[],models:names)
   check(plan.matrices.count==expected.count && plan.instances==expected.count+1,"Actual renderer omitted parked locomotive carriages")
   let player=TrainLayoutPlayer(vehicleID:id,code:model,position:p,heading:h,pitch:pitch,roll:roll)
   let remote=rendererTrainPlan(fleet,driving:false,currentVehicleID:nil,camera:p,remoteVehicles:[parked],remotePlayers:[player,player],models:names)
   check(remote.matrices.count==expected.count && remote.instances==expected.count,"Actual renderer duplicated/omitted remote-driven carriages")
   check(plan.matrices==remote.matrices,"Remote-to-parked layout changed")
   let streamed=rendererTrainPlan(fleet,driving:false,currentVehicleID:nil,camera:p+SIMD3(200,0,0),remoteVehicles:[parked],remotePlayers:[],models:names)
   check(streamed.matrices.isEmpty && fleet.trainCarriageLayoutCount==0,"Streamed-out locomotive retained carriage/cache state")
  }
  // Existing owned placement is retained exactly, then reused after exiting.
  let seed=rows.first{$0["model"] as? String=="537"}!,p=vector(seed["position"]!)
  precondition(fleet.enter(model:"537",modelPosition:p,heading:n(seed,"heading")))
  let owned=fleet.carriages;check(owned.count==3,"Owned train lost its existing consist")
  let body=fleet.chassisColliders.first.flatMap{fleet.world.colliderInfo($0)?.body}!,state=fleet.world.bodyState(body)!
  let exact=NativeUnattendedVehicle.Pose(position:SIMD3<Double>(state.position),rotation:NativeUnattendedVehicle.quaternion(state.rotation))
  let copied=fleet.trainCarriages(id:"train",model:"537",bodyPosition:fleet.bodyPosition,heading:fleet.heading,bodyPose:exact)
  equal(owned,copied)
  let ownPlan=rendererTrainPlan(fleet,driving:true,currentVehicleID:"train",camera:fleet.modelPosition,remoteVehicles:[],remotePlayers:[],models:names)
  check(ownPlan.matrices.count==3 && Set(ownPlan.identities.values)==Set((0..<3).map{"carriage:\($0):freiflat"}),"Owned renderer tokens/placement changed")
  fleet.parkCurrentVehicle(id:"train",code:"537",health:1000,damage:"",work:0)
  let parked=fleet.otherVehicle("train")!,raw=RemoteVehicle(id:"train",code:"537",position:parked.position,heading:parked.heading,pitch:parked.pitch,roll:parked.roll)
  let exitPlan=rendererTrainPlan(fleet,driving:false,currentVehicleID:nil,camera:parked.position,remoteVehicles:[raw],remotePlayers:[],models:names)
  check(exitPlan.matrices.count==3 && exitPlan.matrices.values.allSatisfy{value in ownPlan.matrices.values.contains{$0==value}},"Train exit removed/shifted carriage models")
  fleet.clearOtherVehicles();check(fleet.trainCarriageLayoutCount==0,"Session clear retained train layout cache")
  _=rendererTrainPlan(fleet,driving:false,currentVehicleID:nil,camera:p,remoteVehicles:[raw],remotePlayers:[],models:names)
  check(fleet.trainCarriageLayoutCount==1,"Valid parked layout not cached")
  check(!fleet.removeOtherVehicle(id:"train") && fleet.trainCarriageLayoutCount==0,"Explicit disappearance did not evict standalone carriage layout")
  check(fleet.trainCarriages(id:"train",model:"420",bodyPosition:p,heading:0).isEmpty,"Non-train acquired a consist")
  let cold=NativeGroundVehicle()!;precondition(cold.loadDefinitions(data)==212)
  check(cold.trainCarriages(id:"cold",model:"537",bodyPosition:p,heading:0).isEmpty,"Missing tracks fabricated a consist")
  print("PASS train layouts: \(checks) checks across \(rows.count) actual curve/reverse poses; maxmatrixerror \(largest)m; owned/remote/parked/exit/streaming Renderer clauses")
 }
}
