// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Pure ownership of server camera commands in physical GTA world coordinates.
/// Timed RPC82 keeps its duration: Cut2 linear, Cut1 half-cosine. This mapping is
/// an inference supported by the explicit API duration, SAMP-API's time/smooth
/// vector wrappers, and gta-reversed ProcessVectorMoveLinear/TrackLinear; it is
/// not a verified retail comparison. No reconstruction implementation is copied.
/// Untimed PointAt MOVE has no duration on the wire and needs a caller policy.
struct NativeSAMPGameCamera {
    typealias Commands=NativeSAMPGameplayCommands
    struct Limits {
        var maximumCoordinate: Float = 10_000_000
        var minimumLookDistance: Float = 0.001
    }
    enum Failure: Error, Equatable { case configuration, nonFiniteTime, invalidVector, invalidDuration, invalidGravity, missingNormalPose }
    struct Pose: Equatable {
        var eye: SIMD3<Float>
        var target: SIMD3<Float>
        var up=SIMD3<Float>(0,0,1)
    }
    enum Curve { case linear, halfCosine }
    struct Move { let duration: TimeInterval; let curve: Curve }
    struct LookAtRequest {
        let from: Pose
        let target: SIMD3<Float>
        let startedAt: TimeInterval
        let generation: UInt64?
    }
    typealias LookAtMovePolicy=(LookAtRequest)->Move?
    enum Subject: Equatable { case player(UInt16),vehicle(UInt16) }
    enum Provenance { case nativeGameCameraAdapter, unverifiedOffsets }
    struct SubjectFrame {
        let focus: SIMD3<Float>
        var normal: Pose?
        var side: Pose?
        var normalProvenance: Provenance = .unverifiedOffsets
        var sideProvenance: Provenance = .unverifiedOffsets
    }
    typealias SubjectProvider=(Subject,Commands.SpectateMode)->SubjectFrame?
    struct Spectator: Equatable { let subject: Subject; let mode: Commands.SpectateMode }
    enum Diagnostic: Hashable {
        case coincidentLookAt, correctedUp, verticalUpFallback, missingSubject, invalidSubject
        case missingNormalFollow, missingSideFollow, unverifiedFollow
        case spectateNeedsEnable, cameraBlockedBySpectateMode, lookAtMovePolicyRequired
    }
    struct Sample {
        /// Actual safe view used for drawing, spectator212 and streaming.
        let pose: Pose
        let active: Bool
        let spectating: Bool
        let spectator: Spectator?
        let diagnostics: Set<Diagnostic>
        let followRevision: UInt64
    }
    private struct Track {
        let from,to:SIMD3<Float>
        let start,duration:TimeInterval
        let curve:Curve
        func at(_ now:TimeInterval)->SIMD3<Float> {
            if duration<=0 || now-start>=duration{return to}
            if now<=start{return from}
            let ratio=max(0,min(1,(now-start)/duration))
            let share=curve == .linear ? ratio:(1-cos(Double.pi*ratio))/2
            let a=SIMD3<Double>(Double(from.x),Double(from.y),Double(from.z))
            let b=SIMD3<Double>(Double(to.x),Double(to.y),Double(to.z))
            let value=a+(b-a)*share
            return SIMD3(Float(value.x),Float(value.y),Float(value.z))
        }
    }
    private struct PendingLookAt { let target:SIMD3<Float>;let startedAt:TimeInterval;var from:Pose? }
    private let limits:Limits
    var lookAtMovePolicy:LookAtMovePolicy?
    private(set) var generation:UInt64?
    private(set) var sequence:UInt64=0
    private(set) var spectating=false
    private(set) var spectator:Spectator?
    private(set) var followRevision:UInt64=0
    private(set) var lastSample:Sample?
    private var time = -Double.infinity
    private var ownsView=false
    private var base:Pose?,anchor:Pose?
    private var position:Track?,lookAt:Track?,pendingLookAt:PendingLookAt?
    private var commandDiagnostics=Set<Diagnostic>()
    var active:Bool { ownsView }

