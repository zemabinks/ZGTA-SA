// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// A remote pedestrian's presentation timeline. Times are monotonic LOCAL
/// receipt times, never an untrusted sender's wall clock. GTA feet stay Z-up.
/// This owns neither the local motor nor authoritative multiplayer positions.
final class NativeRemoteFootMotion<State> {
    struct Snapshot {
        var at: Double
        var position: SIMD3<Double>
        var heading: Double
        var velocity: SIMD3<Double>
        var ordinary: Bool
        var state: State
        var acceleration = SIMD3<Double>.zero
    }
    struct Sample {
        var position: SIMD3<Double>
        var heading: Double
        var velocity: SIMD3<Double>
        var state: State
    }
    private(set) var snapshots: [Snapshot] = []
    private var waits: [Double] = []
    private var delayAnchor: Double = 0.04
    private var delayTarget: Double = 0.04
    private var delayAt: Double = 0
    private var correction = SIMD3<Double>.zero
    private var turnCorrection: Double = 0
    private var correctedAt: Double = 0

    private static func angle(_ value: Double) -> Double { atan2(sin(value),cos(value)) }
    private static func finite(_ value: SIMD3<Double>) -> Bool {
        value.x.isFinite && value.y.isFinite && value.z.isFinite
    }
    func delay(at time: Double) -> Double {
        let change = max(0,time-delayAt)*0.2
        return delayAnchor + max(-change,min(change,delayTarget-delayAnchor))
    }
    func reset() {
        snapshots.removeAll(keepingCapacity:true);waits.removeAll(keepingCapacity:true)
        delayAnchor=0.04;delayTarget=0.04;delayAt=0
        correction = .zero;turnCorrection=0;correctedAt=0
    }

    /// Full-map replacement, appearance and attachment ownership are handled
    /// by the scene. This boundary rejects invalid/nonincreasing receipt times.
    @discardableResult func record(_ input: Snapshot) -> Bool {
        guard input.at.isFinite,input.heading.isFinite,
              Self.finite(input.position),Self.finite(input.velocity) else{return false}
        if let previous=snapshots.last, input.at<=previous.at {return false}
        var next=input
        if let previous=snapshots.last {
            let interval=next.at-previous.at
            let distance=simd_distance(next.position,previous.position)
            // A placement warp or long suspension starts a new owner timeline;
            // interpolation must not sweep the actor through intervening space.
            if interval>0.5 || (next.ordinary && previous.ordinary && distance>3 && distance>15*interval) {reset()}
            else {
                if interval>0.01 && interval<0.5 {
                    var acceleration=(next.velocity-previous.velocity)/interval
                    let length=simd_length(acceleration)
                    if length>15 {acceleration *= 15/length}
                    next.acceleration=(acceleration+previous.acceleration)*0.5
                }
                if next.ordinary && previous.ordinary && interval<=0.25 {
                    waits.append(interval)
                    if waits.count>24 {waits.removeFirst(waits.count-24)}
                }
            }
        }
        let before=sample(at:next.at)
        delayAnchor=delay(at:next.at);delayAt=next.at
        let ordered=waits.sorted(by:>)
        delayTarget=max(0.04,min(0.4,ordered.count>1 ? ordered[1]:ordered.first ?? 0.04))
        snapshots.append(next)
        if snapshots.count>40 {snapshots.removeFirst(snapshots.count-40)}
        correction = .zero;turnCorrection=0;correctedAt=next.at
        if let before,let after=base(at:next.at) {
            let residual=before.position-after.position
            if simd_length(residual)<=3 {
                correction=residual
                turnCorrection=Self.angle(before.heading-after.heading)
            }
        }
        return true
    }

    func sample(at time: Double) -> Sample? {
        guard time.isFinite,let newest=snapshots.last else{return nil}
        // No replay of background time and no indefinitely walking lost peer.
        if time<newest.at {
            return .init(position:newest.position,heading:newest.heading,
                         velocity:.zero,state:newest.state)
        }
        guard var value=base(at:time) else{return nil}
        let remaining=exp(-max(0,time-correctedAt)/0.12)
        value.position += correction*remaining
        value.heading=Self.angle(value.heading+turnCorrection*remaining)
        if time-newest.at>0.5 {value.velocity = .zero}
        return value
    }

    private func base(at time: Double) -> Sample? {
        Self.sample(snapshots,at:time,delay:delay(at:time))
    }

    /// Common interpolation kernel, separated from receipt/correction owners.
    static func sample(_ snapshots:[Snapshot],at time:Double,delay:Double) -> Sample? {
        guard let newest=snapshots.last else{return nil}
        if !newest.ordinary {
            let elapsed=min(0.25,max(0,time-newest.at))
            return .init(position:newest.position+newest.velocity*elapsed+newest.acceleration*(elapsed*elapsed/2),
                         heading:newest.heading,velocity:newest.velocity+newest.acceleration*elapsed,state:newest.state)
        }
        let target=time-delay
        if target>=newest.at {
            let elapsed=min(0.12,target-newest.at)
            return .init(position:newest.position+newest.velocity*elapsed,
                         heading:newest.heading,velocity:newest.velocity,state:newest.state)
        }
        guard let first=snapshots.first else{return nil}
        if target<=first.at {return .init(position:first.position,heading:first.heading,velocity:first.velocity,state:first.state)}
        for index in stride(from:snapshots.count-2,through:0,by:-1) {
            let left=snapshots[index],right=snapshots[index+1]
            guard left.at<=target else{continue}
            let interval=right.at-left.at
            let distance=simd_distance(left.position,right.position)
            let share=interval<=0 || (distance>3 && distance>15*interval) ? 0:max(0,min(1,(target-left.at)/interval))
            return .init(position:left.position+(right.position-left.position)*share,
                         heading:Self.angle(left.heading+Self.angle(right.heading-left.heading)*share),
                         velocity:left.velocity+(right.velocity-left.velocity)*share,state:left.state)
        }
        return nil
    }
}
