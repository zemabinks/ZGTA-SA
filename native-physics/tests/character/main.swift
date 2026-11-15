import Foundation
import simd

typealias V = SIMD3<Double>
func v(_ raw: Any) -> V { let a = raw as! [Double]; return V(a[0],a[1],a[2]) }
func f(_ raw: Any) -> SIMD3<Float> { SIMD3<Float>(v(raw)) }
let fixture = try JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))) as! [String:Any]
let delta = fixture["delta"] as! Double
var reports: [[String:Any]] = [], failed = false, totalFrames = 0
for scenario in fixture["cases"] as! [[String:Any]] {
    let scene = scenario["scene"] as! [[String:Any]], name = scenario["name"] as! String
    let world = SwiftRapierWorld(gravity: SIMD3(0,-9.81,0))!
    var bodyIDs: [Int:UInt64] = [:], colliderIDs: [Int:UInt64] = [:]
    for shape in scene {
        var parent: UInt64?
        if let body = shape["body"] as? [String:Any] {
            let frame = body["inertiaFrame"] as! [Double]
            precondition(frame == [0,0,0,1], "Extend the fixture for non-axis-aligned principal inertia")
            parent = world.addBody(position: f(body["position"]!),mass: .init(value: Float(body["mass"] as! Double),
                centre: f(body["localCom"]!),inertia: f(body["inertia"]!)),gravityScale: 1)!
            bodyIDs[body["id"] as! Int] = parent
        }
        let q = shape["rotation"] as! [Double]
        let id = world.addBox(halfExtents: f(shape["half"]!),body: parent,position: f(shape["at"]!),
            rotation: simd_quatf(ix: Float(q[0]),iy: Float(q[1]),iz: Float(q[2]),r: Float(q[3])))!
        colliderIDs[shape["id"] as! Int] = id
        world.setColliderGroups(id,collision: UInt32((shape["groups"] as! NSNumber).uint64Value),solver: 0xffffffff)
        world.setColliderSurface(id,surface: 2,material: Int32(shape["material"] as! Int))
    }
    world.step()
    let queries = NativeRapierCharacterQueries(world: world)!, motor = NativeCharacterMotor(world: queries)
    motor.otherColliders = Set((scenario["others"] as! [Int]).compactMap { colliderIDs[$0] })
    motor.setActive(true)
    let frames = scenario["frames"] as! [[String:Any]]
    var position = v(frames[0]["before"]!), maxPosition = 0.0, maxRising = 0.0, maxEasing = 0.0
    var groundMismatch = 0, propMismatch = 0, barrierMismatch = 0, pressMismatch = 0, firstDifference: [String:Any] = [:]
    var maxPressPoint = 0.0, maxPressSpeed = 0.0, maxPressDirection = 0.0
    for (index,frame) in frames.enumerated() {
        let input = frame["input"] as! [String:Any], expected = frame["expected"] as! [String:Any]
        motor.step(position: &position,displacement: v(input["travel"]!),jump: input["jump"] as? Double ?? 0,
            delta: delta,held: input["held"] as? Bool ?? false,verticalOverride: input["vertical"] as? Double)
        let error = simd_length(position-v(expected["position"]!)), rising = abs(motor.rising-(expected["rising"] as! Double))
        maxPosition = max(maxPosition,error); maxRising = max(maxRising,rising)
        maxEasing = max(maxEasing,abs(motor.eased()-(expected["easing"] as! Double)))
        let presses = expected["pressed"] as! [[String:Any]]
        if presses.count != motor.pressed.count { pressMismatch += 1 }
        for (actual,press) in zip(motor.pressed,presses) {
            if actual.body != bodyIDs[press["body"] as! Int] { pressMismatch += 1 }
            maxPressPoint = max(maxPressPoint,simd_length(actual.point-v(press["point"]!)))
            maxPressSpeed = max(maxPressSpeed,abs(actual.speed-(press["speed"] as! Double)))
            let direction = press["direction"] as! [Double]
            maxPressDirection = max(maxPressDirection,simd_length(actual.direction-SIMD2(direction[0],direction[1])))
        }
        let groundDiff = motor.grounded != expected["grounded"] as! Bool
        let propDiff = motor.propped != expected["propped"] as! Bool
        if groundDiff { groundMismatch += 1 }; if propDiff { propMismatch += 1 }
        for (angle,value) in zip([0,Double.pi/2,Double.pi,Double.pi*1.5],expected["barred"] as! [Bool]) {
            if motor.barred(angle) != value { barrierMismatch += 1 }
        }
        if firstDifference.isEmpty && (error > 1e-5 || rising > 1e-5 || groundDiff || propDiff) {
            firstDifference = ["frame":index,"positionError":error,"actualPosition":[position.x,position.y,position.z],
                "expectedPosition":expected["position"]!,"rising":motor.rising,"expectedRising":expected["rising"]!,
                "grounded":motor.grounded,"expectedGrounded":expected["grounded"]!]
        }
        precondition(error.isFinite && rising.isFinite)
        world.step(); totalFrames += 1
    }
    let result: [String:Any] = ["case":name,"frames":frames.count,"maxPositionError":maxPosition,
        "maxRisingError":maxRising,"maxEasingError":maxEasing,"groundedMismatches":groundMismatch,
        "proppedMismatches":propMismatch,"barredMismatches":barrierMismatch,"pressMismatches":pressMismatch,
        "maxPressPointError":maxPressPoint,"maxPressSpeedError":maxPressSpeed,"maxPressDirectionError":maxPressDirection,"firstDifference":firstDifference]
    reports.append(result)
    if maxPosition > 0.01 || maxRising > 0.1 || groundMismatch > 0 || propMismatch > 0 || barrierMismatch > 0 || pressMismatch > 0 || maxPressPoint > 0.01 || maxPressSpeed > 0.1 || maxPressDirection > 0.001 { failed = true }
    print("\(name): position \(maxPosition), rising \(maxRising), easing \(maxEasing), grounded \(groundMismatch), propped \(propMismatch), barrier \(barrierMismatch), press \(pressMismatch) point \(maxPressPoint) speed \(maxPressSpeed)")
}
try JSONSerialization.data(withJSONObject: reports,options: [.prettyPrinted,.sortedKeys])
    .write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
print("\(failed ? "FAIL" : "PASS"): \(totalFrames) full native character motor/query/core frames; 1 cm position, 0.1 m/s rising, exact state gate")
if failed { exit(1) }
