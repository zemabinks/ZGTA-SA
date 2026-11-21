// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
@main enum TrafficRiderFallTests {
 typealias O=NativeTrafficRiderFall
 static var checks=0
 static func check(_ x:Bool,_ m:String)throws{checks+=1;if !x{throw NSError(domain:m,code:1)}}
 static func close(_ x:Double,_ y:Double,_ m:String)throws{try check(x.isFinite && y.isFinite && abs(x-y)<1e-10,m)}
 static func vector(_ x:SIMD3<Double>,_ y:SIMD3<Double>,_ m:String)throws{for i in 0..<3{try close(x[i],y[i],m)}}
 static func vec(_ raw:Any)->SIMD3<Double>{let a=(raw as! [NSNumber]).map(\.doubleValue);return SIMD3(a[0],a[1],a[2])}
 static func matrix(_ raw:Any)->simd_double4x4{let a=(raw as! [NSNumber]).map(\.doubleValue);return .init(columns:(SIMD4(a[0],a[1],a[2],a[3]),SIMD4(a[4],a[5],a[6],a[7]),SIMD4(a[8],a[9],a[10],a[11]),SIMD4(a[12],a[13],a[14],a[15])))}
 static func clip(_ raw:Any?)->O.Clip?{guard let a=raw as? [String:Any]else{return nil};return .init(name:a["name"]as! String,duration:(a["duration"]as! NSNumber).doubleValue,rootAtStart:a["rootStart"]is [NSNumber] ? vec(a["rootStart"]!):.zero)}
 static func main(){do{try run()}catch{print("FAIL \(error)");exit(1)}}
 static func run()throws {
  let hit=O.Clip(name:"test-hit",duration:0.5,rootAtStart:.zero),fall=O.Clip(name:"test-fall",duration:1,rootAtStart:SIMD3(0,0,1))
  let owner=O(seat:.zero,side:-1,turn:0.3,origin:1,lift:0.5,modelMatrix:matrix_identity_double4x4,hit:hit,falls:[fall,nil],stand:nil)!
  let edge=owner.update(delta:2)!
  try check(edge.sample?.clip=="test-hit" && edge.sample?.time==0.5 && edge.phase=="test-fall" && edge.phaseTime==0,"Overshoot carried through more than one clip")
  let start=owner.update(delta:0)!
  try check(start.sample?.clip=="test-fall" && start.sample?.time==0,"Next clip was not sampled on later update")
  let last=owner.update(delta:1)!
  try check(last.state == .down && last.completedClip=="test-fall","Final endpoint did not enter down")
  let held=owner.update(delta:0.3)!
  try check(held.sample?.clip=="test-fall" && held.sample?.time==1,"Down stopped holding the last clip")
  try check(owner.update(delta:.nan)==nil && owner.update(delta:-1)==nil,"Invalid delta advanced fall state")
  var cases=0,steps=0
  if CommandLine.arguments.count==2 {
   let data=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))as! [String:Any]
   for row in data["cases"]as! [[String:Any]] {
    let input=row["authored"]as! [String:Any],seat=input["seat"]as! [String:Any],call=input["call"]as! [String:Any],initial=row["initialExpected"]as! [String:Any]
    // The private reference probe declares this authored standing seam.
    let falls=input["falls"]as! [Any],stand=O.Clip(name:"authored_stand_boundary",duration:1,rootAtStart:.zero)
    let value=O(seat:vec(seat["at"]!),side:(seat["side"]as! NSNumber).intValue,requestedSide:(call["side"]as! NSNumber).intValue,
      turn:(input["initialTurn"]as! NSNumber).doubleValue,origin:(input["origin"]as! NSNumber).doubleValue,lift:(input["lift"]as! NSNumber).doubleValue,
      modelMatrix:matrix(input["initialMatrix"]!),hit:clip(input["hit"]),falls:falls.map{clip($0)},stand:stand)!
    let name=row["name"]as! String
    try check(value.state.rawValue==initial["state"]as! String && value.phase==initial["phase"]as? String && value.remaining==initial["remaining"]as! [String],name+" initial phase admission")
    var captures=UInt64((initial["captures"]as! [Any]).count/2)
    for step in row["steps"]as! [[String:Any]] {
     let e=step["expected"]as! [String:Any],frame=value.update(delta:(step["delta"]as! NSNumber).doubleValue)!
     try check(frame.state.rawValue==e["state"]as! String && frame.phase==e["phase"]as? String && frame.completedClip==e["completedClip"]as? String,name+" phase/down/completed state")
     try close(frame.phaseTime,(e["phaseTime"]as! NSNumber).doubleValue,name+" phase time")
     try vector(frame.anchor,vec(e["anchor"]!),name+" retained anchor")
     try vector(frame.anchor,vec(e["figurePosition"]!),name+" final figure anchor")
     try vector(frame.capturedAnchor,vec(e["capturedAnchor"]!),name+" capture anchor")
     try close(frame.transitionProgress,(e["transitionProgress"]as! NSNumber).doubleValue,name+" continuity clock")
     try close(frame.turn,(e["figureTurn"]as! NSNumber).doubleValue,name+" figure turn")
     let samples=e["samples"]as! [[String:Any]],sample=samples.last
     try check(frame.sample?.clip==sample?["clip"]as? String,name+" final selected sample")
     if let sample{try close(frame.sample!.time,(sample["time"]as! NSNumber).doubleValue,name+" sample time")}
     captures+=UInt64((e["captures"]as! [Any]).count/2);try check(frame.captureSerial==captures,name+" capture phase ownership")
     let expectedMatrix=matrix(e["usedMatrix"]!)
     for c in 0..<4{for r in 0..<4{try close(frame.modelMatrix[c][r],expectedMatrix[c][r],name+" immutable model matrix")}}
     steps+=1
    };cases+=1
   }
  }
  print("PASS traffic rider fall policy: \(checks) checks, \(cases) archived cases, \(steps) steps; clip/anchor/matrix policy only, no bones/rendering, detached lifetime, NPC handoff or retail acceptance")
 }
}
