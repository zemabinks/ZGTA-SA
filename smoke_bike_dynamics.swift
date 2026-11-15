import Foundation
import simd

@main enum BikeDynamicsSmoke {
    static func main() throws {
        let root = CommandLine.arguments.count>1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
        let data = try Data(contentsOf: URL(fileURLWithPath:root).appendingPathComponent("local-only/physics-fixtures/bike-dynamics.json"))
        let document = try JSONSerialization.jsonObject(with:data) as! [String:Any]
        func vector(_ raw: Any) -> SIMD3<Double> { let a=raw as! [Double]; return SIMD3(a[0],a[1],a[2]) }
        var errors=0,frames=0,maximum=0.0,worst=""
        func check(_ actual:Double,_ expected:Double,_ label:String,tolerance:Double=2e-9) {
            let difference=abs(actual-expected)
            if difference>maximum { maximum=difference;worst=label }
            if !actual.isFinite || difference>tolerance { if errors<15 { print("FAIL \(label): \(actual), expected \(expected), difference \(difference)") };errors += 1 }
        }
        func compare(_ actual:SIMD3<Double>,_ raw:Any,_ label:String) { let target=vector(raw);for axis in 0..<3 { check(actual[axis],target[axis],label+"[\(axis)]") } }
        for scenario in document["cases"] as! [[String:Any]] {
            let config=scenario["config"] as! [String:Any], hubs=config["hubs"] as! [String:[String:Any]]
            func hub(_ name:String)->NativeBikeDynamics.Hub { .init(at:vector(hubs[name]!["at"]!),radius:hubs[name]!["radius"] as! Double) }
            let table=NativeVehicleDynamics.Table(model:config["id"] as! Int,values:config["table"] as! [String:Any])
            let configuration=NativeBikeDynamics.Configuration(table:table,origin:config["origin"] as! Double,
                front:hub("front"),rear:hub("rear"),parameters:config["bike"] as! [String:Double],pedalled:config["pedalled"] as! Bool)
            let solver=NativeBikeDynamics(configuration:configuration,random:{0.37})!
            solver.setTyres(scenario["tyres"] as! [Int])
            for (index,frame) in (scenario["frames"] as! [[String:Any]]).enumerated() {
                let raw=frame["body"] as! [String:Any], q=raw["rotation"] as! [Double]
                let body=NativeBikeDynamics.BodyState(position:vector(raw["position"]!),rotation:simd_quatd(ix:q[0],iy:q[1],iz:q[2],r:q[3]),
                    linearVelocity:vector(raw["linearVelocity"]!),angularVelocity:vector(raw["angularVelocity"]!))
                let values=frame["input"] as! [String:Any];var input=NativeBikeDynamics.Input()
                input.throttle=values["throttle"] as? Double ?? 0;input.steer=values["steer"] as? Double ?? 0
                input.lean=values["lean"] as? Double ?? 0;input.wetness=values["wetness"] as? Double ?? 0
                input.handbrake=values["handbrake"] as? Bool ?? false;input.riderless=values["riderless"] as? Bool ?? false;input.hop=values["hop"] as? Bool ?? false
                let rays=frame["rays"] as! [Any];var rayIndex=0
                let result=solver.step(delta:document["delta"] as! Double,input:input,body:body) { _,_,_ in
                    defer { rayIndex += 1 };precondition(rayIndex<rays.count)
                    guard let hit=rays[rayIndex] as? [String:Any] else { return nil }
                    return .init(distance:hit["distance"] as! Double,normal:vector(hit["normal"]!),surface:hit["surface"] as! Int,material:hit["material"] as! Int)
                }
                precondition(rayIndex==rays.count)
                let label="\(scenario["name"]!)/\(index)"
                compare(result.linearVelocity,frame["linearVelocity"]!,label+"/linear");compare(result.angularVelocity,frame["angularVelocity"]!,label+"/angular")
                check(result.steering,frame["steering"] as! Double,label+"/steering");check(result.gas,frame["gas"] as! Double,label+"/gas")
                check(Double(result.gear),frame["gear"] as! Double,label+"/gear",tolerance:0)
                check(solver.lean,frame["lean"] as! Double,label+"/lean");check(solver.rearSpin,frame["rearSpin"] as! Double,label+"/rearSpin")
                check(Double(solver.pedal),frame["pedal"] as! Double,label+"/pedal",tolerance:0);check(solver.crank,frame["crank"] as! Double,label+"/crank")
                for (a,b) in zip(solver.drop,frame["drop"] as! [Double]) { check(a,b,label+"/drop") }
                check(result.burnout ? 1:0,(frame["burnout"] as! Bool) ? 1:0,label+"/burnout",tolerance:0)
                for (wheel,target) in zip(result.wheels,frame["wheels"] as! [[String:Any]]) {
                    let w=label+"/wheel\(wheel.index)"
                    check(wheel.compression,target["compression"] as! Double,w+"/compression");check(wheel.counts,target["counts"] as! Double,w+"/counts")
                    check(Double(wheel.state),target["state"] as! Double,w+"/state",tolerance:0);check(wheel.spin,target["spin"] as! Double,w+"/spin")
                    compare(wheel.point,target["point"]!,w+"/point");compare(wheel.normal,target["normal"]!,w+"/normal")
                }
                frames += 1
            }
            print("Replayed \(scenario["name"]!)")
        }
        print("\(errors==0 ? "PASS":"FAIL"): \(frames) original bike frames; maximum error \(maximum) at \(worst); \(errors) mismatches")
        if errors>0 { exit(1) }
    }
}
