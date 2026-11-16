let root=URL(fileURLWithPath:CommandLine.arguments[1])
let data=try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/vehicles.physics.json"))
let values=(try JSONSerialization.jsonObject(with:data)as![String:Any])["models"]as![String:[String:Any]]
let catalog=try NativeSAMPVehicleCoordinates(metadata:data)
precondition(catalog.count==212)
var checks=0
func check(_ value:Bool,_ why:String){precondition(value,why);checks+=1}
for id in values.keys.sorted(){
 let model=Int(id)!,origin=(values[id]!["origin"]as!NSNumber).floatValue
 for h:Float in [-3.1,0,1.2,3.1]{for p:Float in [-1.4,0,0.8]{for r:Float in [-1.5,0,2.3]{
  let quaternion=try NativeSAMPVehicleCoordinates.rotation(heading:h,pitch:p,roll:r)
  let expected=NativeGroundVehicle.modelOffset(origin:origin,heading:h,pitch:p,roll:r)
  let offset=try catalog.offset(model:model,rotation:quaternion)
  check(simd_distance(offset,expected)<0.000005,"Full rotated DFF offset agrees with actual native owner")
  let feet=SIMD3<Float>(2293,2451.6,9.84)
  let raw=try catalog.root(feet,model:model,rotation:quaternion)
  check(simd_distance(try catalog.body(raw,model:model,rotation:quaternion),feet)<0.0003,"Root/body inverse at large world coordinates")
  let native=NativeGroundVehicle.rotation(heading:h,pitch:p,roll:r)
  let transform=NativeGroundVehicle.transform(position:SIMD3<Double>(SwiftRapierWorld.gtaToRapier(feet)),rotation:simd_quatd(vector:SIMD4<Double>(native.vector)),origin:Double(origin))
  let point=SIMD3(transform.columns.3.x,transform.columns.3.y,transform.columns.3.z)
  check(simd_distance(raw,point)<0.0003,"Wire model root equals actual full native model transform")
  let scaled=try catalog.offset(model:model,rotation:quaternion*2)
  check(simd_distance(scaled,offset)<0.000005,"Scaled finite quaternions normalize once")
 }}}
}
let base=SIMD3<Float>(2301.6963,2451.5754,9.832725),identity=SIMD4<Float>(1,0,0,0)
let corrected=try catalog.root(base,model:411,rotation:identity)
check(abs(corrected.z-10.620225)<0.00001,"Infernus original model root differs from prepared body origin by0.7875")
check(corrected.x==base.x && corrected.y==base.y,"Upright root conversion preserves horizontal position")
for q in [SIMD4<Float>(repeating:0),SIMD4<Float>(1,.nan,0,0),SIMD4<Float>(1,0,.infinity,0)] {
 do{_=try catalog.root(base,model:411,rotation:q);preconditionFailure("Invalid quaternion accepted")}catch{checks+=1}
}
do{_=try catalog.root(base,model:0,rotation:identity);preconditionFailure("Unknown model substituted")}catch{checks+=1}
var malformed=try JSONSerialization.jsonObject(with:data)as![String:Any]
malformed["models"]=["411":["origin":true]]
do{_=try NativeSAMPVehicleCoordinates(metadata:JSONSerialization.data(withJSONObject:malformed));preconditionFailure("Boolean origin accepted")}catch{checks+=1}
print("PASS \(checks) actual native vehicle model/body coordinate checks across212 models and36 orientations")
