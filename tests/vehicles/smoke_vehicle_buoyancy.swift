import Foundation
import simd

@main enum VehicleBuoyancySmoke {
    static func main() throws {
        let root=CommandLine.arguments[1],url=URL(fileURLWithPath:root).appendingPathComponent("local-only/physics-fixtures/vehicle-buoyancy.json")
        let document=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
        func v(_ raw:Any)->SIMD3<Double> { let a=raw as! [Double];return SIMD3(a[0],a[1],a[2]) }
        func n(_ values:[String:Any],_ key:String)->Double { (values[key] as? NSNumber)?.doubleValue ?? 0 }
        var errors=0,count=0,maximum=0.0,worst=""
        func check(_ actual:Double,_ expected:Double,_ label:String) {
            let delta=abs(actual-expected);if delta>maximum { maximum=delta;worst=label }
            if !actual.isFinite || delta>2e-9 { if errors<12 { print("FAIL \(label): \(actual), expected \(expected), error \(delta)") };errors += 1 }
        }
        for scenario in document["cases"] as! [[String:Any]] {
            let config=scenario["config"] as! [String:Any],table=NativeVehicleDynamics.Table(model:Int(n(config,"id")),values:config["table"] as! [String:Any])
            let bounds=config["bounds"] as! [String:Any],collision=config["collision"] as? [String:Any]
            let box=collision?["box"] as? [String:Any] ?? bounds["box"] as! [String:Any]
            let parameters=(config["boat"] as? [String:Any]).flatMap { NativeVehicleBuoyancy.Parameters($0) }
            let buoyancy=NativeVehicleBuoyancy(table:table,minimum:v(box["min"]!),maximum:v(box["max"]!),parameters:parameters)!
            var levels:[[String:Any]]=[],waves:[[String:Any]]=[],levelIndex=0,waveIndex=0,label=""
            buoyancy.waterLevel={ point in
                precondition(levelIndex<levels.count,"Unexpected water-level query")
                let query=levels[levelIndex];levelIndex += 1
                let expected=v(query["point"]!);for axis in 0..<3 { check(point[axis],expected[axis],label+"/query[\(axis)]") }
                return (query["level"] as? NSNumber)?.doubleValue
            }
            if scenario["waves"] as! Bool { buoyancy.wave={ _ in
                precondition(waveIndex<waves.count,"Unexpected wave query")
                let query=waves[waveIndex];waveIndex += 1
                return .init(height:n(query,"height"),normal:v(query["normal"]!))
            } }
            for (index,frame) in (scenario["frames"] as! [[String:Any]]).enumerated() {
                let raw=frame["body"] as! [String:Any],q=raw["quaternion"] as! [Double]
                let body=NativeVehicleForces(move:v(raw["move"]!),turn:v(raw["turn"]!),right:v(raw["right"]!),forward:v(raw["forward"]!),up:v(raw["up"]!),
                    middle:v(raw["middle"]!),place:v(raw["place"]!),quaternion:simd_quatd(ix:q[0],iy:q[1],iz:q[2],r:q[3]),mass:n(raw,"mass"),turnMass:n(raw,"turnMass"),wheels:Int(n(raw,"wheels")))
                let values=frame["input"] as! [String:Any];var input=NativeVehicleDynamics.Input()
                input.throttle=n(values,"throttle");input.steer=n(values,"steer");input.handbrake=values["handbrake"] as? Bool ?? false
                input.accelerate=(values["accelerate"] as? NSNumber)?.doubleValue;input.brake=(values["brake"] as? NSNumber)?.doubleValue
                levels=frame["levels"] as! [[String:Any]];waves=frame["waves"] as! [[String:Any]];levelIndex=0;waveIndex=0
                label="\(scenario["name"]!)/\(index)"
                buoyancy.step(body,input:input,step:n(frame,"step"),wheels:Int(n(frame,"wheels")))
                if levelIndex != levels.count || waveIndex != waves.count {
                    FileHandle.standardError.write(Data("Query mismatch \(label): levels \(levelIndex)/\(levels.count), waves \(waveIndex)/\(waves.count)\n".utf8))
                    exit(1)
                }
                let expected=frame["expected"] as! [String:Any],move=v(expected["move"]!),turn=v(expected["turn"]!)
                for axis in 0..<3 { check(body.move[axis],move[axis],label+"/move[\(axis)]");check(body.turn[axis],turn[axis],label+"/turn[\(axis)]") }
                let flags:[String:Bool]=["touching":buoyancy.touching,"onWater":buoyancy.onWater,"lost":buoyancy.lost,"dead":buoyancy.dead,"propeller":buoyancy.propeller,"wake":buoyancy.wake]
                for (key,value) in flags { check(value ? 1:0,(expected[key] as! Bool) ? 1:0,label+"/"+key) }
                check(buoyancy.rudder,n(expected,"rudder"),label+"/rudder");check(buoyancy.gas,n(expected,"gas"),label+"/gas")
                check(buoyancy.immersion,n(expected,"immersion"),label+"/immersion");check(buoyancy.takeSlam(),n(expected,"slam"),label+"/slam")
                count += 1
            }
            print("Replayed \(scenario["name"]!)")
        }
        print("\(errors==0 ? "PASS":"FAIL"): \(count) original buoyancy contexts; maximum error \(maximum) at \(worst); \(errors) mismatches")
        if errors>0 { exit(1) }
    }
}
