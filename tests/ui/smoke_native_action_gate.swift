import Foundation

// Authored UI/renderer boundaries record requests; they implement no gameplay.
struct UIColor {
    static let black = UIColor(), white = UIColor()
    init() {}
    init(red: Double, green: Double, blue: Double, alpha: Double) {}
    func withAlphaComponent(_ value: Double) -> UIColor { self }
    var cgColor: Int { 0 }
}
final class Layer { var borderColor = 0; var borderWidth = 1.0 }
final class Button { let layer = Layer(); var backgroundColor = UIColor() }
final class View { var window: Int? = 1 }
final class Network { var isReady = true; var originalInputBlocked = false; var health = 100.0 }
final class Radio { var requests = 0; func next() { requests += 1 } }
final class Renderer {
    var originalCoughing = false, canNativeFootMeleeGuard = false
    var hasLandingGear = true, canUnhitchVehicle = false, crouching = false, vehicleLights = false
    var jumps = 0, gears = 0, crouches = 0, releases = 0
    func jump() { jumps += 1 }
    func toggleLandingGear() { gears += 1 }
    func toggleCrouch() { crouches += 1; crouching.toggle() }
    func releaseVehicleCoupling() { releases += 1 }
}
struct Context { var melee = false, guarding = false }
struct Axis { var value: Float = 0 }
struct Stick { var xAxis = Axis(), yAxis = Axis() }
struct Pad {
    var leftThumbstick = Stick(), rightThumbstick = Stick(), leftTrigger = Axis(), rightTrigger = Axis()
}
final class Harness {
    var applicationActive = true, legacySelection = false
    var viewIfLoaded: View? = View(), presentedViewController: Int?
    let network = Network(), radio = Radio()
    var renderer: Renderer? = Renderer(), currentVehicle: Int?
    var run = false, touchMeleeGuard = false, usingMelee = false, aiming = false
    var legacyCrouchUntil = 0.0, aimRequests = 0, radioUpdates = 0
    let runButton = Button(), aimButton = Button(), crouchButton = Button()
    var bindingContext = Context()
    func setAiming(_ value: Bool) { aiming = value; aimRequests += 1 }
    func updateRadioControl() { radioUpdates += 1 }
    func controllerEligible(active: Bool, acceptsInput: Bool) -> Bool {
        /* ACTUAL_CONTROLLER_ELIGIBILITY */
    }
    func pollController(gate: inout NativeControllerInputGate, pad: Pad, active: Bool = true,
                        acceptsInput: Bool = true, pressed: Bool = false) -> Bool {
        /* ACTUAL_CONTROLLER_CALL */
    }
    func deliverRight(pad: Pad, driving: Bool, seed: SIMD2<Float> = .zero) -> SIMD2<Float> {
        let currentVehicle: Int? = driving ? 1 : nil
        var cameraLookX = seed.x, cameraLookY = seed.y, steering = seed.x, lookVertical = seed.y
        /* ACTUAL_RIGHT_DELIVERY */
        return driving ? SIMD2(cameraLookX, cameraLookY) : SIMD2(steering, lookVertical)
    }
    /* ACTUAL_HANDLERS */
    var mutations: Int {
        (run ? 1 : 0) + (touchMeleeGuard ? 1 : 0) + aimRequests + radio.requests + radioUpdates +
        (renderer?.jumps ?? 0) + (renderer?.gears ?? 0) + (renderer?.crouches ?? 0) +
        (renderer?.releases ?? 0) + ((renderer?.vehicleLights == true) ? 1 : 0) +
        (legacyCrouchUntil > 0 ? 1 : 0)
    }
}

