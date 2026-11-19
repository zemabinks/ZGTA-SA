import Foundation

@main enum VerifyRecovery {
    static var checks = 0
    static func expect(_ value: @autoclosure () -> Bool, _ label: String) {
        precondition(value(), label); checks += 1
    }
    static func opened(_ action: NativeConnectionRecovery.Action?) -> UInt64 {
        guard case .open(let generation) = action else { fatalError("Expected one connection attempt") }
        return generation
    }
    static func main() {
        var model = NativeConnectionRecovery()
        var now = 0.0, generation = opened(model.start(now: now))
        expect(model.state == .connecting && model.desired, "Initial intent")
        expect(model.start(now: now) == nil, "Connect is idempotent")
        for delay in [2.0, 4, 8, 16, 32, 60, 60] {
            expect(model.failed(generation: generation, now: now), "Current failure accepted")
            expect(!model.failed(generation: generation, now: now), "Duplicate failure cannot schedule twice")
            expect(model.state == .reconnecting, "Input unavailable during retry")
            expect(model.tick(now: now + delay - 0.001) == nil, "Do not retry early")
            now += delay; generation = opened(model.tick(now: now))
        }
        model.received(.hello, generation: generation, now: now)
        expect(model.state != .ready, "Hello alone is insufficient")
        model.received(.inventory, generation: generation, now: now)
        expect(model.state != .ready, "Inventory without world is insufficient")
        model.received(.world, generation: generation, now: now)
        expect(model.state == .ready, "Three current baselines enable ready")
        expect(model.failed(generation: generation, now: now), "Established failure")
        expect(model.tick(now: now + 0.499) == nil, "Established reconnect delay")
        now += 0.5; let previous = generation; generation = opened(model.tick(now: now))
        expect(generation != previous, "Fresh generation")
        model.received(.hello, generation: previous, now: now)
        model.received(.world, generation: previous, now: now)
        model.received(.inventory, generation: previous, now: now)
        expect(model.state != .ready, "Old callbacks never unlock fresh transport")
        expect(!model.failed(generation: previous, now: now), "Old failure ignored")
        expect(model.failed(generation: generation, now: now), "Failed post-established attempt")
        expect(model.tick(now: now + 1.999) == nil, "Failed delay resets to2seconds after hello")
        model.setActive(false, now: now)
        expect(model.tick(now: now + 1000) == nil, "No retries while inactive")
        now += 1000; model.setActive(true, now: now)
        generation = opened(model.tick(now: now))
        expect(model.state == .reconnecting, "Foreground restores desired transport")
        let oldGeneration = generation
        generation = opened(model.restart(now: now))
        expect(generation != oldGeneration, "Resync uses new generation")
        expect(model.failed(generation: generation, now: now), "Resync failure is recoverable")
        now += 4; generation = opened(model.tick(now: now))
        expect(model.state == .reconnecting, "Failed resync did not latch")
        model.stop()
        expect(model.state == .stopped && !model.desired, "Terminal disconnect")
        expect(model.tick(now: now + 10000) == nil, "Terminal stop never retries")
        model.received(.hello, generation: generation, now: now)
        expect(model.state == .stopped, "Late hello cannot resurrect stopped client")

        for order in [[0,1,2],[0,2,1],[1,0,2],[1,2,0],[2,0,1],[2,1,0]] {
            var r = NativeConnectionRecovery(); let g = opened(r.start(now: 0))
            for (index, key) in order.enumerated() {
                let baseline: NativeConnectionRecovery.Baseline = key == 0 ? .hello : key == 1 ? .inventory : .world
                r.received(baseline, generation: g, now: Double(index) / 10)
                expect((r.state == .ready) == (index == 2), "Complete barrier regardless of baseline order")
            }
        }
        for fps in [30,60,120] {
            var r = NativeConnectionRecovery(); let g = opened(r.start(now: 0))
            for step in 1...fps*10 { expect(r.tick(now: Double(step)/Double(fps)) == nil, "No early handshake timeout") }
            expect(r.tick(now: 10 + 1/Double(fps)) == .timeout(g), "Bounded incomplete/malformed handshake")
            r.stop(); let live = opened(r.start(now: 20))
            for b in [NativeConnectionRecovery.Baseline.hello,.world,.inventory] { r.received(b,generation: live,now: 20) }
            for step in 1...fps*30 {
                let t = 20 + Double(step)/Double(fps)
                if step % (fps*2) == 0 { r.received(generation: live,now: t) }
                expect(r.tick(now: t) == nil && r.state == .ready, "Healthy heartbeat independent of display FPS")
            }
            expect(r.tick(now: 200) == nil, "Frame gap gets timeout grace")
            for step in 1...fps*10 { expect(r.tick(now: 200 + Double(step)/Double(fps)) == nil, "Grace remains bounded") }
            expect(r.tick(now: 210 + 1/Double(fps)) == .timeout(live), "Silent connection expires after grace")
        }
        var suspended = NativeConnectionRecovery(); let sg = opened(suspended.start(now: 0))
        for b in [NativeConnectionRecovery.Baseline.hello,.world,.inventory] { suspended.received(b,generation: sg,now: 0) }
        suspended.setActive(false,now: 1)
        expect(suspended.tick(now: 1000) == nil, "Suspended watchdog suppressed")
        suspended.setActive(true,now: 1000)
        expect(suspended.tick(now: 1000) == nil, "Foreground avoids false timeout")
        for step in 1...40 { expect(suspended.tick(now: 1000 + Double(step)/4) == nil, "Foreground grace") }
        expect(suspended.tick(now: 1010.25) == .timeout(sg), "Dead foreground socket detected")

        let valid: [String:Any] = ["revision": 3, "selected": 22,
            "weapons": [["id":22,"clip":7,"rest":20]], "reload": NSNull()]
        var rows = [valid]
        for key in ["revision","selected","weapons"] { var value=valid;value.removeValue(forKey:key);rows.append(value) }
        for key in ["revision","selected"] { for invalid:Any in [true,-1,0.5,Double.infinity,9_007_199_254_740_992.0] { var value=valid;value[key]=invalid;rows.append(value) } }
        for id in [0,1,15,22,46,47] { for clip in [0,9999,10000,-1] { for rest in [0,1,9999,-1] {
            var value=valid;value["selected"]=id;value["weapons"]=[["id":id,"clip":clip,"rest":rest]];rows.append(value)
        } } }
        for reload:[String:Any] in [["remainingMs": -1],["remainingMs": 10001],["remainingMs": 500,"weapon":22],["remainingMs": 0,"weapon":0],["remainingMs": 0,"weapon":23]] { var value=valid;value["reload"]=reload;rows.append(value) }
        var duplicate=valid;duplicate["weapons"]=[["id":22,"clip":1,"rest":0],["id":22,"clip":1,"rest":0]];rows.append(duplicate)
        for value in rows {
            let actual = NativeWeaponState(allowLegacySnapshots:true)
            expect(NativeConnectionRecovery.validInventory(value) == actual.apply(value), "Ready validator matches actual inventory parser")
        }
        print("PASS native connection recovery: \(checks) clock/baseline/validation checks; no services/UI")
    }
}
