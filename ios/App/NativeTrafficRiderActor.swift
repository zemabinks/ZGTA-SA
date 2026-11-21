// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// One ready original actor binding. It retains the actual pose at a phase
/// boundary; the scalar fall owner never blends the figure anchor twice.
final class NativeTrafficRiderActor {
    struct Output {
        let pose:NativeSkeletalActor.Pose,model:simd_float4x4
        let down:Bool
        let feet:(position:SIMD3<Float>,heading:Float)?
    }
    let identity:String,name:String,seat:NativeTrafficOccupants.Seat
    private(set) var actor:NativeSkeletalActor
    private let definition:NativeRiderDefinitions.Definition
    private let library:NativeSkeletalAnimationLibrary
    private let animator:NativeRiderAnimation
    private var fall:NativeTrafficRiderFall?
    private var capture:NativeSkeletalActor.Pose?,captureSerial:UInt64=2
    private var previousEnd:Double?,last:Output?
    private var origin:Float=0
    var falling:Bool{fall != nil}
    var heldOutput:Output?{last}
    /// A verified original upload can replace its converted actor object
    /// without replacing the rider's task. Retained palettes/captures require
    /// the same complete rig, vertices and skin order, not merely a bone count.
    func bindCompatible(_ next:NativeSkeletalActor)->Bool {
        if actor === next{return true}
        guard actor.matchesRig(next)else{return false}
        actor=next;return true
    }

    init(identity:String,name:String,seat:NativeTrafficOccupants.Seat,
         actor:NativeSkeletalActor,definition:NativeRiderDefinitions.Definition,
         library:NativeSkeletalAnimationLibrary) {
        self.identity=identity;self.name=name;self.seat=seat;self.actor=actor
        self.definition=definition;self.library=library
        animator=NativeRiderAnimation(duration:library.duration(of:))
    }
    private func clip(_ name:String?)->NativeTrafficRiderFall.Clip? {
        guard let name,let duration=library.duration(of:name)else{return nil}
        return .init(name:name,duration:duration,rootAtStart:library.rootPosition(name,at:0))
    }
    func update(interval:NativeRiderPoseClock.Interval,model:simd_float4x4,
                origin:Float,input:NativeRiderAnimation.Input)->Output? {
        guard interval.canPrime else{previousEnd=nil;return last}
        if previousEnd==interval.end,let last{return last}
        let delta=max(0,interval.end-max(interval.start,previousEnd ?? interval.end))
        previousEnd=interval.end
        guard let anchor=definition.seats[seat.index].position else{return nil}
        let turn=Float(definition.seats[seat.index].turn ?? 0)
        if fall==nil,definition.astride,input.dead {
            // A newly ready dead seat still has a real seated pose to capture.
            capture=last?.pose ?? actor.riderPose(frame:animator.update(delta:0,
                configuration:definition.configuration(seat:seat.index),input:.init()),
                library:library,figurePosition:anchor,figureTurn:turn)
            let hit=clip(definition.hitClip(contains:{self.library.duration(of:$0) != nil}))
            let falls=(definition.group?.fallOff ?? []).map{value in
                clip(value?.replacingOccurrences(of:":",with:"/"))
            }
            fall=NativeTrafficRiderFall(seat:SIMD3<Double>(anchor),side:definition.seats[seat.index].side,
                turn:Double(turn),origin:Double(origin),lift:1,
                modelMatrix:simd_double4x4(columns:(SIMD4<Double>(model[0]),SIMD4<Double>(model[1]),SIMD4<Double>(model[2]),SIMD4<Double>(model[3]))),
                hit:hit,falls:falls,stand:clip("ped/idle_stance"))
            self.origin=origin
            // Invalid resource values cannot silently become a living rider.
            guard fall != nil else{return nil}
        }
        if let fall,let frame=fall.update(delta:delta) {
            let sample=NativeRiderAnimation.Frame(base:frame.sample?.clip,time:frame.sample?.time ?? 0)
            if captureSerial != frame.captureSerial {
                // ep() captures the raw endpoint before this update's blend.
                capture=actor.riderPose(frame:sample,library:library,
                    figurePosition:SIMD3<Float>(frame.capturedAnchor),figureTurn:Float(frame.turn))
                captureSerial=frame.captureSerial
            }
            let pose=actor.riderPose(frame:sample,library:library,
                figurePosition:SIMD3<Float>(frame.rawAnchor),figureTurn:Float(frame.turn),
                previous:frame.transition<1 ? capture:nil,transition:frame.transition)
            let m=frame.modelMatrix
            let frozen=simd_float4x4(columns:(SIMD4<Float>(m[0]),SIMD4<Float>(m[1]),SIMD4<Float>(m[2]),SIMD4<Float>(m[3])))
            let landedRoot=frame.completedClip.flatMap{name in library.duration(of:name).map{library.rootPosition(name,at:$0)}}
            last = .init(pose:pose,model:frozen,down:frame.state == .down,
                feet:frame.state == .down ? landedRoot.flatMap{actor.riderLanded(pose:pose,rootTranslation:$0,model:frozen,origin:self.origin)}:nil)
        }else if fall==nil {
            let pose=actor.riderPose(frame:animator.update(interval:interval,
                configuration:definition.configuration(seat:seat.index),input:input),
                library:library,figurePosition:anchor,figureTurn:turn)
            last = .init(pose:pose,model:model,down:false,feet:nil)
        }
        return last
    }
}
