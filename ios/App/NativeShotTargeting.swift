import Foundation
import simd

/// Coherent client target-selection geometry. These body offsets and the
/// existing cone policy are approximations, not retail/skeletal hitboxes.
enum NativeShotTargeting {
    typealias V=SIMD3<Float>
    static let muzzleHeight:Float=1.35
    static let torsoHeight:Float=1.15
    static func muzzle(feet:V)->V {feet+V(0,0,muzzleHeight)}
    static func torso(feet:V)->V {feet+V(0,0,torsoHeight)}

    struct Ray {
        let origin:V
        let direction:V
        let range:Float
        init?(origin:V,direction:V,range:Float) {
            guard NativeShotTargeting.finite(origin),NativeShotTargeting.finite(direction),range.isFinite,range>0 else{return nil}
            let raw=SIMD3<Double>(direction),length=simd_length(raw)
            guard length.isFinite,length>0 else{return nil}
            let unit=V(raw/length),end=origin+unit*range
            guard NativeShotTargeting.finite(end) else{return nil}
            self.origin=origin;self.direction=unit;self.range=range
        }
        var end:V {origin+direction*range}
        func point(at distance:Float)->V {origin+direction*distance}
    }
    struct Candidate {
        let id:String
        let point:V
    }
    struct Selection {
        let id:String
        let point:V
        let distance:Float
    }
    /// The exact selected point is used for the cone, range, visibility and
    /// eventual packet endpoint. Input order deterministically breaks ties.
    static func select(ray:Ray,aiming:Bool,candidates:[Candidate],
                       visible:(V,V)->Bool)->Selection? {
        let threshold=Double(aiming ? Float(0.994):Float(0.95))
        var selected:Selection?,nearest=Double.infinity
        for candidate in candidates {
            guard finite(candidate.point) else{continue}
            let offset=SIMD3<Double>(candidate.point)-SIMD3<Double>(ray.origin)
            let distance=simd_length(offset)
            guard distance>0.5,distance<=Double(ray.range),distance<nearest,
                  simd_dot(offset/distance,SIMD3<Double>(ray.direction))>=threshold,
                  visible(ray.origin,candidate.point) else{continue}
            selected=Selection(id:candidate.id,point:candidate.point,distance:Float(distance))
            nearest=distance
        }
        return selected
    }
    private static func finite(_ point:V)->Bool {point.x.isFinite && point.y.isFinite && point.z.isFinite}
}