    init(limits:Limits=Limits(),lookAtMovePolicy:LookAtMovePolicy?=nil){self.limits=limits;self.lookAtMovePolicy=lookAtMovePolicy}
    private func validateLimits()throws{
        guard limits.maximumCoordinate.isFinite,limits.maximumCoordinate>0,limits.maximumCoordinate<=1_000_000_000,
              limits.minimumLookDistance.isFinite,limits.minimumLookDistance>0,limits.minimumLookDistance<=1_000 else{throw Failure.configuration}
    }
    private func valid(_ vector:SIMD3<Float>)->Bool {
        vector.x.isFinite && vector.y.isFinite && vector.z.isFinite &&
        abs(vector.x)<=limits.maximumCoordinate && abs(vector.y)<=limits.maximumCoordinate && abs(vector.z)<=limits.maximumCoordinate
    }
    private mutating func advance(_ timestamp:TimeInterval)throws->TimeInterval {
        guard timestamp.isFinite else{throw Failure.nonFiniteTime};time=max(time,timestamp);return time
    }
    private func raw(at now:TimeInterval,fallback:Pose?)->Pose? {
        guard var pose=base ?? lastSample?.pose ?? fallback else{return nil}
        if let position{pose.eye=position.at(now)}
        if let lookAt{pose.target=lookAt.at(now)}
        return pose
    }
    private mutating func takeView(at now:TimeInterval,seed:Pose?)throws {
        if let seed,(!valid(seed.eye) || !valid(seed.target)){throw Failure.invalidVector}
        let current:Pose?
        if !ownsView {current=seed ?? lastSample?.pose}
        else if spectating && spectator != nil {current=seed ?? lastSample?.pose ?? raw(at:now,fallback:seed)}
        else {current=raw(at:now,fallback:seed)}
        if let current{base=current;anchor=current}
        ownsView=true
    }
    private mutating func releaseView(){
        ownsView=false;base=nil;anchor=nil;position=nil;lookAt=nil;pendingLookAt=nil;spectator=nil;commandDiagnostics.removeAll()
        followRevision &+= 1
    }
    /// Rejects retired/reordered events before they can change time or camera state.
    @discardableResult mutating func apply(_ event:Commands.Event,at timestamp:TimeInterval,seed:Pose?=nil)throws->Bool {
        try validateLimits()
        if event.command == .reset {
            guard (generation==nil || event.generation>generation!),event.sequence==0 else{return false}
            guard timestamp.isFinite else{throw Failure.nonFiniteTime}
            generation=event.generation;sequence=0;time=timestamp;spectating=false;lastSample=nil;releaseView();return true
        }
        guard generation==event.generation,event.sequence>sequence else{return false}
        guard timestamp.isFinite else{throw Failure.nonFiniteTime}
        switch event.command {
        case .gravity(let value):guard Commands.validGravity(value)else{throw Failure.invalidGravity}
        case .cameraPosition(let value),.cameraLookAt(let value,_):guard valid(value)else{throw Failure.invalidVector}
        case .cameraInterpolation(_,let from,let to,let duration,_):
            guard valid(from),valid(to)else{throw Failure.invalidVector};guard duration<=Int32.max else{throw Failure.invalidDuration}
        case .spectatePlayer(let id,_):guard id != .max else{throw Failure.invalidVector}
        case .spectateVehicle(let id,_):guard id>0,id != .max else{throw Failure.invalidVector}
        default:break
        }
        let now=try advance(timestamp);sequence=event.sequence;commandDiagnostics.removeAll()
        let blocked=spectating && spectator.map{$0.mode != .fixed} == true
        switch event.command {
        case .reset,.controllable,.gravity:break
        case .cameraBehind:releaseView()
        case .spectating(let value):
            if value {try takeView(at:now,seed:seed)}else{
                if spectator != nil{base=lastSample?.pose ?? raw(at:now,fallback:seed);position=nil;lookAt=nil;pendingLookAt=nil}
                spectator=nil
            }
            spectating=value
        case .spectatePlayer(let id,let mode),.spectateVehicle(let id,let mode):
            guard spectating else{commandDiagnostics.insert(.spectateNeedsEnable);return true}
            try takeView(at:now,seed:seed)
            let subject:Subject
            if case .spectatePlayer=event.command{subject = .player(id)}else{subject = .vehicle(id)}
            spectator=Spectator(subject:subject,mode:mode);position=nil;lookAt=nil;pendingLookAt=nil
        case .cameraPosition(let value):
            guard !blocked else{commandDiagnostics.insert(.cameraBlockedBySpectateMode);return true}
            try takeView(at:now,seed:seed)
            position=Track(from:value,to:value,start:now,duration:0,curve:.linear)
        case .cameraLookAt(let value,let cut):
            guard !blocked else{commandDiagnostics.insert(.cameraBlockedBySpectateMode);return true}
            try takeView(at:now,seed:seed);spectator=nil
            if cut == .cut {lookAt=Track(from:value,to:value,start:now,duration:0,curve:.linear);pendingLookAt=nil}
            else {
                let current=raw(at:now,fallback:seed)
                pendingLookAt=PendingLookAt(target:value,startedAt:now,from:current);lookAt=nil
                if let current {base?.target=current.target}
            }
        case .cameraInterpolation(let isPosition,let from,let to,let milliseconds,let cut):
            guard !blocked else{commandDiagnostics.insert(.cameraBlockedBySpectateMode);return true}
            try takeView(at:now,seed:seed)
            let track=Track(from:from,to:to,start:now,duration:Double(milliseconds)/1_000,curve:cut == .move ? .halfCosine:.linear)
            if isPosition{position=track}else{lookAt=track;pendingLookAt=nil;spectator=nil}
        }
        return true
    }
    /// Confirmed spawn is distinct from CameraBehind: it also leaves spectator mode.
    @discardableResult mutating func spawned(at timestamp:TimeInterval,generation expected:UInt64?=nil)throws->Bool {
        if let expected,expected != generation{return false};_ = try advance(timestamp);spectating=false;releaseView();return true
    }
    mutating func sample(at timestamp:TimeInterval,normal:Pose,subjectProvider:SubjectProvider={_,_ in nil})throws->Sample {
        try validateLimits();let now=try advance(timestamp)
        guard valid(normal.eye),valid(normal.target)else{throw Failure.missingNormalPose}
        var diagnostics=commandDiagnostics
        if ownsView,base==nil{base=normal;anchor=normal}
        var pose=ownsView ? (raw(at:now,fallback:normal) ?? normal):normal
        if var pending=pendingLookAt {
            if pending.from==nil{pending.from=pose;pendingLookAt=pending}
            if let from=pending.from,let move=lookAtMovePolicy?(LookAtRequest(from:from,target:pending.target,startedAt:pending.startedAt,generation:generation)) {
                guard move.duration.isFinite,move.duration>=0,move.duration<=Double(Int32.max)/1_000 else{throw Failure.invalidDuration}
                lookAt=Track(from:from.target,to:pending.target,start:pending.startedAt,duration:move.duration,curve:move.curve)
                pendingLookAt=nil;pose.target=lookAt!.at(now)
            }else{diagnostics.insert(.lookAtMovePolicyRequired)}
        }
        if spectating,let spectator {
            if let frame=subjectProvider(spectator.subject,spectator.mode) {
                guard valid(frame.focus) else{
                    diagnostics.insert(.invalidSubject)
                    let held=try safe(lastSample?.pose ?? pose,anchor:anchor ?? normal,diagnostics:&diagnostics)
                    let output=Sample(pose:held,active:ownsView,spectating:spectating,spectator:spectator,diagnostics:diagnostics,followRevision:followRevision)
                    lastSample=output;return output
                }
                switch spectator.mode {
                case .fixed:pose.target=frame.focus
                case .normal,.side:
                    let candidate=spectator.mode == .normal ? frame.normal:frame.side
                    let provenance=spectator.mode == .normal ? frame.normalProvenance:frame.sideProvenance
                    if let candidate,valid(candidate.eye),valid(candidate.target) {
                        pose=candidate
                        if provenance == .unverifiedOffsets{diagnostics.insert(.unverifiedFollow)}
                    }else{
                        diagnostics.insert(candidate == nil ? (spectator.mode == .normal ? .missingNormalFollow:.missingSideFollow):.invalidSubject)
                    }
                }
            }else{diagnostics.insert(.missingSubject)}
            if diagnostics.contains(.missingSubject) || diagnostics.contains(.invalidSubject) || diagnostics.contains(.missingNormalFollow) || diagnostics.contains(.missingSideFollow) {
                pose=lastSample?.pose ?? pose
            }
        }
        pose=try safe(pose,anchor:anchor ?? normal,diagnostics:&diagnostics)
        let output=Sample(pose:pose,active:ownsView,spectating:spectating,spectator:spectator,diagnostics:diagnostics,followRevision:followRevision)
        lastSample=output;return output
    }
    private func safe(_ raw:Pose,anchor:Pose,diagnostics:inout Set<Diagnostic>)throws->Pose {
        guard valid(raw.eye),valid(raw.target)else{throw Failure.invalidVector}
        func d(_ p:SIMD3<Float>)->SIMD3<Double>{SIMD3(Double(p.x),Double(p.y),Double(p.z))}
        func f(_ p:SIMD3<Double>)->SIMD3<Float>{SIMD3(Float(p.x),Float(p.y),Float(p.z))}
        func unit(_ p:SIMD3<Double>)->SIMD3<Double>?{let q=simd_length_squared(p);return q.isFinite && q>1e-20 ? p/sqrt(q):nil}
        let anchorDirection=unit(d(anchor.target)-d(anchor.eye)) ?? SIMD3<Double>(0,1,0)
        let anchorUp=unit(d(anchor.up)) ?? SIMD3<Double>(0,0,1)
        let anchorRight=unit(simd_cross(anchorDirection,anchorUp)) ?? SIMD3<Double>(1,0,0)
        var target=raw.target
        if simd_length_squared(d(target)-d(raw.eye))<Double(limits.minimumLookDistance)*Double(limits.minimumLookDistance) {
            diagnostics.insert(.coincidentLookAt)
            let magnitude=max(abs(Double(raw.eye.x)),abs(Double(raw.eye.y)),abs(Double(raw.eye.z)))
            let distance=max(Double(limits.minimumLookDistance),magnitude*Double(Float.ulpOfOne)*4)
            target=f(d(raw.eye)+anchorDirection*distance)
        }
        guard let direction=unit(d(target)-d(raw.eye))else{throw Failure.invalidVector}
        var up=unit(d(raw.up))
        if up==nil{up=anchorUp;diagnostics.insert(.correctedUp)}
        var right=unit(simd_cross(direction,up!))
        if right==nil {
            diagnostics.insert(.verticalUpFallback)
            right=unit(anchorRight-direction*simd_dot(direction,anchorRight))
            if right==nil {
                let reference=abs(direction.x)<0.8 ? SIMD3<Double>(1,0,0):SIMD3<Double>(0,1,0)
                right=unit(simd_cross(direction,reference))
            }
        }
        guard let right,let orthogonalUp=unit(simd_cross(right,direction))else{throw Failure.invalidVector}
        return Pose(eye:raw.eye,target:target,up:f(orthogonalUp))
    }
}
