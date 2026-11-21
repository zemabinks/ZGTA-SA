// SPDX-License-Identifier: AGPL-3.0-only
import simd

/// The ordinary-shot pool is separate from projectiles and hit authority.
/// Exhausting its sixteen lines never suppresses the shot's other effects.
final class NativeShotTracers {
    struct Line {
        let slot:Int
        let back:SIMD3<Double>,head:SIMD3<Double>
        let opacity:Double
    }
    private struct Trace {
        let head:SIMD3<Double>,offset:SIMD3<Double>,life:Double
        var left:Double
    }
    private var traces=[Trace?](repeating:nil,count:16)
    private let random:()->Double
    init(random:@escaping()->Double={Double.random(in:0..<1)}){self.random=random}
    func clear(){traces=[Trace?](repeating:nil,count:16)}
    @discardableResult func shot(from start:SIMD3<Double>,to end:SIMD3<Double>)->Bool {
        guard (0..<3).allSatisfy({start[$0].isFinite && end[$0].isFinite}) else{return false}
        let offset=end-start,length=simd_length(offset)
        guard length.isFinite,length>0,let slot=traces.firstIndex(where:{$0==nil}) else{return false}
        let direction=offset/length
        let along=random()*length,size=min(2+3*random(),length-along)
        let life=slot<5 ? 0.3:slot<10 ? 0.15:0.075
        traces[slot]=Trace(head:start+direction*(along+size),offset:-direction*size,life:life,left:life)
        return true
    }
    func advance(delta:Double) {
        guard delta.isFinite,delta>=0 else{return}
        for index in traces.indices {
            guard var trace=traces[index]else{continue}
            trace.left-=delta
            traces[index]=trace.left<=0 ? nil:trace
        }
    }
    var lines:[Line] {
        traces.enumerated().compactMap{index,trace in
            guard let trace else{return nil}
            let opacity=trace.left/trace.life
            return .init(slot:index,back:trace.head+trace.offset*opacity,head:trace.head,opacity:opacity)
        }
    }
}
