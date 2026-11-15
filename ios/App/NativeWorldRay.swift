import Foundation
import simd

/// Ordered coverage of the streamed375m cells. Scene identity belongs to the
/// actor, not to a camera/muzzle that can briefly cross the700m interior band.
enum NativeWorldRay {
    struct Coverage {
        var cells=Set<String>()
        var firstUnavailable:Float?
    }
    struct Hit {let distance:Float;let normal:SIMD3<Float>}
    enum Result {case clear,hit(Hit),unavailable(Float)}

    static func coverage(from start:SIMD3<Float>,to end:SIMD3<Float>,interior:Bool,
                         loaded:(String)->Bool)->Coverage? {
        guard finite(start),finite(end) else{return nil}
        let a=SIMD3<Double>(start),delta=SIMD3<Double>(end)-a,distance=simd_length(delta)
        guard distance.isFinite else{return nil}
        var cuts:[Double]=[0,1]
        for axis in 0..<2 where delta[axis] != 0 {
            for edge in 0...16 {
                let t=(Double(edge)*375-3000-a[axis])/delta[axis]
                if t>0 && t<1 {cuts.append(t)}
            }
        }
        cuts.sort()
        var result=Coverage()
        func visit(_ point:SIMD3<Double>,at t:Double) {
            var name:String?
            if point.x >= -3000 && point.x <= 3000 && point.y >= -3000 && point.y <= 3000 {
                let x=min(15,Int(floor((point.x+3000)/375)))
                let y=min(15,Int(floor((point.y+3000)/375)))
                name="\(interior ? "i":"c")\(y*16+x)"
            }
            if let name {result.cells.insert(name)}
            if (name.map(loaded) != true) && result.firstUnavailable == nil {
                result.firstUnavailable=Float(t*distance)
            }
        }
        visit(a,at:0)
        for i in 1..<cuts.count where cuts[i]-cuts[i-1]>1e-12 {
            visit(a+delta*((cuts[i]+cuts[i-1])*0.5),at:cuts[i-1])
        }
        visit(a+delta,at:1)
        return result
    }

    static func query(from start:SIMD3<Float>,direction:SIMD3<Float>,distance:Float,
                      interior:Bool,loaded:(String)->Bool,
                      trace:(SIMD3<Float>,SIMD3<Float>,Float)->Hit?)->Result {
        guard finite(start),finite(direction),distance.isFinite,distance>0 else{return .unavailable(0)}
        let magnitude=simd_length(direction)
        guard magnitude.isFinite,magnitude>0.0001 else{return .unavailable(0)}
        let unit=direction/magnitude
        guard let coverage=coverage(from:start,to:start+unit*distance,interior:interior,loaded:loaded) else{return .unavailable(0)}
        let limit=min(distance,coverage.firstUnavailable ?? distance)
        if limit>0,let hit=trace(start,unit,limit) {
            guard hit.distance.isFinite,hit.distance>=0,hit.distance<=limit,finite(hit.normal) else{return .unavailable(0)}
            return .hit(hit)
        }
        if let missing=coverage.firstUnavailable {return .unavailable(missing)}
        return .clear
    }
    private static func finite(_ p:SIMD3<Float>)->Bool {p.x.isFinite && p.y.isFinite && p.z.isFinite}
}

/// Geometry-only prefetch is bounded independently from visible mesh residency.
struct NativeCollisionRequests {
    private var touched:[String:Double]=[:]
    private let limit=8,lifetime:Double=2
    mutating func request(_ names:Set<String>,now:Double,visible:Set<String>) {
        guard now.isFinite else{return}
        touched=touched.filter{now >= $0.value && now-$0.value<=lifetime && !visible.contains($0.key)}
        for name in names where !visible.contains(name) {touched[name]=now}
        if touched.count>limit {
            let retained=touched.sorted {a,b in a.value == b.value ? a.key<b.key:a.value>b.value}.prefix(limit)
            touched=Dictionary(uniqueKeysWithValues:retained.map{($0.key,$0.value)})
        }
    }
    mutating func retained(now:Double,visible:Set<String>)->Set<String> {
        request([],now:now,visible:visible)
        return Set(touched.keys).union(visible)
    }
    mutating func reset() {touched.removeAll()}
}
