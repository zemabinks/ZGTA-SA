// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Match only already admitted server pedestrians. No spawn, skin change,
/// health change, position packet or player-row mutation is performed here.
enum NativeTrafficRiderHandoff {
    struct Source {
        let serial:UInt64,skin:Int
        let feet:SIMD3<Double>
    }
    struct Destination:Hashable {
        let id:UInt16,generation:UInt64
    }
    struct Candidate {
        let destination:Destination,skin:Int
        let position:SIMD3<Double>,admittedAt:Double
    }
    static func match(sources:[Source],candidates:[Candidate],now:Double,
                      assigned:[UInt64:Destination])->[UInt64:Destination] {
        guard now.isFinite else{return assigned}
        func distance(_ a:SIMD3<Double>,_ b:SIMD3<Double>)->Double{hypot(a.x-b.x,a.y-b.y)}
        var result=assigned,used=Set(assigned.values)
        for source in sources where result[source.serial]==nil {
            var nearest:Candidate?,limit=4.0
            for candidate in candidates where !used.contains(candidate.destination) && candidate.skin==source.skin {
                guard candidate.admittedAt.isFinite,now>=candidate.admittedAt,now-candidate.admittedAt<=5 else{continue}
                let gap=distance(candidate.position,source.feet)
                guard gap.isFinite,gap<limit else{continue}
                let belongsToNearer=sources.contains{other in
                    other.serial != source.serial && other.skin==source.skin && result[other.serial]==nil &&
                    distance(candidate.position,other.feet)<gap
                }
                if !belongsToNearer{nearest=candidate;limit=gap}
            }
            if let nearest{result[source.serial]=nearest.destination;used.insert(nearest.destination)}
        }
        return result
    }
}
