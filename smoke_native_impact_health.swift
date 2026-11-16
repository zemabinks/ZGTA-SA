import Foundation
import CoreFoundation
// ACTUAL_PREDICTION
let doc=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
var checks=0,frames=0
for scenario in doc["cases"] as! [[String:Any]]{for acknowledge in [true,false]{
 var prediction=NativeHealthPrediction();prediction.begin(connection:"crash",health:scenario["health"] as! Int,armour:scenario["armour"] as! Int,revision:0,processed:0)
 var revision=0
 for row in scenario["rows"] as! [[String:Any]]{
  let damage=row["damage"] as! Int
  let event=row["kind"] as! String=="impact" ? prediction.impact(damage):prediction.hurt(to:max(0,prediction.health-damage))
  precondition(prediction.health==row["health"] as! Int && prediction.armour==row["armour"] as! Int,"Actual archived crash/fall health ownership")
  checks+=2;frames+=1
  if acknowledge,let event{revision+=1;precondition(prediction.apply(health:row["health"] as! Int,armour:row["armour"] as! Int,connection:"crash",processed:event.sequence,revision:revision));checks+=1}
 }
 prediction.disconnect();precondition(!prediction.active);checks+=1
}}
print("PASS original crash/fall armour ordering: \(checks) checks, \(frames) actual archived damage frames")
