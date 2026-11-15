import Foundation

/// One synchronous owner connects a reserved network sequence to the predicted
/// muzzle event. Readiness is published before the next hand/fixed substep.
enum NativeWeaponShotDelivery {
    @discardableResult static func deliver(weapon: Int, left: Bool, ticket: NativeShotTicket,
        inventory: NativeWeaponState, readiness: (Bool) -> Void,
        emission: (Int, Bool, NativeShotTicket) -> Void) -> Bool {
        let accepted = inventory.consumeAnimationShot(weapon: weapon, ticket: ticket)
        readiness(inventory.canFire)
        guard accepted else { return false }
        emission(weapon, left, ticket)
        return true
    }
    /// Explicit offline legacy tests only. Production state refuses to predict
    /// without a negotiated connection and a preallocated ticket.
    @discardableResult static func deliver(weapon: Int, left: Bool, inventory: NativeWeaponState,
        readiness: (Bool) -> Void, emission: (Int, Bool) -> Void) -> Bool {
        let accepted = inventory.consumeAnimationShot(weapon: weapon)
        readiness(inventory.canFire)
        guard accepted else { return false }
        emission(weapon, left)
        return true
    }
}
