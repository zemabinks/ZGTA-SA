// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
private enum Failed:Error{case check(String)}
private var checks=0
private func check(_ value:Bool,_ reason:String)throws{checks+=1;if !value{throw Failed.check(reason)}}
@main private enum Probe {
 static func main()throws {
  for indices in stride(from:3,through:96,by:3) {
   for split in stride(from:0,through:indices,by:3) {
    let plan=try NativeWorldDrawPlan(indexCount:indices,solidCount:split)
    let solid=Array(plan.solid.start..<(plan.solid.start+plan.solid.count))
    let clear=Array(plan.clear.start..<(plan.clear.start+plan.clear.count))
    try check(solid+clear==Array(0..<indices),"Every source index belongs to exactly one ordered phase")
    try check(Set(solid).isDisjoint(with:clear),"Solid/clear phases never overlap")
   }
  }
  for pair in [(0,0),(-3,0),(4,0),(3,1),(3,4),(3,-3),(3_000_000,0),(Int.max,0),(3,Int.max)] {
   var rejected=false;do{_ = try NativeWorldDrawPlan(indexCount:pair.0,solidCount:pair.1)}catch{rejected=true}
   try check(rejected,"Invalid or overflowing draw range rejected")
  }
  try check(NativeWorldDrawPlan(indexCount:9,triangles:3,blend:6)?.clear == .init(start:6,count:3),"Validated metadata maps the actual indexed suffix")
  for values:(Int?,Int?) in [(nil,nil),(3,nil),(nil,6),(2,6),(Int.max,6),(3,Int.max),(3,-1)] {
   try check(NativeWorldDrawPlan(indexCount:9,triangles:values.0,blend:values.1)==nil,"Incomplete or mismatched index metadata cannot drive a GPU range")
  }
  let declared:[String:Any]=["detail":["cell":128,"columns":16,"sharp":256,"sharpColumns":8,"cells":[["cell":59,"layers":342,"sharp":186,"triangles":76440,"blend":211824]]]]
  let manifest=try NativeWorldSharpManifest(data:JSONSerialization.data(withJSONObject:declared))
  let entry=manifest.entries["c59"]!
  try check(entry.triangles==76440 && entry.blend==211824,"Explicit indexed material boundary retained alongside HD identity")
  for row:[String:Any] in [["triangles":3],["blend":6],["triangles":3,"blend":10],["triangles":3,"blend":4],["triangles":true,"blend":3],["triangles":Int.max,"blend":0]] {
   var invalid=declared,detail=invalid["detail"] as![String:Any]
   var cell:[String:Any]=["cell":59,"layers":342,"sharp":186];row.forEach{cell[$0.key]=$0.value};detail["cells"]=[cell];invalid["detail"]=detail
   var rejected=false;do{_ = try NativeWorldSharpManifest(data:JSONSerialization.data(withJSONObject:invalid))}catch{rejected=true}
   try check(rejected,"Malformed partial material metadata rejected")
  }
  print("PASS \(checks) authored indexed-world partition/identity/admission checks; GPU and scene order remain separate")
 }
}
