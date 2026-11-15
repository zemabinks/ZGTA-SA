import Foundation

/// Movement tasks share one physical facing. An inactive locomotion cache
/// must adopt that facing before it can write the character again.
/// No angle interpolation or model-facing offset is applied here.
final class NativeHeadingContinuity {
    enum Owner:String {case foot,jetpack,parachute,swimming,climbing}
    private(set) var owner:Owner = .foot
    private(set) var handoffs=0

    static func difference(_ to:Double,from:Double)->Double {
        atan2(sin(to-from),cos(to-from))
    }
    static func canonical(_ heading:Double)->Double {
        atan2(sin(heading),cos(heading))
    }
    static func inputFacing(camera:Double,sideways:Double,forward:Double)->Double {
        guard camera.isFinite,sideways.isFinite,forward.isFinite else{return camera.isFinite ? canonical(camera):0}
        return canonical(camera+atan2(sideways,forward))
    }
    /// The external task owns facing until the foot task resumes, including
    /// the final tick whose flight/swim motion result can already be nil.
    func external(_ owner:Owner) {
        precondition(owner != .foot)
        self.owner=owner
    }
    /// Reset also discards pre-flight gait/strafe input. New foot input is
    /// consumed normally afterwards, rather than replaying suspended input.
    @discardableResult
    func resumeFoot(facing:Double,locomotion:NativeFootLocomotion)->Bool {
        guard owner != .foot,facing.isFinite else{return false}
        locomotion.reset(heading:Self.canonical(facing))
        owner = .foot;handoffs += 1
        return true
    }
    /// Explicit relocation or model replacement also starts a new task frame.
    func reset(facing:Double,locomotion:NativeFootLocomotion) {
        guard facing.isFinite else{return}
        locomotion.reset(heading:Self.canonical(facing));owner = .foot
    }
}
