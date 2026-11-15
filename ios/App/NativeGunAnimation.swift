import Foundation

/// Definitions emitted by the actual public 60662.OP loader, including melee
/// combos and the source's 30-fps-to-50-Hz loop conversion and .006 breakout.
struct NativeFootWeaponAnimation: Decodable {
    struct Loop: Decodable {
        var start: Double
        var end: Double
        var fire: Double
        var every: Double?
        var again: Double?
        var interval: Double { every ?? end - start }
    }
    struct Swing: Decodable { var clip: String; var loop: Loop }
    var id: Int
    var style: [String: String]?
    var loop: Loop?
    var crouched: Loop?
    var twin: Bool
    var arm: Bool
    var reloads: Bool
    var through: Bool
    var moveSpeed: Double?
    var breakout: Double?
    var continuous: Bool?
    var clips: [String: String?]?
    var swings: [Swing]?
    var moving: Swing?
    var ground: Swing?
    var guardAt: Double?
    var guardTo: Double?
    var flags: [String: Bool]?
    var use: String?
    var aims: Bool?
    func clip(_ name: String) -> String? { clips?[name] ?? nil }
    static func load(data: Data) throws -> [Int: NativeFootWeaponAnimation] {
        struct Document: Decodable { let weapons: [NativeFootWeaponAnimation] }
        let doc = try JSONDecoder().decode(Document.self, from: data)
        return Dictionary(uniqueKeysWithValues: doc.weapons.map { ($0.id, $0) })
    }
}

/// Exact held-weapon animation state machine inside public 49368.R6 (tM).
/// Animation time drives shot events; a continuous stream advances at .02 s.
final class NativeGunAnimation {
    struct Configuration {
        var loop: NativeFootWeaponAnimation.Loop
        var length: Double
        var breakout: Double = .infinity
        var twin = false
        var continuous = false
        var crouched = false
    }
    private enum State: Int { case none = 0, aim = 1, fire = 2, endLeisure = 6, endNow = 7 }
    private var there = false
    private var at: Double = 0
    private var was: Double = 0
    private var playing = false
    private var amount: Double = 0
    private var delta: Double = 0
    private var held = false
    private var active = false
    private var state: State = .none
    private var request: State = .none
    private var ending = false
    private var hasFired = false
    private var didEnd = false
    private var streamTime: Double = 0
    private var ready = true
    var on: Bool { active }
    var blend: Double { there ? amount : 0 }
    var time: Double { at }
    var firing: Bool { active && held && state == .fire }
    var fired: Bool { hasFired }
    var shooting: Bool { active && state == .fire }
    var ended: Bool { let value = didEnd; didEnd = false; return value }