var checks = 0
func expect(_ value: @autoclosure () -> Bool, _ label: String) {
    checks += 1; precondition(value(), label)
}
let old = CommandLine.arguments.last == "old"
let actions: [(String, (Harness) -> Void, Bool)] = [
    ("run", {$0.toggleRun()}, false), ("jump", {$0.jump()}, false),
    ("aim", {$0.toggleAim()}, false), ("gear", {$0.toggleGear()}, true),
    ("crouch", {$0.toggleCrouch()}, false), ("radio", {$0.nextRadioStation()}, true)
]
let blocked: [(String, (Harness) -> Void)] = [
    ("background", {$0.applicationActive = false}), ("detached", {$0.viewIfLoaded?.window = nil}),
    ("unloaded", {$0.viewIfLoaded = nil}), ("modal", {$0.presentedViewController = 1}),
    ("not-ready", {$0.network.isReady = false}), ("selection", {$0.legacySelection = true}),
    ("server-blocked", {$0.network.originalInputBlocked = true}),
    ("cough", {$0.renderer?.originalCoughing = true})
]
var leakedCases: [String] = []
for (reason, configure) in blocked {
    for (name, action, vehicle) in actions {
        let h = Harness(); if vehicle { h.currentVehicle = 1 }; configure(h)
        expect(!h.acceptsHeldInput, "actual input policy blocks \(reason)")
        action(h)
        if h.mutations != 0 { leakedCases.append("\(reason):\(name)") }
        expect(old ? h.mutations > 0 : h.mutations == 0, "\(reason):\(name) request ownership")
    }
}
for (name, action, vehicle) in actions {
    let h = Harness(); if vehicle { h.currentVehicle = 1 }
    action(h); expect(h.mutations > 0, "accepted \(name) still works")
}
// The same touch button controls guard, vehicle lights, hitch release and dive.
for branch in 0..<4 {
    for enabled in [false, true] {
        let h = Harness(); h.network.originalInputBlocked = !enabled
        switch branch {
        case 0: h.renderer?.canNativeFootMeleeGuard = true; h.toggleAim()
        case 1: h.currentVehicle = 1; h.toggleAim()
        case 2: h.currentVehicle = 1; h.renderer?.canUnhitchVehicle = true; h.toggleCrouch()
        default: h.currentVehicle = 1; h.toggleCrouch()
        }
        expect((h.mutations > 0) == (old || enabled), "contextual action \(branch), enabled \(enabled)")
    }
}
let guarded = Harness(); guarded.bindingContext = .init(melee: true, guarding: true)
guarded.jump(); expect(guarded.mutations == 0, "guarding jump exclusion remains")
let absent = Harness(); absent.renderer = nil; absent.jump(); absent.toggleGear()
expect(absent.mutations == 0, "absent renderer remains safe")
let footRadio = Harness(); footRadio.nextRadioStation()
expect(footRadio.mutations == 0, "on-foot radio exclusion remains")
let noGear = Harness(); noGear.renderer?.hasLandingGear = false; noGear.toggleGear()
expect(noGear.mutations == 0, "unsupported gear remains safe")

