// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Semantic input to the real SA-MP controls, independent of device bindings.
/// Source: https://open.mp/docs/scripting/resources/keys and official core.hpp /
/// vehicle.hpp wire bitfields. Analog axes are signed128, not keymask bits.
enum NativeSAMPInput {
    struct State {
        var enabled = true, driving = false
        var sideways: Float = 0, forward: Float = 0, steering: Float = 0, pitch: Float = 0
        var throttle: Float = 0, brake: Float = 0
        var crouch = false, fire = false, sprint = false, enterExit = false, jump = false
        var aim = false, handbrake = false, horn = false, action = false, walk = false
        var look: String?
        var turretHorizontal: Float = 0, turretVertical: Float = 0
        var special: UInt8 = 0
    }
    struct Frame: Equatable {
        var keys: UInt16 = 0, leftRight: Int16 = 0, upDown: Int16 = 0, special: UInt8 = 0
    }
    static func axis(_ value: Float) -> Int16 {
        guard value.isFinite else { return 0 }
        return Int16((min(1, max(-1, value)) * 128).rounded())
    }
    static func encode(_ state: State) -> Frame {
        guard state.enabled else { return Frame() }
        var frame = Frame()
        func set(_ mask: UInt16, _ held: Bool) { if held { frame.keys |= mask } }
        frame.leftRight = axis(state.driving ? state.steering:state.sideways)
        frame.upDown = axis(-(state.driving ? state.pitch:state.forward))
        frame.special = state.special <= 3 ? state.special:0
        set(1, state.action)
        set(2, state.driving ? state.horn:state.crouch)
        set(4, state.fire)
        set(8, state.driving ? state.throttle.isFinite && state.throttle > 0.05:state.sprint)
        set(16, state.enterExit)
        set(32, state.driving ? state.brake.isFinite && state.brake > 0.05:state.jump)
        set(128, state.driving ? state.handbrake:state.aim)
        set(512, state.look == "behind")
        if state.driving {
            set(64, state.look == "right"); set(256, state.look == "left")
        } else { set(1024, state.walk) }
        set(2048, state.turretVertical.isFinite && state.turretVertical > 0.05)
        set(4096, state.turretVertical.isFinite && state.turretVertical < -0.05)
        set(8192, state.turretHorizontal.isFinite && state.turretHorizontal < -0.05)
        set(16384, state.turretHorizontal.isFinite && state.turretHorizontal > 0.05)
        return frame
    }
    static func specialKey(heldHID: Set<Int>) -> UInt8 {
        // Y/N/H are additional-key values in the weapon byte's high2 bits.
        if heldHID.contains(28) { return 1 }
        if heldHID.contains(17) { return 2 }
        if heldHID.contains(11) { return 3 }
        return 0
    }
}
