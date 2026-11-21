// SPDX-License-Identifier: AGPL-3.0-only
// Authored motor/query boundaries; the complete coordinator and renderer getters
// are actual source. This is display timing, not collision or retail validation.
import Foundation
import simd

final class SwiftRapierWorld {
    var legacyGravityAcceleration: Double?
    var steps = 0
    func step() { steps += 1 }
    static func gtaToRapier(_ p: SIMD3<Float>) -> SIMD3<Float> { SIMD3(p.x, p.z, -p.y) }
    static func rapierToGTA(_ p: SIMD3<Float>) -> SIMD3<Float> { SIMD3(p.x, -p.z, p.y) }
}
final class NativeRapierCharacterQueries {
    let walker: UInt64 = 1, probe: UInt64 = 2
    var translation = SIMD3<Double>.zero
    init?(world: SwiftRapierWorld) {}
    func setTranslation(_ body: UInt64, _ p: SIMD3<Double>) { translation = p }
}
final class NativeCharacterMotor {
    struct Press {}
    var otherColliders: Set<UInt64> = []
    var grounded = false, propped = false
    var rising = 0.0, gravityAcceleration = 20.0
    var pressed: [Press] = []
    private var oldEasing = 0.0, newEasing = 0.0
    init(world: NativeRapierCharacterQueries) {}
    func setActive(_ active: Bool) { resetMotion() }
    func stand() { grounded = true }
    func clearContactEvents() { pressed = [] }
    func resetMotion() { rising = 0; oldEasing = 0; newEasing = 0 }
    func eased(_ alpha: Double = 1) -> Double { oldEasing + (newEasing - oldEasing) * alpha }
    func setEasing(previous: Double, current: Double) { oldEasing = previous; newEasing = current }
    func step(position: inout SIMD3<Double>, displacement: SIMD3<Double>, jump: Double,
              delta: Double, held: Bool, verticalOverride: Double?, carrying: UInt64?) {
        position += displacement
        if let verticalOverride { rising = verticalOverride; position.y += verticalOverride * delta }
    }
}
final class SwimBoundary { var hauled: SIMD3<Double>? }
final class RendererBoundary {
    var camera = SIMD3<Float>.zero
    var character: NativeCharacterController?
    var characterActive = true, driving = false, legacySpectating = false
    var climb: Int?
    var weaponEventFeet: SIMD3<Float>?
    let swimController = SwimBoundary()
    // ACTUAL_RENDERER_GETTERS
    var displayed: SIMD3<Float> { footPresentationPosition }
}
var checks = 0
func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    checks += 1
    if !condition() { fatalError(message) }
}
func close(_ a: SIMD3<Float>, _ b: SIMD3<Float>, tolerance: Float = 0.0002) -> Bool {
    simd_distance(a, b) <= tolerance
}
let start = SIMD3<Float>(10, -20, 4), velocity = SIMD3<Float>(3, 2, 0)
var maximumIncrementError: Float = 0
for rate in [120, 144, 30, 60, 75] {
    let world = SwiftRapierWorld(), character = NativeCharacterController(world: world)!
    let renderer = RendererBoundary(); renderer.character = character
    character.reset(feet: start, grounded: true)
    var previousDisplay = start
    for frame in 0..<(rate * 2) {
        let delta = 1 / Double(rate)
        let state = character.update(delta: delta, displacement: velocity / Float(rate), geometryReady: true)
        renderer.camera = state.feet
        let display = renderer.displayed
        if frame > 3 {
            let error = simd_distance(display - previousDisplay, velocity / Float(rate))
            maximumIncrementError = max(maximumIncrementError, error)
            require(error < 0.0002, "High-refresh display repeats committed physics snapshots")
            require(close(display, start + velocity * Float(Double(frame + 1) / Double(rate) - 1/60.0)),
                    "Display time does not follow the fixed-step interpolation boundary")
        }
        let count = world.steps, physical = character.state.feet, speed = character.stepVelocity
        for _ in 0..<5 { _ = character.presentationFeet; _ = renderer.displayed }
        require(world.steps == count && character.state.feet == physical && character.stepVelocity == speed,
                "A presentation query advanced or changed authoritative motion")
        require(renderer.position == physical && renderer.shotFeet == physical,
                "Visual interpolation replaced network or animation-marker feet")
        renderer.weaponEventFeet = physical + SIMD3(1, 2, 3)
        require(renderer.shotFeet == renderer.weaponEventFeet!, "Display root replaced a fixed-tick shot marker")
        renderer.weaponEventFeet = nil
        previousDisplay = display
    }
    require(close(character.state.feet, start + velocity * 2), "Display cadence changed physical endpoints")
    require(world.steps == 120, "Display rate changed the fixed motor tick count")
}
let world = SwiftRapierWorld(), character = NativeCharacterController(world: world)!
let renderer = RendererBoundary(); renderer.character = character
character.reset(feet: start, grounded: true)
_ = character.update(delta: 1/60, displacement: SIMD3(0.1, 0, 0), geometryReady: true)
_ = character.update(delta: 1/120, displacement: .zero, geometryReady: true)
renderer.camera = character.state.feet
character.motor.setEasing(previous: -0.4, current: -0.2)
require(abs(character.presentationFeet.z - (character.state.feet.z - 0.3)) < 0.00001,
        "Step easing used a different fraction from head interpolation")
let displayed = character.presentationFeet
character.cancelPendingInput()
require(character.presentationFeet == displayed, "Input cancellation reset display history")
for delta in [0.0, Double.nan, 0.75] {
    _ = character.update(delta: delta, displacement: SIMD3(20, 0, 0), geometryReady: true)
    require(close(character.presentationFeet, character.state.feet + SIMD3(0, 0, Float(character.state.eased))),
            "Clock discontinuity reused an unrelated display interval")
}
let destination = SIMD3<Float>(200, -300, 12)
character.reset(feet: destination, grounded: true); renderer.camera = character.state.feet
require(character.presentationFeet == destination, "Teleport blended from the previous world position")
_ = character.update(delta: 1/120, displacement: .zero, geometryReady: true)
renderer.camera = character.state.feet
require(character.presentationFeet == destination, "Teleport left stale half-tick presentation")
character.supportFeet = SIMD3(210, -301, 15)
require(renderer.displayed == character.supportFeet!, "Moving support received duplicate root interpolation")
character.supportFeet = nil
for owner in ["vehicle", "spectator", "climb", "haul", "inactive"] {
    renderer.camera = SIMD3(500, 600, 20)
    switch owner {
    case "vehicle": renderer.driving = true
    case "spectator": renderer.legacySpectating = true
    case "climb": renderer.climb = 1
    case "haul": renderer.swimController.hauled = SIMD3(1, 2, 3)
    default: renderer.characterActive = false
    }
    require(renderer.displayed == renderer.camera, "Presentation escaped special owner: \(owner)")
    renderer.driving = false; renderer.legacySpectating = false; renderer.climb = nil
    renderer.swimController.hauled = nil; renderer.characterActive = true
}
let anchor = SIMD3<Float>(40, -30, 8)
let held = character.update(delta: 1/60, displacement: .zero, geometryReady: true, motion: { _, _, input in
    var result = input; result.heldFeet = anchor; return result
})
require(held.feet == anchor && character.presentationFeet == anchor, "Animation-owned held root was interpolated away from its anchor")
character.setActive(false)
require(character.presentationFeet == character.state.feet, "Inactive controller kept an old visual interval")
print("PASS actual fixed coordinator/display publication: \(checks) checks, 30/60/75/120/144Hz, maximum increment error \(maximumIncrementError)m; authored motor boundary, no collision/UI/retail claim")
