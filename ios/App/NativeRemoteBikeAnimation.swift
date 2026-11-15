import Foundation

/// Original main-bundle remote bike wrapper: packet-age prediction, lean
/// easing and crank correction. The seated animator consumes these values;
/// they are distinct from the rigid body's roll and wheel spin.
final class NativeRemoteBikeAnimation {
    struct Sample {
        var serial: Double
        var time: Double
        var speed: Double
        var yawRate: Double
        var health: Double = 1000
        var kit: [Double]?
    }
    struct Frame {
        var lean: Double
        var tuck: Double
        var pedal: Int?
        var crank: Double?
        var hop: Double
    }
    private var model: String?
    private var lean: Double = 0
    private var crank: Double = 0
    private var owed: Double = 0
    private var step: Double?

    func update(model: String,maxLean: Double?,now: Double,delta: Double,
                sample: Sample,previous: Sample?) -> Frame {
        let changed = self.model != model
        if changed { self.model = model }
        let kit = sample.kit.flatMap { !$0.isEmpty && $0[0].isFinite ? $0 : nil }
        let age = clamp(now-sample.time,0,0.5)
        let packetDelta = previous.map { sample.time-$0.time } ?? 0
        var desired: Double = 0,window: Double = 0.25
        if let kit {
            let before: Double
            if packetDelta > 0,let prior = previous?.kit,!prior.isEmpty,prior[0].isFinite { before = prior[0] }
            else { before = kit[0] }
            let prediction = packetDelta > 0 && packetDelta <= 0.3 ? (kit[0]-before)/packetDelta*min(age,0.15) : 0
            desired = clamp(kit[0]+prediction,-Double.pi/2,Double.pi/2)
            window = clamp(0.8*packetDelta,0.04,0.3)
        } else if let maxLean,sample.health != 0 && abs(sample.yawRate) > 0.03 {
            desired = asin(clamp(-sample.speed*sample.yawRate/20,-maxLean,maxLean))
        }
        let ease = changed ? 1 : 1-exp(-delta/window)
        lean += (desired-lean)*ease
        let tuck = kit.flatMap { $0.count > 1 && $0[1].isFinite ? clamp($0[1],-1,1) : nil } ?? 0
        let mode: Int?
        if let kit,kit.count > 3,kit[2].isFinite,kit[3].isFinite { mode = min(2,max(0,Int(floor(kit[2]+0.5)))) }
        else { mode = nil }
        guard let mode,let kit else { step = nil;return Frame(lean:lean,tuck:tuck,pedal:nil,crank:nil,hop:0) }
        let rate: Double = mode == 1 ? 1.1 : mode == 2 ? 2.2 : 0
        if step != sample.serial { owed = phase(kit[3]+rate*age-crank+0.5)-0.5 }
        if step == nil { crank += owed;owed = 0 }
        step = sample.serial
        let correction = owed*ease
        owed -= correction;crank = phase(crank+rate*delta+correction)
        let hop = kit.count > 4 && kit[4].isFinite ? clamp(kit[4],-1,1) : 0
        return Frame(lean:lean,tuck:tuck,pedal:mode,crank:crank,hop:hop)
    }
    private func clamp(_ value: Double,_ lower: Double,_ upper: Double) -> Double { min(upper,max(lower,value)) }
    private func phase(_ value: Double) -> Double { let remainder = value.truncatingRemainder(dividingBy:1);return (remainder+1).truncatingRemainder(dividingBy:1) }
}
