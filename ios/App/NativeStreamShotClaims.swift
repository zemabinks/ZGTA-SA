import Foundation
import simd

/// Existing effect-cylinder policy; this adds no damage, spread or cadence
/// authority. The server validates every claim against its accepted shot.
enum NativeStreamShotTargets {
    static let weapons:Set<Int>=[37,41,42]
    static let radius:Float=0.8
    static let maximumTargets=128
    static func players(ray:NativeShotTargeting.Ray,candidates:[NativeShotTargeting.Candidate],
                        visible:(SIMD3<Float>,SIMD3<Float>)->Bool)->[String] {
        var result:[String]=[],seen=Set<String>()
        for target in candidates {
            guard !target.id.isEmpty,target.id.utf8.count<=64,!seen.contains(target.id),
                  target.point.x.isFinite,target.point.y.isFinite,target.point.z.isFinite else{continue}
            let offset=SIMD3<Double>(target.point)-SIMD3<Double>(ray.origin)
            let direction=SIMD3<Double>(ray.direction),along=simd_dot(offset,direction)
            guard along>=0,along<=Double(ray.range),simd_length(offset-direction*along)<=Double(radius),
                  visible(ray.origin,target.point) else{continue}
            seen.insert(target.id);result.append(target.id)
            if result.count==maximumTargets {break}
        }
        return result
    }
}

/// The same victim cadence spans all effect weapons, as on the existing
/// server. Call only after that exact shot was queued successfully.
final class NativeStreamShotClaims {
    private var connection:String?
    private var times:[String:Int64]=[:]
    private static let interval:Int64=300
    private static let retention:Int64=2000
    private static let capacity=512
    func reset(){connection=nil;times.removeAll(keepingCapacity:true)}
    var retainedCount:Int {times.count}
    static func normalized(_ players:[String])->[String] {
        var result:[String]=[],seen=Set<String>()
        for id in players.prefix(NativeStreamShotTargets.maximumTargets*4) {
            guard !id.isEmpty,id.utf8.count<=64,seen.insert(id).inserted else{continue}
            result.append(id);if result.count==NativeStreamShotTargets.maximumTargets{break}
        }
        return result
    }
    func take(weapon:Int,connection:String,players:[String],milliseconds:Double)->[String] {
        guard NativeStreamShotTargets.weapons.contains(weapon),!connection.isEmpty,connection.utf8.count<=256 else{return []}
        if self.connection != connection {reset();self.connection=connection}
        guard milliseconds.isFinite,milliseconds>=0,milliseconds<Double(Int64.max) else{return []}
        let now=Int64(floor(milliseconds))
        times=times.filter{now<$0.value || now-$0.value<=Self.retention}
        var result:[String]=[],seen=Set<String>()
        for id in Self.normalized(players) {
            guard !id.isEmpty,id.utf8.count<=64,seen.insert(id).inserted else{continue}
            if let previous=times[id] {
                guard now>=previous,now-previous>=Self.interval else{continue}
            } else if times.count>=Self.capacity {continue}
            times[id]=now;result.append(id)
            if result.count==NativeStreamShotTargets.maximumTargets {break}
        }
        return result
    }
}
