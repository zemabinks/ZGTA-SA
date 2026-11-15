import Foundation
import CoreFoundation

/// Transport intent and deadlines are independent from account identity and
/// inventory prediction. All times use the same injected monotonic clock.
struct NativeConnectionRecovery {
    enum State: Equatable { case stopped, connecting, reconnecting, ready }
    enum Action: Equatable { case open(UInt64), timeout(UInt64) }
    enum Baseline { case hello, inventory, world }
    private(set) var state: State = .stopped
    private(set) var desired = false
    private(set) var active = true
    private(set) var generation: UInt64 = 0
    private(set) var hasTransport = false
    private var attempts = 0
    private var retryAt: Double = 0
    private var failedDelay: Double = 2
    private var startedAt: Double = 0
    private var lastInbound: Double = 0
    private var lastTick: Double?
    private var established = false
    private var hello = false, inventory = false, world = false

    mutating func start(now: Double) -> Action? {
        guard now.isFinite else { return nil }
        if !desired { desired = true; attempts = 0; failedDelay = 2; retryAt = now; state = .connecting }
        return tick(now: now)
    }
    mutating func stop() {
        desired = false; hasTransport = false; generation &+= 1
        attempts = 0; failedDelay = 2; lastTick = nil; state = .stopped
        clearBaseline()
    }
    mutating func setActive(_ value: Bool, now: Double) {
        guard active != value else { return }
        active = value; lastTick = nil
        if value, now.isFinite {
            // Suspension is not evidence of a dead server. A foreground ping
            // gets a full bounded grace period to detect a half-open socket.
            startedAt = now; lastInbound = now
        }
    }
    mutating func restart(now: Double) -> Action? {
        guard desired, now.isFinite else { return nil }
        hasTransport = false; clearBaseline(); retryAt = now; state = .reconnecting
        return tick(now: now)
    }
    mutating func tick(now: Double) -> Action? {
        guard desired, active, now.isFinite else { return nil }
        if let lastTick, now < lastTick || now-lastTick > 1 {
            // Match the browser's frame-gap protection: elapsed suspended time
            // must not manufacture an immediate connection timeout.
            lastInbound = now; startedAt = now
        }
        lastTick = now
        if hasTransport {
            if now-lastInbound > 10 || (state != .ready && now-startedAt > 10) { return .timeout(generation) }
            return nil
        }
        guard now >= retryAt else { return nil }
        generation &+= 1; hasTransport = true; attempts += 1
        state = attempts == 1 ? .connecting : .reconnecting
        startedAt = now; lastInbound = now; clearBaseline()
        return .open(generation)
    }
    @discardableResult mutating func failed(generation: UInt64, now: Double) -> Bool {
        guard desired, hasTransport, generation == self.generation, now.isFinite else { return false }
        hasTransport = false
        retryAt = now + (established ? 0.5 : failedDelay)
        if !established { failedDelay = min(60, failedDelay * 2) }
        clearBaseline(); state = .reconnecting
        return true
    }
    mutating func received(generation: UInt64, now: Double) {
        guard desired, hasTransport, generation == self.generation, now.isFinite else { return }
        lastInbound = now
    }
    mutating func received(_ baseline: Baseline, generation: UInt64, now: Double) {
        guard desired, hasTransport, generation == self.generation, now.isFinite else { return }
        received(generation: generation, now: now)
        switch baseline {
        case .hello: hello = true; established = true; failedDelay = 2
        case .inventory: inventory = true
        case .world: world = true
        }
        if hello && inventory && world { state = .ready }
    }
    private mutating func clearBaseline() {
        hello = false; inventory = false; world = false; established = false
    }

    /// A syntactically valid ACK alone is insufficient to unlock movement.
    /// Check the complete same inventory shape accepted by NativeWeaponState.
    static func validInventory(_ value: [String: Any]) -> Bool {
        guard integer(value["revision"]) != nil, let selected = integer(value["selected"]),
              let rows = value["weapons"] as? [[String: Any]] else { return false }
        var ids = Set<Int>()
        for row in rows {
            guard let id = integer(row["id"]), id <= 46, ids.insert(id).inserted,
                  let clip = integer(row["clip"]), let rest = integer(row["rest"]),
                  clip <= 9999, rest <= 9999-clip else { return false }
        }
        guard selected == 0 || ids.contains(selected) else { return false }
        let reload = value["reload"] as? [String: Any]
        let remaining = (reload?["remainingMs"] as? NSNumber)?.doubleValue ?? 0
        guard remaining.isFinite, remaining >= 0, remaining <= 10000 else { return false }
        if let weapon = reload?["weapon"], integer(weapon) != selected || selected == 0 { return false }
        return true
    }
    static func integer(_ value: Any?) -> Int? {
        guard let n = value as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite, n.doubleValue >= 0, n.doubleValue <= 9_007_199_254_740_991,
              let result = Int(exactly: n.doubleValue) else { return nil }
        return result
    }
}
