import Foundation

/// Separate starting a new attack from delivering its committed animation
/// marker. Public9737 gates new intent on busy/stunned/rolling/air state, but
/// does not erase every committed marker merely because a pose became busy.
/// Inventory, actual target geometry and server authority remain independent.
enum NativeCombatEligibility {
    struct Context {
        var alive = true
        /// Another movement/task owns the hands: vehicle, swim, climb,
        /// parachute, boarding or an equivalent explicit input owner.
        var blocked = false
        var airborne = false
        var busy = false
        var stunned = false
        var rolling = false
        var flying = false
        var arm = false
        var requiresAim = false
        var aimHeld = false
        var ready = true
        var reloading = false

        private var ownsHands: Bool { alive && !blocked && (!flying || arm) }
        var canAim: Bool { ownsHands && (!airborne || flying) && !busy }
        var canRequestFire: Bool {
            canAim && !stunned && !rolling && ready && !reloading && (!requiresAim || aimHeld)
        }
        var canEmitShot: Bool { ownsHands && !stunned && ready && !reloading }
        /// Stun suppresses raw held input as well as rising-edge requests.
        func heldTrigger(_ held: Bool) -> Bool { held && ownsHands && !stunned }
    }
}
