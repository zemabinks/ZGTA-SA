import Foundation
import simd
let rows = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String:Any]
let world = SwiftRapierWorld(gravity: .zero)!
var bodies: [String:UInt64] = [:]
for row in rows["cases"] as! [[String:Any]] {
    let kind = row["kind"] as! String
    let id: UInt64
    if let existing = bodies[kind] { id = existing }
    else { id = world.addBody(kind: kind == "velocity" ? .kinematicVelocity : .kinematicPosition,position: .zero)!; bodies[kind] = id }
    let q = row["input"] as! [Double]
    let rotation = simd_quatf(ix: Float(q[0]),iy: Float(q[1]),iz: Float(q[2]),r: Float(q[3]))
    let accepted = kind == "velocity" ? world.setBrowserRotation(id,rotation: rotation) : world.setBrowserNextKinematicRotation(id,rotation: rotation)
    precondition(accepted == (q != [0,0,0,0]))
    func check(_ key: String) {
        let expected = (row[key] as! [Double]).map(Float.init), actual = world.bodyState(id)!.rotation.vector
        for axis in 0..<4 { precondition(actual[axis].bitPattern == expected[axis].bitPattern,"\(kind) \(key) quaternion component \(axis)") }
    }
    check("before");world.step();check("after")
}
print("PASS: explicit JS rotation/next-rotation normalization is Float-bit exact; zero quaternion ignored; raw state API preserved")
