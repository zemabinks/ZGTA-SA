import Foundation
import simd
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let doc=try JSONSerialization.jsonObject(with:Data(contentsOf:root)) as! [String:Any]
var checks=0,frames=0,maxError=0.0
func check(_ ok:Bool,_ text:String){checks+=1;if !ok{FileHandle.standardError.write(Data("FAIL bike ejection: \(text)\n".utf8));exit(1)}}
func vector(_ raw:Any)->SIMD3<Double>{let v=raw as! [Double];return SIMD3(v[0],v[1],v[2])}
for row in doc["impacts"] as! [[String:Any]]{
 let model=row["model"] as! Int,mass=row["mass"] as! Double,intensity=row["intensity"] as! Double
 let way=vector(row["way"]!),forward=vector(row["forward"]!),right=vector(row["right"]!),up=vector(row["up"]!),expected=row["expected"] as! Double
 let value=NativeBikeEjection.force(intensity:intensity,mass:mass,model:model,way:way,forward:forward,right:right,up:up)
 let error=abs(value-expected);maxError=max(maxError,error);check(error<1e-9,"Original weighted impact \(model): \(value) / \(expected)")
 let coordinator=NativeBikeEjection(model:model,mass:mass)
 let body=NativeVehicleDamage.Body(position:.zero,right:right,forward:forward,up:up,move:.zero,turn:.zero)
 coordinator.impact(intensity:intensity,way:way,body:body,previousVelocity:SIMD3(1,2,3),occupied:true)
 let event=coordinator.take();check((event != nil)==(expected>0),"Impact threshold")
 if let event{check(event.force==value && event.velocity==SIMD3(1,2,3),"Ejection lost preceding velocity")}
 check(coordinator.take()==nil,"Event was consumed twice")
 coordinator.impact(intensity:intensity,way:way,body:body,previousVelocity:.zero,occupied:false)
 check(coordinator.take()==nil,"Unoccupied bike ejected a local rider")
}
for scenario in doc["cases"] as! [[String:Any]]{
 let model=NativeBikeEjection(model:521,mass:500)
 for row in scenario["rows"] as! [[String:Any]]{
  model.step(delta:row["delta"] as! Double,up:SIMD3(0,row["up"] as! Double,0),velocity:SIMD3(row["speed"] as! Double,0,0),contact:row["contact"] as! Bool,occupied:true)
  let result=model.take(),expected=row["expected"] as? [String:Any]
  check((result != nil)==(expected != nil),"Original rollover gate \(scenario["mode"]!) at \(scenario["hz"]!)Hz frame\(frames)")
  if let result,let expected{check(result.force==expected["force"] as! Double && result.velocity==vector(expected["velocity"]!),"Rollover velocity")}
  frames+=1
 }
 model.reset();check(model.take()==nil,"Reset retained an old crash")
}
let queued=NativeBikeEjection(model:521,mass:100)
let body=NativeVehicleDamage.Body(position:.zero,right:SIMD3(1,0,0),forward:SIMD3(0,0,-1),up:SIMD3(0,1,0),move:.zero,turn:.zero)
queued.impact(intensity:1000,way:SIMD3(0,0,-1),body:body,previousVelocity:SIMD3(1,0,0),occupied:true)
queued.impact(intensity:500,way:SIMD3(0,0,-1),body:body,previousVelocity:SIMD3(2,0,0),occupied:true)
check(queued.take()!.velocity==SIMD3(1,0,0),"A weaker impact replaced the queued ejection")
print("PASS actual bike ejection rules: \(checks) checks, \(frames) rollover frames; max force error \(maxError)")
