import Foundation
import simd
let root=URL(fileURLWithPath:CommandLine.arguments[1])
let catalog=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("local-only/selfhost/tread-catalog.json"))) as! [String:Any]
let meshes=catalog["models"] as! [String:[String:Any]]
let reference=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))) as! [String:Any]
var checks=0,rays=0,poses=0,maxRay=0.0,maxVertex=0.0
func check(_ ok:Bool,_ message:String){checks+=1;precondition(ok,message)}
func vector(_ value:Any)->SIMD3<Double>{let v=value as! [Double];return SIMD3(v[0],v[1],v[2])}
func vertices(_ tread:NativeVehicleTread,_ expected:[Double]){
 check(tread.positions.count*3==expected.count,"Support vertex count changed")
 for (index,point) in tread.positions.enumerated(){for axis in 0..<3{
  let error=abs(Double(point[axis])-expected[3*index+axis]);maxVertex=max(maxVertex,error);check(error<1e-6,"Support vertex posing differs at\(index)/\(axis):\(error)")
 }}
}
func query(_ tread:NativeVehicleTread,_ rows:[[String:Any]]){
 for row in rows {
  let q=row["rotation"] as! [Double],rotation=simd_quatd(ix:q[0],iy:q[1],iz:q[2],r:q[3])
  let actual=tread.ray(origin:vector(row["origin"]!),distance:row["distance"] as! Double,bodyPosition:vector(row["position"]!),bodyRotation:rotation)
  if let expected=row["hit"] as? Double {
   check(actual != nil,"Support ray unexpectedly missed")
   let error=abs(actual!-expected);maxRay=max(maxRay,error);check(error<2e-6,"Support ray differs:\(error)")
  }else{check(actual==nil,"Support ray invented a hit")};rays+=1
 }
}
for row in reference["base"] as! [[String:Any]] {
 let id=row["id"] as! Int,mesh=NativeVehicleTread.Definition(meshes[String(id)]!)!,tread=NativeVehicleTread(mesh)
 check(mesh.indices==row["indices"] as! [Int],"Support topology differs")
 vertices(tread,row["positions"] as! [Double]);query(tread,row["rays"] as! [[String:Any]])
}
for row in reference["working"] as! [[String:Any]] {
 let id=row["id"] as! Int,tread=NativeVehicleTread(NativeVehicleTread.Definition(meshes[String(id)]!)!)
 for frame in row["frames"] as! [[String:Any]] {
  let m=frame["matrix"] as! [Double]
  tread.pose(work:frame["work"] as! Double){point,_ in
   SIMD3(m[0]*point.x+m[4]*point.y+m[8]*point.z+m[12],m[1]*point.x+m[5]*point.y+m[9]*point.z+m[13],m[2]*point.x+m[6]*point.y+m[10]*point.z+m[14])
  }
  vertices(tread,frame["positions"] as! [Double]);query(tread,frame["rays"] as! [[String:Any]]);poses+=1
 }
}
print("PASS support query meshes: \(checks) checks, \(rays) actual original rays, \(poses) working poses; max ray\(maxRay), max vertex\(maxVertex)")
