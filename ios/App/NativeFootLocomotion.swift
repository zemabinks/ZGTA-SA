import Foundation
import simd

/// The public 9737 on-foot controller's input acceleration and facing rules.
/// Headings at this boundary use the native protocol: zero +Y, positive +X.
/// Browser headings have the opposite sign; root travel is GTA side/forward.
final class NativeFootLocomotion {
    struct Input {
        var stick = SIMD2<Double>.zero
        var cameraHeading: Double = 0
        var aiming = false
        var crouching = false
        var guardStance = false
        var gunUp = false
        var armAim = false
        var movingAim = true
        var movingFire = true
        var gunShooting = false
        var attackHeld = false
        var isGun = true
        var hipFire = false
        var poise = false
        var busy = false
        var stunned = false
        var rolling = false
        var swinging = false
        var air = false
        var turningRate: Double = 6.5
        var throwing = false
        var heavy = false
    }
    struct Frame { var ratio: Double; var strafe: SIMD2<Double>?; var heading: Double; var pushing: Bool }
    private var requestedRatio: Double = 0
    private var remainder: Double = 0
    private var smoothedRatio: Double = 0
    private var easedStrafe = SIMD2<Double>.zero
    private var wholeBodyAim = false
    private var wantedHeading: Double = 0
    var heading: Double = 0
    var requestedMovementRatio: Double { requestedRatio }
    var reportedRatio: Double { wholeBodyAim ? min(1,simd_length(easedStrafe)) : smoothedRatio }
    func reset(heading: Double) {
        self.heading = heading; requestedRatio = 0; remainder = 0; smoothedRatio = 0
        wantedHeading = heading
        easedStrafe = .zero; wholeBodyAim = false
    }
    func update(delta dt: Double,input: Input) -> Frame {
        let wasWholeBodyAim = wholeBodyAim
        wholeBodyAim = input.gunUp && !input.armAim && !input.crouching
        let hasInput = simd_length(input.stick) > 0
        if wasWholeBodyAim && !wholeBodyAim { requestedRatio = hasInput ? 1 : 0; smoothedRatio = requestedRatio }
        let crouchedAim = input.crouching && input.aiming
        let push = min(1,crouchedAim ? abs(input.stick.y) : simd_length(input.stick))
        let forbidden = input.busy || input.stunned || input.rolling || input.swinging ||
            (input.gunUp && input.isGun && !input.movingFire && input.gunShooting) ||
            (crouchedAim && input.isGun && input.attackHeld) || (input.aiming && input.isGun && !input.movingAim)
        var target: Double = forbidden ? 0 : push * (128.0 / 60)
        let freeArm = input.aiming && input.armAim && !input.crouching
        if (input.aiming && !freeArm) || input.crouching || input.guardStance { target = min(1,target) }
        var wanted = wantedHeading
        if !wholeBodyAim {
            if input.stunned { requestedRatio = max(0,requestedRatio - 7 * dt) }
            else if target <= 0 { remainder = max(0,max(remainder,requestedRatio) - 1.75 * dt); requestedRatio = 0 }
            else {
                wanted = wrap(input.cameraHeading + atan2(input.stick.x,input.stick.y))
                if requestedRatio <= 0 { requestedRatio = min(target,max(0.4,remainder)) }
                remainder = 0; requestedRatio += min(3.5 * dt,max(-3.5 * dt,target-requestedRatio))
            }
        }
        if input.swinging && push > 0 { wanted = wrap(input.cameraHeading + atan2(input.stick.x,input.stick.y)) }
        let hipArm = input.hipFire && input.armAim
        if input.guardStance || input.poise || input.throwing || (input.aiming && !hipArm && (!freeArm || target <= 0)) { wanted = input.cameraHeading }
        wantedHeading = wanted
        let denominator = target > 0 ? max(1,simd_length(input.stick)) : .infinity
        let normal = input.stick / denominator
        if wholeBodyAim {
            let step = 3.5 * dt
            if input.stunned {
                for i in 0..<2 { easedStrafe[i] -= min(step,max(-step,easedStrafe[i])) }
            } else if target <= 0 { easedStrafe = .zero }
            else { for i in 0..<2 { easedStrafe[i] += min(step,max(-step,normal[i]-easedStrafe[i])) } }
        } else { easedStrafe = .zero }
        if !input.air {
            if input.guardStance || input.poise || input.throwing || (input.aiming && !input.hipFire && (!freeArm || requestedRatio == 0)) { heading = wanted }
            else if (requestedRatio > 0 && !wholeBodyAim) || (input.swinging && push > 0) || (input.aiming && input.hipFire && !hipArm) {
                heading = wrap(heading + min(input.turningRate * dt,max(-input.turningRate * dt,wrap(wanted-heading))))
            }
        }
        smoothedRatio += min(6 * dt,max(-6 * dt,requestedRatio-smoothedRatio))
        return Frame(ratio:smoothedRatio,strafe:input.aiming && !freeArm || input.guardStance ? (wholeBodyAim ? easedStrafe : normal) : nil,heading:heading,pushing:push > 0)
    }
    static func worldTravel(_ travel: SIMD2<Double>,heading: Double) -> SIMD3<Float> {
        SIMD3(Float(cos(heading)*travel.x+sin(heading)*travel.y),Float(-sin(heading)*travel.x+cos(heading)*travel.y),0)
    }
    private func wrap(_ angle: Double) -> Double { let value=(angle+Double.pi).truncatingRemainder(dividingBy:2*Double.pi);return (value < 0 ? value+2*Double.pi : value)-Double.pi }
}
