import Foundation
import simd
final class WaterExitHarness {
 struct Configuration{let origin:Double}
 struct Definition{let configuration:Configuration}
 struct Body{let position:SIMD3<Float>}
 struct World{var value:Body;func bodyState(_ id:UInt64)->Body?{value}}
 struct Floatation{let lost:Bool}
 struct Dynamics{let buoyancy:Floatation?}
 var rigid:UInt64?=1,model="",definitions:[String:Definition]=[:],dynamics:Dynamics?
 var world=World(value:Body(position:.zero)),waterLevel:((SIMD3<Double>)->Double?)?
 // ACTUAL_WATER_GETTER
}
let fixture=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))) as! [String:Any]
var checks=0
for row in fixture["rows"] as! [[String:Any]]{
 let app=WaterExitHarness(),mode=row["mode"] as! String,origin=row["origin"] as! Double
 app.model=row["id"] as! String;app.definitions[app.model] = .init(configuration:.init(origin:origin))
 app.world.value = .init(position:SIMD3(1,Float(row["y"] as! Double),2))
 app.waterLevel={_ in row["level"] as? Double}
 if mode=="none"{app.rigid=nil}
 if mode=="buoyant" || mode=="sunk"{app.dynamics = .init(buoyancy:.init(lost:mode=="sunk"))}
 precondition(app.lostInWater==row["expected"] as! Bool,"Original water ownership \(app.model)/\(mode)/\(row["y"]!)")
 checks+=1
}
let absent=WaterExitHarness();precondition(!absent.lostInWater);checks+=1
print("PASS actual vehicle water-state getter: \(checks) checks; existing floatation ownership and strict fallback threshold")
