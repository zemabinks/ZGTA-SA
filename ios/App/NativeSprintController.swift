import Foundation

/// Public module 34719's shared foot/bike/water sprint counter. Durations are
/// supplied in the original 50-Hz units, independent of display refresh rate.
final class NativeSprintController {
    enum Mode { case foot, bike, water, underwater }
    struct Profile {
        var press: Double = 4
        var held: Double = 0.7
        var loose: Double = 0.2
        var over: Double = 5
        var most: Double = 10
        var costHeld: Double = 1
        var costTapped: Double = 0.5
        var gain: Double = 0.3
        var hook = true
        static func forMode(_ mode: Mode) -> Profile {
            var profile = Profile()
            switch mode {
            case .foot: break
            case .bike: profile.costHeld = 0; profile.costTapped = 0.4; profile.gain = 1; profile.hook = false
            case .water: profile.costTapped = 0.3
            case .underwater: profile.costHeld = 0; profile.costTapped = 0; profile.gain = 1
            }
            return profile
        }
    }
    private(set) var counter: Double = 0
    private var remaining: Double = 0
    private var heldFor: Double = -1
    func reset() { counter = 0; remaining = 0; heldFor = -1 }
    func control(_ profile: Profile,ticks: Double,tapped: Bool,held: Bool,
                 staminaLeft: Double,take: (Double) -> Bool) -> Double {
        let available = counter > 0 || staminaLeft > 0
        let elapsed = max(0,ticks-remaining)
        remaining = max(0,remaining-ticks)
        let previousHeld = heldFor
        heldFor = tapped ? 0 : held ? (heldFor >= 0 ? heldFor+ticks : 0) : -1
        let hooked = profile.hook && heldFor > 10
        if tapped && available {
            counter = min(profile.most,counter+profile.press);remaining = max(0,2-ticks)
        } else if held && available {
            counter = hooked ? min(profile.most,max(1,counter)+ticks) : max(1,counter-elapsed*profile.held)
        } else {
            if profile.hook && !held && previousHeld > 10 { counter = min(counter,1) }
            if counter > 0 { counter = max(0,counter-elapsed*profile.loose) }
        }
        let tappedPace = counter > profile.over
        guard tappedPace || (counter > 0 && available) else { return 0 }
        guard take(ticks*(tappedPace ? profile.costTapped : profile.costHeld)) else { counter = 0;return 0 }
        return 1+(tappedPace ? (counter/profile.over-1)*profile.gain : 0)
    }
    func result(_ profile: Profile) -> Double {
        counter > profile.over ? 1+(counter/profile.over-1)*profile.gain : counter > 0 ? 1 : 0
    }
}

/// Stamina/breath budget used by the public on-foot controller. Swimming's
/// oxygen timer is separate; this budget governs sprint effort and recovery.
struct NativeStamina {
    private(set) var value: Double = 150
    var tireless = false
    var laden = false
    var left: Double { value+90 }
    mutating func take(_ amount: Double) -> Bool {
        if amount <= 0 { return true }
        if laden { return false }
        if tireless { return true }
        guard value > -150 else { return false }
        value = max(-150,value-amount/3);return true
    }
    mutating func rest(_ amount: Double) { value = min(150,value+amount) }
    /// Public pedestrian swim steering restores a nonpositive effort budget
    /// before underwater sprint control. Underwater effort itself costs zero;
    /// retaining an exhausted foot budget would suppress its input response.
    mutating func prepareUnderwater() { if value <= 0 { value = 0.1 } }
    /// The pedestrian's common recovery path also runs during ordinary air
    /// motion and parachuting. The caller decides whether sprint effort owns
    /// this tick; a parachute uses the source's cleared locomotion ratio zero.
    mutating func restForLocomotion(ticks: Double, ratio: Double) {
        guard ticks.isFinite, ticks > 0, ratio.isFinite else { return }
        rest(ticks * (ratio > 1 ? 0.15 : 0.5))
    }
    mutating func reset() { value = 150 }
}
