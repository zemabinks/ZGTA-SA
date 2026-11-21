// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Clip/anchor ownership for a ready astride rider. The caller retains bones,
/// resource identity and detached-driver/NPC handoff; this owner never creates
/// a physics body or grants vehicle/player authority.
final class NativeTrafficRiderFall {
    struct Clip {
        let name:String,duration:Double
        let rootAtStart:SIMD3<Double>
    }
    struct Sample {let clip:String,time:Double}
    enum State:String {case jacked,down}
    struct Frame {
        let state:State,phase:String?,completedClip:String?
        let sample:Sample?,phaseTime:Double
        /// rawAnchor is supplied to the poser before its continuity blend.
        /// anchor is the resulting position, retained for the next update.
        let rawAnchor:SIMD3<Double>,anchor:SIMD3<Double>,capturedAnchor:SIMD3<Double>
        let transitionProgress:Double,transition:Double,turn:Double
        let captureSerial:UInt64,modelMatrix:simd_double4x4
    }
    private struct Phase {
        let clip:Clip,anchor:SIMD3<Double>,lowerTo:Double?
    }
    private var phases:[Phase]
    private(set) var state:State
    private(set) var phaseTime=0.0,transitionProgress=0.0
    private(set) var anchor:SIMD3<Double>,capturedAnchor:SIMD3<Double>,turn:Double
    private(set) var captureSerial:UInt64=2
    private(set) var completed:Clip?
    let modelMatrix:simd_double4x4
    private let stand:Clip?
    var phase:String?{phases.first?.clip.name}
    var remaining:[String]{Array(phases.dropFirst()).map{$0.clip.name}}

    init?(seat:SIMD3<Double>,side:Int,requestedSide:Int = -1,turn:Double,
          origin:Double,lift:Double,modelMatrix:simd_double4x4,
          hit:Clip?,falls:[Clip?],stand:Clip?) {
        func finite(_ p:SIMD3<Double>)->Bool{p.x.isFinite && p.y.isFinite && p.z.isFinite}
        func valid(_ clip:Clip?)->Bool {
            clip.map{!$0.name.isEmpty && $0.duration.isFinite && $0.duration>=0 && finite($0.rootAtStart)} ?? true
        }
        guard finite(seat),turn.isFinite,origin.isFinite,lift.isFinite,
              (0..<4).allSatisfy({i in (0..<4).allSatisfy{modelMatrix[i][$0].isFinite}}),
              valid(hit),valid(stand),falls.allSatisfy(valid)else{return nil}
        let direction=side==0 ? requestedSide:side,index=direction<0 ? 0:1
        func entry(_ i:Int)->Clip?{falls.indices.contains(i) ? falls[i]:nil}
        var queue:[Phase]=[]
        if let hit{queue.append(.init(clip:hit,anchor:seat,lowerTo:nil))}
        if let fall=entry(index) ?? entry(1-index) {
            queue.append(.init(clip:fall,anchor:seat-fall.rootAtStart,lowerTo:-origin+lift))
        }
        phases=queue;state=queue.isEmpty ? .down:.jacked
        anchor=seat;capturedAnchor=seat;self.turn=turn
        self.modelMatrix=modelMatrix;self.stand=stand
    }
    private static func smooth(_ value:Double,_ low:Double,_ high:Double)->Double {
        if value<=low{return 0};if value>=high{return 1}
        let share=(value-low)/(high-low);return share*share*(3-2*share)
    }
    /// One supplied display update can finish at most one phase. Its sample
    /// remains the old phase endpoint; the next clip starts on a later call.
    /// The separate continuity clock consumes the supplied delta after capture.
    func update(delta:Double)->Frame? {
        guard delta.isFinite,delta>=0 else{return nil}
        var sample:Sample?
        if let phase=phases.first {
            phaseTime+=delta
            sample = .init(clip:phase.clip.name,time:min(phaseTime,phase.clip.duration))
            anchor=phase.anchor
            if let target=phase.lowerTo {
                anchor.z += (target-anchor.z)*Self.smooth(phaseTime,0,0.5*phase.clip.duration)
            }
            if phaseTime>=phase.clip.duration {
                completed=phase.clip;phases.removeFirst();phaseTime=0
                capturedAnchor=anchor;transitionProgress=0;captureSerial &+= 1
                if phases.isEmpty{state = .down}
            }
        }else if let clip=completed ?? stand {
            sample = .init(clip:clip.name,time:completed==nil ? 0:clip.duration)
        }
        let raw=anchor
        if transitionProgress<1 {
            transitionProgress=min(1,transitionProgress+delta/0.25)
            anchor=capturedAnchor+(anchor-capturedAnchor)*Self.smooth(transitionProgress,0,1)
        }
        turn+=(0-turn)*min(1,delta/0.25*2)
        return .init(state:state,phase:phase,completedClip:completed?.name,sample:sample,phaseTime:phaseTime,
            rawAnchor:raw,anchor:anchor,capturedAnchor:capturedAnchor,transitionProgress:transitionProgress,
            transition:Self.smooth(transitionProgress,0,1),turn:turn,captureSerial:captureSerial,modelMatrix:modelMatrix)
    }
}
