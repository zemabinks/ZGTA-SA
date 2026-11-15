import Foundation
import simd

typealias V = SIMD3<Double>
func vector(_ value: Any?) -> V {
    let a = value as! [Double]; return V(a[0],a[1],a[2])
}
func f(_ v: V) -> SIMD3<Float> { SIMD3(Float(v.x),Float(v.y),Float(v.z)) }
func d(_ v: SIMD3<Float>) -> V { V(Double(v.x),Double(v.y),Double(v.z)) }
func num(_ j: [String:Any], _ key: String, _ fallback: Double = 0) -> Double { (j[key] as? NSNumber)?.doubleValue ?? fallback }
func flag(_ j: [String:Any], _ key: String) -> Bool { j[key] as? Bool ?? false }
let path = CommandLine.arguments[1]
let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: path))) as! [String:Any]
let config = fixture["config"] as! [String:Any], tableJSON = config["table"] as! [String:Any]
let table = NativeVehicleDynamics.Table(model: Int(num(config,"model")), values: tableJSON)
let wheels = (config["wheels"] as! [[String:Any]]).map {
    NativeVehicleDynamics.WheelSpecification(centre: vector($0["centre"]), radius: num($0,"radius"),front: flag($0,"front"),left: flag($0,"left"))
}
let configuration = NativeVehicleDynamics.Configuration(table: table, origin: num(config,"origin"),wheels: wheels)
let cases = Array((fixture["cases"] as! [[String:Any]]).prefix(4))
var summary: [[String:Any]] = []
for useNativeSolver in [false,true] {
    for test in cases {
        let name = test["name"] as! String, frames = test["frames"] as! [[String:Any]]
        let world = SwiftRapierWorld(gravity: SIMD3(0,-9.81,0))!
        // Preserve the original fixture's collider insertion order: floor before
        // chassis. Reversing contact-pair order changes f32 manifold iteration.
        world.addBox(halfExtents: SIMD3(1000,0.1,1000),position: SIMD3(0,-0.1,0))
        let start = frames[0]["body"] as! [String:Any]
        let body = world.addBody(position: f(vector(start["position"])), mass: .init(value: Float(table.mass),
            centre: SIMD3(Float(table.comX),Float(table.comZ),Float(-table.comY)), turnMass: Float(table.turnMass)))!
        let shape = world.addBox(halfExtents: SIMD3(1,0.6,2.5),body: body,position: SIMD3(0,0.1,0),
            friction: Float(min(0.8,450/table.mass)),restitution: 0.05)!
        world.setColliderGroups(shape,collision: 327663,solver: 0xfdffffff)
        world.step() // Match the original harness initialization step.
        let solver = NativeVehicleDynamics(configuration: configuration, random: { 0.37 })!
        var maxPosition = 0.0, maxVelocity = 0.0, maxRotation = 0.0
        for frame in frames {
            let actual = world.bodyState(body)!, reference = frame["body"] as! [String:Any]
            maxPosition = max(maxPosition,simd_length(d(actual.position)-vector(reference["position"])))
            maxVelocity = max(maxVelocity,simd_length(d(actual.linearVelocity)-vector(reference["linearVelocity"])))
            let rq = reference["rotation"] as! [Double]
            let aq = simd_quatd(ix: Double(actual.rotation.imag.x),iy: Double(actual.rotation.imag.y),iz: Double(actual.rotation.imag.z),r: Double(actual.rotation.real))
            maxRotation = max(maxRotation,simd_length(aq.vector-SIMD4(rq[0],rq[1],rq[2],rq[3])))
            var linear: V, angular: V
            if useNativeSolver {
                let source = frame["input"] as! [String:Any]
                var input = NativeVehicleDynamics.Input()
                input.throttle = num(source,"throttle"); input.steer = num(source,"steer")
                input.handbrake = flag(source,"handbrake"); input.lean = num(source,"lean")
                input.abandoned = flag(source,"abandoned"); input.pad = flag(source,"pad"); input.wetness = num(source,"wetness")
                input.suspensionOffsets = source["suspensionOffsets"] as? [Double] ?? []
                input.accelerate = (source["accelerate"] as? NSNumber)?.doubleValue
                input.brake = (source["brake"] as? NSNumber)?.doubleValue
                if let pedal = source["pedals"] as? [Double] { input.pedals = SIMD2(pedal[0],pedal[1]) }
                let output = solver.step(delta: 1/60,input: input, body: .init(position: d(actual.position),rotation: aq,
                    linearVelocity: d(actual.linearVelocity),angularVelocity: d(actual.angularVelocity))) { origin,direction,distance in
                    guard let hit = world.raycast(origin: f(origin),direction: f(direction),distance: Float(distance),excludingBody: body) else { return nil }
                    return NativeVehicleDynamics.RayHit(distance: Double(hit.distance),normal: d(hit.normal),surface: hit.surface,material: hit.material)
                }
                linear = output.linearVelocity; angular = output.angularVelocity
            } else { linear = vector(frame["linearVelocity"]); angular = vector(frame["angularVelocity"]) }
            precondition(world.setVelocities(body,linear: f(linear),angular: f(angular)))
            precondition(world.step())
        }
        let position = d(world.bodyState(body)!.position), error = simd_length(position-vector(test["final"]))
        // Integrated f32 physics is compared with an absolute physical tolerance,
        // separately from the near-machine-epsilon Double force-translation gate.
        precondition(error.isFinite && maxPosition.isFinite)
        precondition(maxPosition < 0.01 && error < 0.01, "Vehicle path exceeded 1 cm tolerance")
        precondition(maxVelocity < 0.1, "Vehicle velocity exceeded 0.1 m/s tolerance")
        precondition(maxRotation < 0.005, "Vehicle quaternion exceeded component tolerance")
        let mode = useNativeSolver ? "native-solver-and-core" : "recorded-forces-native-core"
        let result: [String:Any] = ["case":name,"mode":mode,"frames":frames.count,"maxPositionError":maxPosition,
            "maxLinearVelocityError":maxVelocity,"maxQuaternionComponentError":maxRotation,"finalPositionError":error,
            "finalPosition":[position.x,position.y,position.z]]
        summary.append(result)
        print("\(mode) \(name): max position \(maxPosition), velocity \(maxVelocity), final \(error)")
    }
}
let report = try JSONSerialization.data(withJSONObject: summary,options: [.prettyPrinted,.sortedKeys])
try report.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
