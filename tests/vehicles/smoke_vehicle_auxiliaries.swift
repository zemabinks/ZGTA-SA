import Foundation
import simd

@main enum VehicleAuxiliariesSmoke {
    static func main() throws {
        let root=CommandLine.arguments[1]
        func v(_ raw:Any)->SIMD3<Double> { let a=raw as! [Double];return SIMD3(a[0],a[1],a[2]) }
        func n(_ values:[String:Any],_ key:String)->Double { (values[key] as? NSNumber)?.doubleValue ?? 0 }
        var errors=0,count=0,maximum=0.0,worst=""
        func check(_ actual:Double,_ expected:Double,_ label:String,tolerance:Double=2e-9) {
            let delta=abs(actual-expected);if delta>maximum { maximum=delta;worst=label }
            if !actual.isFinite || delta>tolerance { if errors<12 { print("FAIL \(label): \(actual), expected \(expected), error \(delta)") };errors += 1 }
        }
        func compare(_ actual:SIMD3<Double>,_ raw:Any,_ label:String) {
            let expected=v(raw);for axis in 0..<3 { check(actual[axis],expected[axis],label+"[\(axis)]") }
        }
        for name in ["flight-dynamics","vehicle-buoyancy"] {
            let url=URL(fileURLWithPath:root).appendingPathComponent("local-only/physics-fixtures/\(name).json")
            let document=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
            for scenario in document["cases"] as! [[String:Any]] {
                let config=scenario["config"] as! [String:Any],id=Int(n(config,"id")),kind=config["kind"] as! String
                let table=NativeVehicleDynamics.Table(model:id,values:config["table"] as! [String:Any])
                let rawWheels=config["struts"] as? [[String:Any]] ?? config["wheels"] as! [[String:Any]]
                let wheels=rawWheels.map { NativeVehicleDynamics.WheelSpecification(centre:v($0["centre"]!),radius:n($0,"radius"),front:$0["front"] as! Bool,left:$0["left"] as! Bool) }
                let solver=NativeVehicleDynamics(configuration:.init(table:table,origin:n(config,"origin"),wheels:wheels,kind:kind),random:{0.37})!
                let bounds=config["bounds"] as! [String:Any],collision=config["collision"] as? [String:Any]
                let box=collision?["box"] as? [String:Any] ?? bounds["box"] as! [String:Any]
                solver.buoyancy=NativeVehicleBuoyancy(table:table,minimum:v(box["min"]!),maximum:v(box["max"]!),parameters:(config["boat"] as? [String:Any]).flatMap { NativeVehicleBuoyancy.Parameters($0) })!
                if let values=config["flying"] as? [String:Any] {
                    solver.flight=NativeFlightDynamics(parameters:NativeFlightDynamics.Parameters(values)!,kind:kind,rearExtent:n(bounds,"minY"),jets:id==520,hover:id==539)
                }
                var levels:[[String:Any]]=[],waves:[[String:Any]]=[],levelIndex=0,waveIndex=0,label=""
                if name=="vehicle-buoyancy" {
                    solver.buoyancy?.waterLevel={ point in
                        precondition(levelIndex<levels.count,"Unexpected full water query \(label)")
                        let query=levels[levelIndex];levelIndex += 1;compare(point,query["point"]!,label+"/water")
                        return (query["level"] as? NSNumber)?.doubleValue
                    }
                    if scenario["waves"] as! Bool { solver.buoyancy?.wave={ _ in
                        precondition(waveIndex<waves.count);let row=waves[waveIndex];waveIndex += 1
                        return .init(height:n(row,"height"),normal:v(row["normal"]!))
                    } }
                }
                for (index,frame) in (scenario["frames"] as! [[String:Any]]).enumerated() {
                    let full=frame["full"] as! [String:Any],raw=full["body"] as! [String:Any],q=raw["rotation"] as! [Double]
                    let state=NativeVehicleDynamics.BodyState(position:v(raw["position"]!),rotation:simd_quatd(ix:q[0],iy:q[1],iz:q[2],r:q[3]),linearVelocity:v(raw["linearVelocity"]!),angularVelocity:v(raw["angularVelocity"]!))
                    let values=frame["input"] as! [String:Any];var input=NativeVehicleDynamics.Input()
                    input.throttle=n(values,"throttle");input.steer=n(values,"steer");input.pitch=n(values,"pitch");input.roll=n(values,"roll");input.yaw=n(values,"yaw");input.jets=n(values,"jets")
                    input.nobody=values["nobody"] as? Bool ?? false;input.handbrake=values["handbrake"] as? Bool ?? false
                    input.accelerate=(values["accelerate"] as? NSNumber)?.doubleValue;input.brake=(values["brake"] as? NSNumber)?.doubleValue
                    solver.flight?.setGear(frame["gear"] as? Bool ?? false)
                    levels=full["levels"] as? [[String:Any]] ?? [];waves=full["waves"] as? [[String:Any]] ?? [];levelIndex=0;waveIndex=0
                    label="\(scenario["name"]!)/\(index)"
                    let rays=full["rays"] as! [Any];var rayIndex=0
                    let output=solver.step(delta:1/60,input:input,body:state) { _,_,_ in
                        precondition(rayIndex<rays.count,"Unexpected ray \(label)");let raw=rays[rayIndex];rayIndex += 1
                        guard let hit=raw as? [String:Any] else { return nil }
                        return .init(distance:n(hit,"distance"),normal:v(hit["normal"]!),surface:Int(n(hit,"surface")),material:Int(n(hit,"material")))
                    }
                    precondition(rayIndex==rays.count && levelIndex==levels.count && waveIndex==waves.count,"Original full queries not consumed \(label)")
                    compare(output.linearVelocity,full["linearVelocity"]!,label+"/linear");compare(output.angularVelocity,full["angularVelocity"]!,label+"/angular")
                    check(output.steering,n(full,"steering"),label+"/steering");check(Double(output.gear),n(full,"gear"),label+"/gear",tolerance:0)
                    check(output.gas,n(full,"gas"),label+"/gas");check(output.burnout ? 1:0,(full["burnout"] as! Bool) ? 1:0,label+"/burnout",tolerance:0)
                    for (wheel,target) in zip(output.wheels,full["wheels"] as! [[String:Any]]) {
                        let w=label+"/wheel\(wheel.index)"
                        check(wheel.compression,n(target,"compression"),w+"/compression");check(wheel.offset,n(target,"offset"),w+"/offset")
                        check(wheel.counts,n(target,"counts"),w+"/counts");check(Double(wheel.state),n(target,"state"),w+"/state",tolerance:0)
                        check(wheel.spin,n(target,"spin"),w+"/spin");compare(wheel.point,target["point"]!,w+"/point");compare(wheel.normal,target["normal"]!,w+"/normal")
                    }
                    count += 1
                }
                print("Replayed coupled \(scenario["name"]!)")
            }
        }
        print("\(errors==0 ? "PASS":"FAIL"): \(count) whole original vehicle/flight/buoyancy frames; maximum error \(maximum) at \(worst); \(errors) mismatches")
        if errors>0 { exit(1) }
    }
}
