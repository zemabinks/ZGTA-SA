import Foundation
import simd

@main enum TrainDynamicsSmoke {
    static func main() throws {
        let root=CommandLine.arguments[1],base=URL(fileURLWithPath:root)
        let tracks=NativeTrainTracks(data:try Data(contentsOf:base.appendingPathComponent("local-only/site/game/native/trains.json")))!
        let document=try JSONSerialization.jsonObject(with:Data(contentsOf:base.appendingPathComponent("local-only/physics-fixtures/train-dynamics.json"))) as! [String:Any]
        func v(_ raw:Any)->SIMD3<Double> { let a=raw as! [Double];return SIMD3(a[0],a[1],a[2]) }
        func n(_ values:[String:Any],_ key:String)->Double { (values[key] as? NSNumber)?.doubleValue ?? 0 }
        func configuration(_ row:[String:Any])->NativeTrainDynamics.Configuration {
            let table=row["table"] as! [String:Any],bounds=row["bounds"] as! [String:Any],box=bounds["box"] as! [String:Any]
            return .init(model:Int(n(row,"id")),origin:n(row,"origin"),lower:n(table,"lower"),minimum:v(box["min"]!),maximum:v(box["max"]!),carriages:row["carriages"] as? [Int] ?? [])
        }
        var failures=0,count=0,largest=0.0,worst=""
        func check(_ actual:Double,_ expected:Double,_ label:String,tolerance:Double=2e-9) {
            let error=abs(actual-expected);if error>largest { largest=error;worst=label }
            if !actual.isFinite || error>tolerance { if failures<15 { print("FAIL \(label): \(actual), expected \(expected), error \(error)") };failures += 1 }
        }
        func vector(_ actual:SIMD3<Double>,_ raw:Any,_ label:String,tolerance:Double=2e-9) { let expected=v(raw);for axis in 0..<3 { check(actual[axis],expected[axis],label+"[\(axis)]",tolerance:tolerance) } }
        func quaternion(_ actual:simd_quatd,_ raw:Any,_ label:String) { let a=raw as! [Double];for axis in 0..<4 { check(actual.vector[axis],a[axis],label+"[\(axis)]") } }
        for (index,pair) in zip(tracks.lines,document["lines"] as! [[String:Any]]).enumerated() {
            let (line,reference)=pair,points=reference["points"] as! [Double],from=reference["from"] as! [Double]
            for point in line.points.indices { for axis in 0..<3 { check(line.points[point][axis],points[point*3+axis],"track\(index)/point",tolerance:0) } }
            for (a,b) in zip(line.from,from) { check(a,b,"track\(index)/arc",tolerance:0) }
            check(line.total,n(reference,"total"),"track\(index)/total",tolerance:0)
        }
        for scenario in document["cases"] as! [[String:Any]] {
            let row=scenario["config"] as! [String:Any],config=configuration(row)
            let carriageConfigurations=(scenario["carriageConfigs"] as? [[String:Any]] ?? []).map(configuration)
            let solver=NativeTrainDynamics(configuration:config,tracks:tracks,position:v(scenario["start"]!),heading:n(scenario,"heading"))!
            let initial=scenario["initial"] as! [String:Any]
            vector(SIMD3<Double>(SIMD3<Float>(solver.initial.position)),initial["position"]!,"\(scenario["name"]!)/initial",tolerance:0)
            for (index,frame) in (scenario["frames"] as! [[String:Any]]).enumerated() {
                let input=frame["input"] as! [String:Any]
                let result=solver.step(delta:1/60,throttle:n(input,"throttle"),handbrake:input["handbrake"] as? Bool ?? false)
                let label="\(scenario["name"]!)/\(index)"
                let body=frame["body"] as! [String:Any],bodyRotation=body["rotation"] as! [Double]
                let bodyPose=NativeTrainDynamics.Pose(position:v(body["position"]!),rotation:simd_quatd(vector:SIMD4(bodyRotation)))
                let carriages=solver.carriages(body:bodyPose,configurations:carriageConfigurations)
                let expectedCarriages=frame["carriages"] as? [[String:Any]] ?? []
                check(Double(carriages.count),Double(expectedCarriages.count),label+"/carriage-count",tolerance:0)
                for (index,pair) in zip(carriages,expectedCarriages).enumerated() {
                    vector(pair.0.position,pair.1["position"]!,label+"/carriage\(index)/position")
                    quaternion(pair.0.rotation,pair.1["rotation"]!,label+"/carriage\(index)/rotation")
                }
                vector(result.pose.position,frame["position"]!,label+"/position");quaternion(result.pose.rotation,frame["rotation"]!,label+"/rotation")
                vector(result.linearVelocity,frame["linearVelocity"]!,label+"/linear");vector(result.angularVelocity,frame["angularVelocity"]!,label+"/angular")
                check(solver.speed,n(frame,"speed"),label+"/speed");count += 1
            }
            print("Replayed \(scenario["name"]!)")
        }
        print("\(failures==0 ? "PASS":"FAIL"): \(count) original trainframes,4track Float32arcs; maximum error \(largest) at \(worst); \(failures) mismatches")
        if failures>0 { exit(1) }
    }
}
