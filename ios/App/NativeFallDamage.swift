import Foundation

/// Archived main19737 regular-foot landing policy. Inputs are downward peak
/// and previous task-requested horizontal speed in world units/s. This is a
/// browser compatibility policy, not a measured retail damage calibration.
enum NativeFallDamage {
    static func amount(fastest:Double,horizontal:Double) -> Double {
        guard fastest.isFinite,horizontal.isFinite,fastest>=0,horizontal>=0,
              fastest>18.75 || horizontal>33 else {return 0}
        if fastest>30 {return 165}
        return 2.64*max(0,fastest-12.5)+0.66*max(0,horizontal-12.5)
    }

    /// The native/server health boundary is integral. Round the resulting
    /// health as the server does; fall damage bypasses armour entirely.
    static func health(after damage:Double,current:Int) -> Int {
        guard damage.isFinite,damage>0,current>0 else {return current}
        let remaining=Double(current)-damage
        // The source hurt path enters death below one health before its
        // integral network presentation; rounding must not revive that result.
        guard remaining>=1 else {return 0}
        return Int(remaining.rounded())
    }
}