// Execute the actual polling eligibility expression through the real neutral gate.
let h = Harness(); var gate = NativeControllerInputGate()
expect(gate.accepts(active: h.controllerEligible(active: true, acceptsInput: true), axes: [0], pressed: false), "initial neutral")
for _ in 0..<120 {
    let accepted = gate.accepts(active: h.controllerEligible(active: true, acceptsInput: false), axes: [0], pressed: false)
    expect(accepted == old, "blocked neutral cannot arm controller")
}
let resumedHeld = gate.accepts(active: h.controllerEligible(active: true, acceptsInput: true), axes: [1], pressed: true)
expect(resumedHeld == old, "held controller does not resume through server block")
expect(gate.accepts(active: true, axes: [0], pressed: false), "release rearms")
expect(gate.accepts(active: true, axes: [1], pressed: true), "fresh controller request works")
var radialLeaks = 0
let radialOld = old || CommandLine.arguments[1] == "radial-old"
for right in [false, true] {
    for i in 0..<128 {
        let angle = Float(i) * 2 * Float.pi / 128
        for radius: Float in [0.049, 0.051] {
            let x = cos(angle) * radius, y = sin(angle) * radius
            var pad = Pad()
            if right {pad.rightThumbstick = .init(xAxis: .init(value: x), yAxis: .init(value: y))}
            else {pad.leftThumbstick = .init(xAxis: .init(value: x), yAxis: .init(value: y))}
            var neutral = NativeControllerInputGate()
            let accepted = h.pollController(gate: &neutral, pad: pad)
            let expected = radialOld ? max(abs(x), abs(y)) <= 0.05 : radius < 0.05
            expect(accepted == expected, "actual polling radial boundary \(right):\(i):\(radius)")
            if radius > 0.05 && accepted { radialLeaks += 1 }
        }
    }
}
var freshGate = NativeControllerInputGate(), diagonalPad = Pad()
diagonalPad.leftThumbstick = .init(xAxis: .init(value: 0.04), yAxis: .init(value: 0.04))
expect((NativeInputMath.stick(x: 0.04, y: 0.04) != .zero), "diagonal is an actual movement input")
expect(h.pollController(gate: &freshGate, pad: diagonalPad) == radialOld, "moving diagonal cannot rearm")
expect(h.pollController(gate: &freshGate, pad: .init()), "actual neutral rearms")
expect(h.pollController(gate: &freshGate, pad: diagonalPad), "armed small diagonal remains usable")
expect(!h.pollController(gate: &freshGate, pad: .init(), acceptsInput: false), "actual blocked call resets")
if !old {expect(!h.pollController(gate: &freshGate, pad: diagonalPad) || radialOld, "blocked diagonal requires neutral")}
let rightOld = old || radialOld || CommandLine.arguments[1] == "right-old"
var droppedRightVectors = 0
for driving in [false, true] {
    for i in 0..<128 {
        let angle = Float(i) * 2 * Float.pi / 128
        let x = cos(angle) * 0.06, y = sin(angle) * 0.06
        var pad = Pad(); pad.rightThumbstick = .init(xAxis: .init(value: x), yAxis: .init(value: y))
        let vector = NativeInputMath.stick(x: x, y: y)
        let delivered = h.deliverRight(pad: pad, driving: driving)
        let expected = rightOld ? SIMD2(abs(vector.x) > 0.05 ? vector.x : 0,
                                       abs(vector.y) > 0.05 ? vector.y : 0) : vector
        expect(delivered == expected, "actual right-stick direction preserved \(driving):\(i)")
        if vector != .zero && delivered == .zero { droppedRightVectors += 1 }
    }
    for value: SIMD2<Float> in [.zero, SIMD2(0.02, 0.02), SIMD2(.nan, 0), SIMD2(0, .infinity)] {
        var pad = Pad(); pad.rightThumbstick = .init(xAxis: .init(value: value.x), yAxis: .init(value: value.y))
        let seed = SIMD2<Float>(0.4, -0.2)
        expect(h.deliverRight(pad: pad, driving: driving, seed: seed) == seed, "inactive right stick preserves other input")
    }
    var pad = Pad(); pad.rightThumbstick = .init(xAxis: .init(value: 0), yAxis: .init(value: 0.6))
    let seed = SIMD2<Float>(0.4, -0.2)
    expect(h.deliverRight(pad: pad, driving: driving, seed: seed) == SIMD2(rightOld ? 0.4 : 0, 0.6),
           "engaged right stick owns the complete camera vector, like the left stick")
}
let report: [String: Any] = ["status": "PASS", "mode": old ? "historical-defect-reproduced" : "fixed",
    "checks": checks, "leakedBlockedHandlerCases": leakedCases, "heldControllerResumed": resumedHeld,
    "radialOld": radialOld, "outOfDeadzoneRearmCases": radialLeaks,
    "rightDeliveryOld": rightOld, "droppedEngagedRightVectors": droppedRightVectors]
print(String(data: try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys]), encoding: .utf8)!)