    func control(fire: Bool = false, aim: Bool = false, held: Bool = false, pushed: Bool = false, ready: Bool = true) {
        self.ready = ready
        let wanted: State = fire ? (ready ? .fire : .aim) : aim ? .aim : .none
        if !active {
            guard wanted != .none else { return }
            active = true; ending = false; state = .none; request = wanted
            return
        }
        if wanted.rawValue > request.rawValue { request = wanted }
        if aim { if request.rawValue < State.aim.rawValue { request = .aim } }
        else if held || !pushed {
            if state.rawValue <= State.aim.rawValue && request.rawValue <= State.aim.rawValue { request = .endLeisure }
        } else { request = .endNow }
    }
    func cancel(_ config: Configuration) {
        if active && held {
            at = config.loop.start; was = at; playing = false; delta = (1 - amount) * 8
            state = .aim
            if request.rawValue > State.fire.rawValue { request = .none }
        }
    }
    /// Focus/menu cancellation must discard a queued trigger even before
    /// the association becomes held. Normal cancel keeps its source behavior.
    func cancelInput(_ config: Configuration) {
        request = .none
        cancel(config)
        request = .none
        streamTime = 0
    }
    func shoot(_ config: Configuration) {
        active = true; ending = false; state = .fire; request = .none; hasFired = true
        delta = (1 - (there ? amount : 0)) * 16
        there = true; at = config.loop.fire; was = at; playing = true; held = true
        if amount <= 0 { amount = 0.5 }
    }
    func drop() {
        active = false; ending = false; didEnd = false; hasFired = false; state = .none; request = .none
        there = false; held = false; playing = false; amount = 0
    }
    @discardableResult func step(delta dt: Double, configuration config: Configuration) -> Int {
        let loop = config.loop
        var shots = 0
        if there {
            was = at
            if playing {
                if at >= config.length { playing = false }
                else {
                    at += dt
                    if at >= config.length { at = config.length; delta = -4; held = false }
                }
            }
            amount += delta * dt
            if amount <= 0 && delta < 0 { there = false; held = false; playing = false }
            else if amount > 1 { amount = 1; delta = min(0, delta) }
        }
        guard active else { return 0 }
        if ending {
            if there && held && !playing && at < config.length {
                if at == loop.start { at = min(loop.end, config.length); was = at }
                playing = true
            }
            held = false; active = false; ending = false; state = .none; request = .none; didEnd = true
            return 0
        }
        if held {
            if state.rawValue <= State.aim.rawValue && state != .aim {
                if amount > 0 && delta >= 0 { delta = -4 }
            } else if delta >= 0 {
                if state == .fire {
                    if amount >= 0.99 && ready {
                        if !playing && at == loop.start { playing = true }
                    } else if playing && at >= loop.start && was < loop.start { playing = false; at = loop.start }
                }
                if config.continuous {
                    if state == .fire && playing && at > loop.start && at < loop.end {
                        if hasFired && request != .fire { playing = false; delta = -4 }
                        else {
                            streamTime += dt
                            if !hasFired || streamTime >= 0.02 {
                                shots = hasFired ? max(1, min(4, Int(floor(streamTime / 0.02)))) : 1
                                streamTime = hasFired ? streamTime - Double(shots) * 0.02 : 0; hasFired = true
                            }
                            request = .none
                        }
                    }
                } else if state == .fire && playing {
                    if at > loop.fire && was <= loop.fire { shots |= 1 }
                    let second = loop.fire + (loop.end - loop.start) / 2
                    if config.twin && at > second && was <= second { shots |= 2 }
                    if shots != 0 { hasFired = true }
                }
                if playing || (state == .aim && request.rawValue <= State.aim.rawValue) {
                    if state == .aim && playing && at + (at - was) >= loop.start { playing = false; at = loop.start }
                } else if !(at >= config.length && delta < 0) {
                    if request.rawValue > State.fire.rawValue { delta = -4 }
                    else if amount > 0 && delta >= 0 && ready { playing = true }
                    if request == .fire { state = .fire; request = .none; hasFired = false; streamTime = 0 }
                    else if state == .aim && request != .aim { state = .none }
                }
                if at > loop.end && was <= loop.end {
                    if request == .fire {
                        at = loop.start + (at - loop.start - loop.interval); was = min(at, loop.start)
                        playing = ready
                        if !ready { at = loop.start }
                        state = .fire; request = .none; hasFired = false
                        if playing && !config.continuous && at > loop.fire { shots |= 1; hasFired = true; was = at }
                    } else if request == .aim { at = loop.start; playing = false; state = .aim; request = .none }
                }
                if at > config.breakout && request == .endNow { ending = true; delta = config.crouched ? -4 : -1 }
            }
        } else {
            if request == .aim || request == .fire {
                if there {
                    delta = (1 - amount) * 8
                    if at >= config.length { at = 0; was = 0; playing = true }
                } else { there = true; at = 0; was = 0; playing = true; amount = 0; delta = 8 }
                held = true; hasFired = false
            } else { ending = true }
            state = request; request = .none
        }
        if request.rawValue < State.endLeisure.rawValue { request = .none }
        return shots
    }
}
