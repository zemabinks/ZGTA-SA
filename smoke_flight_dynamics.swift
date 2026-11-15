import Foundation
import simd

@main enum FlightDynamicsSmoke {
    static func main() throws {
        let root=CommandLine.arguments[1],url=URL(fileURLWithPath:root).appendingPathComponent("local-only/physics-fixtures/flight-dynamics.json")
        let document=try JSONSerialization.jsonObject(with:Data(contentsOf:url)) as! [String:Any]
        func v(_ raw:Any)->SIMD3<Double> { let a=raw as! [Double];return SIMD3(a[0],a[1],a[2]) }
        func n(_ values:[String:Any],_ key:String)->Double { (values[key] as? NSNumber)?.doubleValue ?? 0 }
        var errors=0,count=0,maximum=0.0,worst=""
        func check(_ actual:Double,_ expected:Double,_ label:String) {
            let delta=abs(actual-expected);if delta>maximum { maximum=delta;worst=label }
            if !actual.isFinite || delta>2e-9 { if errors<12 { print("FAIL \(label): \(actual), expected \(expected), error \(delta)") };errors += 1 }
        }
        for scenario in document["cases"] as! [[String:Any]] {
            let config=scenario["config"] as! [String:Any],bounds=config["bounds"] as! [String:Any],id=Int(n(config,"id"))
            let flight=NativeFlightDynamics(parameters:NativeFlightDynamics.Parameters(config["flying"] as! [String:Any])!,
                kind:config["kind"] as! String,rearExtent:n(bounds,"minY"),jets:id==520,hover:id==539)
            for (index,frame) in (scenario["frames"] as! [[String:Any]]).enumerated() {
                let raw=frame["body"] as! [String:Any],q=raw["quaternion"] as! [Double]
                let body=NativeVehicleForces(move:v(raw["move"]!),turn:v(raw["turn"]!),right:v(raw["right"]!),forward:v(raw["forward"]!),
                    up:v(raw["up"]!),middle:v(raw["middle"]!),place:v(raw["place"]!),quaternion:simd_quatd(ix:q[0],iy:q[1],iz:q[2],r:q[3]),
                    mass:n(raw,"mass"),turnMass:n(raw,"turnMass"),wheels:Int(n(raw,"wheels")))
                let values=frame["input"] as! [String:Any];var input=NativeVehicleDynamics.Input()
                input.throttle=n(values,"throttle");input.pitch=n(values,"pitch");input.roll=n(values,"roll");input.yaw=n(values,"yaw");input.jets=n(values,"jets")
                input.nobody=values["nobody"] as? Bool ?? false
                flight.setGear(frame["gear"] as! Bool);flight.step(body,input:input,step:n(frame,"step"))
                let expected=frame["expected"] as! [String:Any],label="\(scenario["name"]!)/\(index)"
                let move=v(expected["move"]!),turn=v(expected["turn"]!)
                for axis in 0..<3 { check(body.move[axis],move[axis],label+"/move[\(axis)]");check(body.turn[axis],turn[axis],label+"/turn[\(axis)]") }
                check(flight.rotor,n(expected,"rotor"),label+"/rotor");check(flight.turning,n(expected,"turning"),label+"/turning")
                if !(expected["nozzle"] is NSNull) { check(flight.nozzle,n(expected,"nozzle"),label+"/nozzle") }
                check(flight.throttle,n(expected,"throttle"),label+"/throttle");check(flight.drag,n(expected,"drag"),label+"/drag")
                precondition(flight.gearUp==expected["gearUp"] as! Bool);count += 1
            }
            print("Replayed \(scenario["name"]!)")
        }
        print("\(errors==0 ? "PASS":"FAIL"): \(count) original aircraft force contexts; maximum error \(maximum) at \(worst); \(errors) mismatches")
        if errors>0 { exit(1) }
    }
}
