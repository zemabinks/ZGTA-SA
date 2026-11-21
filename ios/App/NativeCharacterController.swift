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
    struct SupportMotion {
        var displacement=SIMD3<Double>.zero
        var body:UInt64?
        var yaw=0.0
        var thrown:SIMD3<Double>?
    }
    var carrySupport:((Double,NativeCharacterMotor,inout SIMD3<Double>)->SupportMotion)?
    var settleSupport:((Double,NativeCharacterMotor,inout SIMD3<Double>,Motion)->Void)?
    var resetSupport:(()->Void)?
    var onSupportMotion:((Double,SIMD3<Double>?)->Void)?
    var afterSupportUpdate:(()->Void)?
    var supportAfloat=false
    var supportFeet:SIMD3<Float>?
    let world: SwiftRapierWorld
    let queries: NativeRapierCharacterQueries
    let motor: NativeCharacterMotor
    private var head = SIMD3<Double>.zero
    private var presentation = NativeFootPresentation()
    private var accumulator = 0.0
    private var pendingTravel = SIMD3<Double>.zero
    private var pendingJump = 0.0
    private var active = false
    private var rootHeld = false
    /// Last committed fixed-step velocity, in Rapier axes and world units/s.
    /// Retain it between display frames that do not advance the motor.
    private(set) var stepVelocity = SIMD3<Double>.zero
    /// Observable motion is unavailable while this owner is inactive, its
    /// clock is suspended or the required collision cells are missing. Keep
    /// the committed velocity separately for subsequent physical handoffs.
    private(set) var movementAvailable = false
    var currentVelocity: SIMD3<Double> { movementAvailable ? stepVelocity : .zero }
    /// Original walker press routing occurs after motor motion and before
    /// CQ.beforeStep applies the queued impulse to promoted parked vehicles.
    var onPress:(([NativeCharacterMotor.Press])->Void)?
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
        guard Self.finite(feet) else { return }
        let p = SwiftRapierWorld.gtaToRapier(feet)
        head = SIMD3(Double(p.x), Double(p.y) + 1.7, Double(p.z))
        clearPendingMotion(); rootHeld = false; stepVelocity = .zero; movementAvailable = false
        resetSupport?()
        supportAfloat=false;supportFeet=nil
        self.active = active; motor.setActive(active)
        queries.setTranslation(queries.walker, head - SIMD3(0,0.8,0))
        if grounded { motor.stand() }
    }
    func setActive(_ active: Bool) {
        self.active = active; clearPendingMotion(); rootHeld = false; stepVelocity = .zero; movementAvailable = false
        motor.setActive(active)
        resetSupport?()
        supportAfloat=false;supportFeet=nil
    }
    private static func finite(_ p: SIMD3<Float>) -> Bool { p.x.isFinite && p.y.isFinite && p.z.isFinite }
    private func clearPendingMotion() {
        accumulator = 0; pendingTravel = .zero; pendingJump = 0
        presentation.reset(head: head)
    }
    /// Input loss discards unconsumed commands, preserving the fixed clock,
    /// committed velocity, airborne momentum and animation-owned root.
    func cancelPendingInput() { pendingTravel = .zero; pendingJump = 0 }
    var state: Output {
        let p = SIMD3<Float>(Float(head.x), Float(head.y - 1.7), Float(head.z))
        return Output(feet: SwiftRapierWorld.rapierToGTA(p), grounded: motor.grounded,
                      rising: motor.rising, eased: motor.eased(), propped: motor.propped, pressed: motor.pressed)
    }
    var presentationAlpha: Double {
        NativeFootPresentation.fraction(remainder: accumulator, step: Self.fixed,
                                        available: movementAvailable && !rootHeld)
    }
    /// Visual interpolation is separate from state, contact, velocity and wire
    /// publication. Moving supports can provide their own rendered anchor.
    var presentationFeet: SIMD3<Float> {
        let alpha = presentationAlpha
        let point = presentation.head(alpha: alpha, easing: motor.eased(alpha))
        return SwiftRapierWorld.rapierToGTA(SIMD3(Float(point.x), Float(point.y - 1.7), Float(point.z)))
    }
    /// Displacement is the intended horizontal GTA-world travel for this frame.
    /// No movement/physics tick is performed until required collision cells exist.
    @discardableResult
    func update(delta: Double, displacement: SIMD3<Float>, jump: Double = 0,
                held: Bool = false, verticalOverride: Double? = nil, carrying: UInt64? = nil,
                geometryReady: Bool,
                motion: ((Double,Output,Motion) -> Motion)? = nil) -> Output {
        // Presentation follows live vehicle poses even on display frames
        // that do not advance the fixed motor clock.
        defer {afterSupportUpdate?()}
        movementAvailable = false
        guard active else { return state }
        // Match the outer frame clock: retain ordinary low-FPS elapsed time,
        // but treat a suspension/invalid clock sample as a discontinuity.
        // At most 30 fixed ticks can run; no old displacement/jump is replayed.
        guard delta.isFinite, delta > 0, delta <= 0.5, Self.finite(displacement) else {
            clearPendingMotion(); motor.clearContactEvents(); return state
        }
        guard geometryReady else {
            clearPendingMotion(); motor.clearContactEvents(); return state
        }
        // A normal high-refresh frame can have no motor tick. Its last
        // committed speed is still the current available physical snapshot.
        movementAvailable = true
        let p = SwiftRapierWorld.gtaToRapier(displacement)
        pendingTravel += SIMD3(Double(p.x),0,Double(p.z))
        accumulator += delta
        if jump.isFinite, jump > 0 { pendingJump = jump }
        while accumulator + 1e-10 >= Self.fixed {
            let previousFeet = state.feet
            let travel = pendingTravel * (Self.fixed / accumulator)
            pendingTravel -= travel; accumulator = max(0, accumulator - Self.fixed)
            let supported=carrySupport?(Self.fixed,motor,&head) ?? SupportMotion()
            onSupportMotion?(supported.yaw,supported.thrown)
            let intended = Motion(displacement: SwiftRapierWorld.rapierToGTA(SIMD3<Float>(travel)),
                                  jump: pendingJump,held: held,verticalOverride: verticalOverride)
            let input = motion?(Self.fixed,state,intended) ?? intended
            guard Self.finite(input.displacement), input.jump.isFinite,
                  input.verticalOverride?.isFinite != false,
                  input.heldFeet.map(Self.finite) != false else {
                pendingJump = 0; stepVelocity = .zero; movementAvailable = false
                motor.clearContactEvents(); world.step(); presentation.reset(head: head); continue
            }
            if let feet = input.heldFeet {
                // Animation roots own translation while hanging/hauling. A
                // stale walking contact/fall is not a velocity for that task.
                if !rootHeld { motor.resetMotion() }
                rootHeld = true
                let point = SwiftRapierWorld.gtaToRapier(feet)
                head = SIMD3(Double(point.x),Double(point.y)+1.7,Double(point.z))
                // A climb/attachment can place the actor without running the
                // walking motor. Keep its enabled contact capsule at that
                // same location before the shared rigid-body world advances.
                queries.setTranslation(queries.walker, head - SIMD3(0,0.8,0))
            } else {
                rootHeld = false
                motor.gravityAcceleration=world.legacyGravityAcceleration ?? 20
                let point = SwiftRapierWorld.gtaToRapier(input.displacement)
                motor.step(position: &head, displacement: SIMD3<Double>(point)+supported.displacement, jump: input.jump, delta: Self.fixed,
                           held: input.held, verticalOverride: input.verticalOverride, carrying: carrying ?? supported.body)
            }
            pendingJump = 0
            if input.heldFeet == nil {onPress?(motor.pressed)}
            settleSupport?(Self.fixed,motor,&head,input)
            if settleSupport != nil {queries.setTranslation(queries.walker,head-SIMD3(0,0.8,0))}
            world.step()
            presentation.commit(head: head, held: rootHeld)
            // Use the same published Float feet boundary as the renderer's
            // prior 60-Hz measurement, with the tick that actually moved it.
            stepVelocity = SIMD3<Double>(SwiftRapierWorld.gtaToRapier((state.feet-previousFeet)/Float(Self.fixed)))
            movementAvailable = true
        }
        return state
    }
}

/// Display history for a fixed-step character. Queries never advance physics
/// or consume input; committed positions remain owned by the motor.
private struct NativeFootPresentation {
    private var previous = SIMD3<Double>.zero
    private var current = SIMD3<Double>.zero

    mutating func reset(head: SIMD3<Double>) {
        previous = head
        current = head
    }

    mutating func commit(head: SIMD3<Double>, held: Bool) {
        previous = held ? head : current
        current = head
    }

    static func fraction(remainder: Double, step: Double, available: Bool) -> Double {
        guard available, remainder.isFinite, step.isFinite, step > 0 else { return 1 }
        return min(1, max(0, remainder / step))
    }

    /// The motor's vertical step easing uses the same interpolation fraction.
    /// Head coordinates use Rapier's Y-up convention; feet conversion belongs
    /// to the character coordinator.
    func head(alpha: Double, easing: Double) -> SIMD3<Double> {
        let share = alpha.isFinite ? min(1, max(0, alpha)) : 1
        var point = previous + (current - previous) * share
        point.y += easing.isFinite ? easing : 0
        return point
    }
}
