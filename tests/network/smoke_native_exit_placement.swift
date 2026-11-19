import Foundation
import simd
struct Case:Decodable {let model:String,poseIndex:Int,mode:String,position:[Double],rotation:[Double],seat:[Double]?,side:Int,wanted:[Double]?,aboard:Bool,expected:[Double],calls:[Int]}
struct Fixture:Decodable {let cases:[Case]}
func vector(_ a:[Double])->SIMD3<Double>{SIMD3(a[0],a[1],a[2])}
let root=URL(fileURLWithPath:CommandLine.arguments[1]),fixture=try JSONDecoder().decode(Fixture.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])))
let catalog=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/vehicles.physics.json"))) as! [String:Any]
let rows=catalog["models"] as! [String:[String:Any]]
let geometries=rows.compactMapValues(NativeVehicleExitPlanner.Geometry.init)
precondition(geometries.count==212,"Missing exit geometry")
var checks=0,maximum=0.0
for c in fixture.cases {
 let q=c.rotation,position=vector(c.position);var calls=[0,0,0]
 let feet=try NativeVehicleExitPlanner.place(geometry:geometries[c.model]!,pose:.init(position:position,rotation:simd_quatd(ix:q[0],iy:q[1],iz:q[2],r:q[3])),seat:c.seat.map(vector),side:c.side,wanted:c.wanted.map(vector),aboard:c.aboard,
  below:{p,d in calls[0]+=1;if c.mode=="void"{return nil};let floor=c.mode=="slope" ? 0.08*(p.x-10.25)-0.04*(p.z+20.5):0,t=p.y-floor;return t>=0 && t<=d ? t:nil},
  along:{p,way,d in calls[1]+=1;return c.mode=="leftWall" && way.x < -0.05 ? 0.1:nil},
  fits:{p,w in calls[2]+=1;switch c.mode {case "leftWall":return p.x>10.6;case "farOnly":return hypot(p.x-position.x,p.z-position.z)>3.2;case "narrow":return w==0;case "roofOnly":return p.y>position.y+3;case "blocked":return false;default:return true}})
 let distance=simd_distance(feet,vector(c.expected));maximum=max(maximum,distance);checks+=2
 guard distance<1e-8,calls==c.calls else {
  print("FAIL exit placement",c.model,c.poseIndex,c.mode,"distance",distance,"feet",feet,"expected",c.expected,"queries",calls,c.calls);exit(1)
 }
}
enum MissingGeometry:Error {case cell}
for query in 0..<3 {
 do {
  _ = try NativeVehicleExitPlanner.place(geometry:geometries["420"]!,pose:.init(position:SIMD3(0,2,0),rotation:simd_quatd(angle:0,axis:SIMD3(0,1,0))),seat:nil,side:-1,wanted:nil,
    below:{_,_ in if query==0{throw MissingGeometry.cell};return 1},along:{_,_,_ in if query==1{throw MissingGeometry.cell};return nil},fits:{_,_ in if query==2{throw MissingGeometry.cell};return true})
  print("FAIL unknown geometry was converted to clear space",query);exit(1)
 }catch MissingGeometry.cell{checks+=1}
}
print("PASS actual archived exit planner: \(fixture.cases.count) cases, \(checks) checks; max error \(maximum); all212 geometry rows; missing-query propagation")
