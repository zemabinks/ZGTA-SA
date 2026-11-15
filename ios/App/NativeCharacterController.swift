import Foundation
import simd

/// Coordinates the literal browser on-foot motor with native Rapier queries.
/// Cell streaming belongs to the shared world owner; only this coordinator
/// steps that world while the player is on foot.
final class NativeCharacterController {
    struct Output {
        let feet: SIMD3<Float>
        let grounded: Bool
        let rising: Double
        let eased: Double
        let propped: Bool
        let pressed: [NativeCharacterMotor.Press]
    }
    struct Motion {
        var displacement: SIMD3<Float>
        var jump: Double = 0
        var held = false
        var verticalOverride: Double? = nil
        var heldFeet: SIMD3<Float>? = nil
    }
    let world: SwiftRapierWorld
    let queries: NativeRapierCharacterQueries
    let motor: NativeCharacterMotor
    private var head = SIMD3<Double>.zero
    private var accumulator = 0.0
    private var pendingTravel = SIMD3<Double>.zero
    private var pendingJump = 0.0
    private var active = false
    private static let fixed = 1.0 / 60.0

    init?(world: SwiftRapierWorld) {
        guard let queries = NativeRapierCharacterQueries(world: world) else { return nil }
        self.world = world; self.queries = queries
        motor = NativeCharacterMotor(world: queries)
    }
    var otherColliders: Set<UInt64> {
        get { motor.otherColliders }
        set { motor.otherColliders = newValue }
    }
    /// Resets pending movement for teleports and transitions into/out of cars.
    func reset(feet: SIMD3<Float>, active: Bool = true, grounded: Bool = false) {
        let p = SwiftRapierWorld.gtaToRapier(feet)
        head = SIMD3(Double(p.x), Double(p.y) + 1.7, Double(p.z))
        accumulator = 0; pendingTravel = .zero; pendingJump = 0
        self.active = active; motor.setActive(active)
        queries.setTranslation(queries.walker, head - SIMD3(0,0.8,0))
        if grounded { motor.stand() }
    }
    func setActive(_ active: Bool) {
        self.active = active; accumulator = 0; pendingTravel = .zero; pendingJump = 0
        motor.setActive(active)
    }
    var state: Output {
        let p = SIMD3<Float>(Float(head.x), Float(head.y - 1.7), Float(head.z))
        return Output(feet: SwiftRapierWorld.rapierToGTA(p), grounded: motor.grounded,
                      rising: motor.rising, eased: motor.eased(), propped: motor.propped, pressed: motor.pressed)
    }
    /// Displacement is the intended horizontal GTA-world travel for this frame.
    /// No movement/physics tick is performed until required collision cells exist.
    @discardableResult
    func update(delta: Double, displacement: SIMD3<Float>, jump: Double = 0,
                held: Bool = false, verticalOverride: Double? = nil, carrying: UInt64? = nil,
                geometryReady: Bool,
                motion: ((Double,Output,Motion) -> Motion)? = nil) -> Output {
        guard active, delta.isFinite, delta > 0, displacement.x.isFinite,
              displacement.y.isFinite, displacement.z.isFinite else { return state }
        guard geometryReady else {
            accumulator = 0; pendingTravel = .zero; pendingJump = 0; return state
        }
        let dt = min(delta, 0.1), scale = dt / delta
        let p = SwiftRapierWorld.gtaToRapier(displacement)
        pendingTravel += SIMD3(Double(p.x),0,Double(p.z)) * scale
        accumulator += dt
        if jump.isFinite, jump > 0 { pendingJump = jump }
        while accumulator + 1e-10 >= Self.fixed {
            let travel = pendingTravel * (Self.fixed / accumulator)
            pendingTravel -= travel; accumulator = max(0, accumulator - Self.fixed)
            let intended = Motion(displacement: SwiftRapierWorld.rapierToGTA(SIMD3<Float>(travel)),
                                  jump: pendingJump,held: held,verticalOverride: verticalOverride)
            let input = motion?(Self.fixed,state,intended) ?? intended
            if let feet = input.heldFeet {
                let point = SwiftRapierWorld.gtaToRapier(feet)
                head = SIMD3(Double(point.x),Double(point.y)+1.7,Double(point.z))
            } else {
                let point = SwiftRapierWorld.gtaToRapier(input.displacement)
                motor.step(position: &head, displacement: SIMD3<Double>(point), jump: input.jump, delta: Self.fixed,
                           held: input.held, verticalOverride: input.verticalOverride, carrying: carrying)
            }
            pendingJump = 0
            world.step()
        }
        return state
    }
}
