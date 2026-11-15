import Foundation
import simd

// Replay original body states and original wheel queries through the Swift
// solver. This isolates the translation from native/WASM integration drift.
@main enum VehicleDynamicsSmoke {
    static func main() throws {
        let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
        let url = URL(fileURLWithPath: root).appendingPathComponent("local-only/physics-fixtures/vehicle-dynamics.json")
        let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
        let config = fixture["config"] as! [String: Any]
        func vector(_ raw: Any) -> SIMD3<Double> { let v = raw as! [Double]; return SIMD3(v[0],v[1],v[2]) }
        let wheels = (config["wheels"] as! [[String: Any]]).map {
            NativeVehicleDynamics.WheelSpecification(centre: vector($0["centre"]!), radius: $0["radius"] as! Double,
                front: $0["front"] as! Bool, left: $0["left"] as! Bool)
        }
        let delta = fixture["delta"] as! Double
        var failures = 0, frameCount = 0, largestError = 0.0, largestLabel = ""
        func check(_ actual: Double, _ expected: Double, _ label: String, tolerance: Double = 2e-9) {
            let error = abs(actual - expected)
            if error > largestError { largestError = error; largestLabel = label }
            if !actual.isFinite || error > tolerance {
                if failures < 12 { print("FAIL \(label): \(actual) expected \(expected), error \(error)") }
                failures += 1
            }
        }
        func checkVector(_ actual: SIMD3<Double>, _ raw: Any, _ label: String) {
            let expected = vector(raw)
            for axis in 0..<3 { check(actual[axis], expected[axis], "\(label)[\(axis)]") }
        }
        for scenario in fixture["cases"] as! [[String: Any]] {
            let settings = scenario["settings"] as? [String: Any] ?? [:]
            let table = NativeVehicleDynamics.Table(model: config["model"] as! Int, values: settings["table"] as? [String: Any] ?? config["table"] as! [String: Any])
            let configuration = NativeVehicleDynamics.Configuration(table: table, origin: config["origin"] as! Double, wheels: wheels,
                hydraulics: settings["hydraulics"] as? Bool ?? false, nitro: settings["nitro"] as? Bool ?? false)
            let solver = NativeVehicleDynamics(configuration: configuration, random: { 0.37 })!
            solver.manual = settings["manual"] as? Bool ?? false; solver.fun = settings["fun"] as? Int ?? 0
            solver.setTyres(settings["tyres"] as? [Int] ?? [])
            let name = scenario["name"] as! String
            for (index, frame) in (scenario["frames"] as! [[String: Any]]).enumerated() {
                let body = frame["body"] as! [String: Any], rotation = body["rotation"] as! [Double]
                let state = NativeVehicleDynamics.BodyState(position: vector(body["position"]!),
                    rotation: simd_quatd(ix: rotation[0],iy: rotation[1],iz: rotation[2],r: rotation[3]),
                    linearVelocity: vector(body["linearVelocity"]!), angularVelocity: vector(body["angularVelocity"]!))
                let rawInput = frame["input"] as! [String: Any]
                var input = NativeVehicleDynamics.Input()
                input.throttle = rawInput["throttle"] as? Double ?? 0; input.steer = rawInput["steer"] as? Double ?? 0
                input.lean = rawInput["lean"] as? Double ?? 0; input.handbrake = rawInput["handbrake"] as? Bool ?? false
                input.wetness = rawInput["wetness"] as? Double ?? 0
                input.accelerate = rawInput["accelerate"] as? Double; input.brake = rawInput["brake"] as? Double
                input.pad = rawInput["pad"] as? Bool ?? false
                input.suspensionOffsets = rawInput["suspensionOffsets"] as? [Double] ?? []
                if let actions = frame["actions"] as? [String: Any] {
                    if actions["fire"] as? Bool == true { solver.fireNitro() }
                    if let shift = actions["shift"] as? Int { solver.shift(shift) }
                }
                let rays = frame["rays"] as! [Any]; var rayIndex = 0
                let output = solver.step(delta: delta, input: input, body: state) { _,_,_ in
                    defer { rayIndex += 1 }
                    precondition(rayIndex < rays.count, "Unexpected extra wheel ray")
                    guard let hit = rays[rayIndex] as? [String: Any] else { return nil }
                    return NativeVehicleDynamics.RayHit(distance: hit["distance"] as! Double,
                        normal: vector(hit["normal"]!), surface: hit["surface"] as! Int, material: hit["material"] as! Int)
                }
                precondition(rayIndex == rays.count, "Not all original wheel rays consumed")
                let prefix = "\(name)/\(index)"
                checkVector(output.linearVelocity, frame["linearVelocity"]!, prefix + "/linear")
                checkVector(output.angularVelocity, frame["angularVelocity"]!, prefix + "/angular")
                check(output.steering, frame["steering"] as! Double, prefix + "/steering")
                check(output.rearSteering, frame["rearSteering"] as! Double, prefix + "/rearSteering")
                check(Double(output.gear), frame["gear"] as! Double, prefix + "/gear", tolerance: 0)
                check(output.gas, frame["gas"] as! Double, prefix + "/gas", tolerance: 0)
                precondition(output.burnout == frame["burnout"] as! Bool)
                for (wheel, expected) in zip(output.wheels, frame["wheels"] as! [[String: Any]]) {
                    let wp = prefix + "/wheel\(wheel.index)"
                    check(wheel.compression, expected["compression"] as! Double, wp + "/compression")
                    check(wheel.offset, expected["offset"] as! Double, wp + "/offset")
                    check(wheel.counts, expected["counts"] as! Double, wp + "/counts")
                    check(Double(wheel.state), expected["state"] as! Double, wp + "/state", tolerance: 0)
                    check(wheel.spin, expected["spin"] as! Double, wp + "/spin")
                    checkVector(wheel.point, expected["point"]!, wp + "/point")
                    checkVector(wheel.normal, expected["normal"]!, wp + "/normal")
                }
                frameCount += 1
            }
            print("Replayed \(name)")
        }
        print("\(failures == 0 ? "PASS" : "FAIL"): \(frameCount) original solver frames; maximum error \(largestError) at \(largestLabel); \(failures) mismatches")
        if failures > 0 { exit(1) }
    }
}
