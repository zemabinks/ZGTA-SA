import Foundation
import simd

/// A shot is clear only when every crossed detailed collision cell is ready.
/// A single origin-cell mesh cannot establish visibility across a cell edge.
enum NativeShotOcclusion {
    static func cells(from start: SIMD3<Float>, to finish: SIMD3<Float>) -> Set<String>? {
        guard [start.x,start.y,start.z,finish.x,finish.y,finish.z].allSatisfy(\.isFinite),
              start.x >= -3000, start.x < 3000, start.y >= -3000, start.y < 3000,
              finish.x >= -3000, finish.x < 3000, finish.y >= -3000, finish.y < 3000,
              (start.z > 700) == (finish.z > 700) else { return nil }
        let a=SIMD3<Double>(start), b=SIMD3<Double>(finish), delta=b-a
        var cuts:[Double]=[0,1]
        for axis in 0..<2 where delta[axis] != 0 {
            for edge in 1..<16 {
                let t=(Double(edge)*375-3000-a[axis])/delta[axis]
                if t>0 && t<1 { cuts.append(t) }
            }
        }
        cuts.sort()
        var samples=cuts
        for i in 1..<cuts.count { samples.append((cuts[i-1]+cuts[i])*0.5) }
        let prefix=start.z > 700 ? "i":"c"
        return Set(samples.map { t in
            let point=a+delta*t
            let x=min(15,max(0,Int(floor((point.x+3000)/375))))
            let y=min(15,max(0,Int(floor((point.y+3000)/375))))
            return "\(prefix)\(y*16+x)"
        })
    }

    static func clear(from start: SIMD3<Float>, to finish: SIMD3<Float>,
                      loaded: (String)->Bool, trace: (SIMD3<Float>,SIMD3<Float>,Float)->Float?) -> Bool {
        guard let required=cells(from:start,to:finish), required.allSatisfy(loaded) else { return false }
        let offset=finish-start, distance=simd_length(offset)
        guard distance.isFinite, distance>0.0001 else { return false }
        guard let obstruction=trace(start,offset/distance,distance) else { return true }
        // A surface at the exact endpoint is not between the muzzle and target.
        return obstruction.isFinite && obstruction >= distance
    }
}
