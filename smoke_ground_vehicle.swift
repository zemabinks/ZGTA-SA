import Foundation
import simd

@main enum GroundVehicleSmoke {
    static func main() throws {
        let root = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : FileManager.default.currentDirectoryPath
        let source = try Data(contentsOf: URL(fileURLWithPath: root).appendingPathComponent("local-only/site/game/native/vehicles.physics.json"))
        let document = try JSONSerialization.jsonObject(with: source) as! [String: Any]
        let models = document["models"] as! [String: [String: Any]]
        let manager = NativeGroundVehicle()!
        let count = manager.loadDefinitions(source)
        precondition(count == models.values.filter { $0["solverSupported"] as? Bool == true }.count)
        var entered = 0
        for (model, row) in models where row["solverSupported"] as? Bool == true {
            precondition(manager.enter(model: model, modelPosition: SIMD3(0,0,2), heading: 0.3), "Original chassis refused: \(model)")
            precondition(manager.modelTransform.columns.3.z.isFinite)
            manager.exit(); entered += 1
        }
        // Compare two display cadences over an identical fixed-time input
        // sequence, exercising production COL chassis rather than a test box.
        func floorData() -> Data {
            var result = Data()
            func word(_ value: UInt32) { var little = value.littleEndian; withUnsafeBytes(of: &little) { result.append(contentsOf: $0) } }
            [UInt32(0x324c4353),4,2,1].forEach(word)
            for value: Float in [-1000,-1000,0, 1000,-1000,0, 1000,1000,0, -1000,1000,0] { word(value.bitPattern) }
            [UInt32(0),1,2,0,2,3].forEach(word)
            result.append(contentsOf: [2,2,0,0,1,1,0,0]); return result
        }
        let flat = floorData()
        func simulate(hz: Int) -> (SIMD3<Float>, Float, simd_quatf) {
            let simulation = NativeGroundVehicle()!; simulation.loadDefinitions(source)
            simulation.installCell("floor", data: flat)
            precondition(simulation.isCellLoaded("floor"))
            precondition(simulation.enter(model: "420", modelPosition: SIMD3(0,0,1.1), heading: 0))
            var input = NativeVehicleDynamics.Input(); input.throttle = 1; input.steer = 0.2
            for _ in 0..<hz*5 { simulation.update(delta: 1 / Double(hz), input: input, currentCell: "floor") }
            precondition(simulation.modelPosition.z > 0.3 && simulation.modelPosition.z < 2)
            precondition(simulation.speed > 1 && simd_length(simulation.modelPosition) > 5)
            return (simulation.modelPosition,simulation.speed,simulation.orientation)
        }
        let a = simulate(hz: 60), b = simulate(hz: 120)
        precondition(simd_distance(a.0,b.0) < 1e-6 && abs(a.1-b.1) < 1e-6)
        precondition(simd_length(a.2.vector-b.2.vector) < 1e-6)
        print("PASS: \(entered) production ground chassis; shared SCL2 contacts; fixed 60/120 Hz cadence identical; Taxi420 final \(a.0), speed \(a.1)")
    }
}
