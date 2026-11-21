// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Server-owned NPCs. Nothing here invents actors, goals, health or player rows.
/// Clocks: wire samples use server epoch milliseconds; display uses monotonic
/// seconds. Reconnection/path changes retire the complete previous namespace.
final class NativeAmbientPedestrians {
    typealias Wire=NativeAmbientPedestrianProtocol
    struct Frame {
        let id:UInt16,skin:UInt16,seed:UInt8,flags:UInt8
        let position:SIMD3<Double>,velocity:SIMD3<Double>,heading:Double
        let state:Wire.State?
        // Local admission lifetime; never changes the wire target namespace.
        var generation:UInt64=0
        var admittedAt:Double=0
        // nil means free motion/no next edge. An existing next edge with no
        // matching graph link uses kind0, matching the graph query fallback.
        var waitingLinkKind:UInt8?=nil
        var targetID:String{"p\(id)"}
        var dead:Bool{flags&8 != 0}
        var down:Bool{flags&1 != 0}
        var panicking:Bool{flags&4 != 0}
    }
    struct Motion {
        var waitingLinkKind:UInt8?=nil
        var free:Wire.Free?
        var path:Wire.Path?
        var speed:Double
        /// Exact constant-acceleration distance; independent of display rate.
        static func travel(speed:Double,wanted:Double,seconds:Double)->(Double,Double) {
            guard seconds>0 else{return(0,speed)}
            let change=abs(wanted-speed)/4,accelerating=min(seconds,change)
            let next=speed+(wanted>=speed ? 4:-4)*accelerating
            return((speed+next)*0.5*accelerating+wanted*max(0,seconds-change),next)
        }
        mutating func advance(_ seconds:Double,graph:NativeAmbientPedestrianPaths)throws->(SIMD3<Double>,SIMD2<Double>) {
            waitingLinkKind=nil
            if let value=free {
                let delta=value.goal-SIMD2(value.feet.x,value.feet.y),length=simd_length(delta)
                let (distance,next)=Self.travel(speed:speed,wanted:value.desiredSpeed,seconds:seconds)
                let travelled=min(length,distance),direction=length>1e-9 ? delta/length:.zero
                let xy=SIMD2(value.feet.x,value.feet.y)+direction*travelled
                speed=length<=distance || length<1e-9 ? 0:next
                return(SIMD3(xy.x,xy.y,value.feet.z),length-travelled<0.05 ? .zero:direction)
            }
            guard var value=path else{throw NativeAmbientPedestrianPaths.Failure.malformed}
            let (distance,nextSpeed)=Self.travel(speed:speed,wanted:value.desiredSpeed,seconds:seconds);speed=nextSpeed
            var a=try graph.place(value.from,seed:value.identity.seed),b=try graph.place(value.to,seed:value.identity.seed)
            var edge=SIMD2(b.x-a.x,b.y-a.y),length=max(0.01,simd_length(edge))
            var progress=value.progress+distance/length
            let side=value.side+min(abs(value.desiredSide-value.side),0.8*distance)*(value.desiredSide>=value.side ? 1:-1)
            if progress>=1,let next=value.next {
                let remaining=(progress-1)*length
                value = .init(identity:value.identity,from:value.to,to:next,next:nil,progress:0,
                    speed:value.speed,desiredSpeed:value.desiredSpeed,side:side,desiredSide:value.desiredSide)
                a=try graph.place(value.from,seed:value.identity.seed);b=try graph.place(value.to,seed:value.identity.seed)
                edge=SIMD2(b.x-a.x,b.y-a.y);length=max(0.01,simd_length(edge));progress=remaining/length
            }
            if let next=value.next {
                waitingLinkKind=try graph.neighbors(value.to).first{$0.id==next}?.kind ?? 0
            }
            progress=min(1,progress)
            let direction=edge/length
            return(a+(b-a)*progress+SIMD3(side*direction.y,-side*direction.x,0),direction)
        }
    }
    private struct Actor {
        var identity:Wire.Identity,motion:Motion,serverAt:Double,received:Double
        var generation:UInt64
        var state:Wire.State?,residual=SIMD3<Double>.zero,correctionAt:Double
        var heading:Double?,lastDisplay:Double?
        var admittedAt:Double,arrivalUntil:Double?
    }
    private(set) var pathsHash:String?
    private(set) var level:Double=0
    private(set) var graph:NativeAmbientPedestrianPaths?
    private var actors:[UInt16:Actor]=[:]
    private var generation:UInt64=0
    private var pending:[(Wire.Event,Double,Double)]=[]
    private var pendingCount=0
    var count:Int{actors.count}
    func contains(id:UInt16,generation:UInt64)->Bool{actors[id]?.generation==generation}
    func reset(){actors.removeAll();pending.removeAll();pendingCount=0;graph=nil;pathsHash=nil;level=0}
    @discardableResult func configure(level:Double,paths:String?)->Bool {
        let hash=paths ?? pathsHash
        guard level.isFinite,level>0,let hash,hash.utf8.count==8,
              hash.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)})else{reset();return false}
        let changed=hash != pathsHash
        if changed {reset();pathsHash=hash}
        self.level=level;return changed || graph==nil
    }
    @discardableResult func install(_ value:NativeAmbientPedestrianPaths)->Bool {
        guard level>0,value.crc32==pathsHash else{return false}
        graph=value;let waiting=pending;pending.removeAll();pendingCount=0
        for (event,serverNow,received) in waiting{receive(event,serverNow:serverNow,received:received)}
        return true
    }
    func receive(_ event:Wire.Event,serverNow:Double,received:Double) {
        guard level>0,pathsHash != nil,serverNow.isFinite,received.isFinite else{return}
        guard let graph else {
            let count:Int
            switch event{case .free(_,let v):count=v.count;case .path(_,let v):count=v.count;case .gone(let v):count=v.count;case .state(let v):count=v.count}
            // Bounded retention while the verified graph loads. Overflow
            // clears the batch; subsequent authoritative refreshes repopulate.
            if pending.count>=64 || pendingCount+count>4096{pending.removeAll();pendingCount=0}
            guard count<=4096 else{return}
            pending.append((event,serverNow,received));pendingCount+=count;return
        }
        switch event {
        case .gone(let ids):for id in ids{actors[id]=nil}
        case .state(let values):for state in values{if actors[state.id] != nil{actors[state.id]?.state=state}}
        case .free(let time,let values):
            for value in values {admit(identity:value.identity,motion:.init(free:value,speed:value.speed),time:time,serverNow:serverNow,received:received,graph:graph)}
        case .path(let time,let values):
            for value in values {
                // A complete row is validated before admission. A corrupt
                // path must not create a partially positioned actor.
                guard (try? graph.point(value.from)) != nil,(try? graph.point(value.to)) != nil,
                      value.next.map({(try? graph.point($0)) != nil}) ?? true else{continue}
                admit(identity:value.identity,motion:.init(path:value,speed:value.speed),time:time,serverNow:serverNow,received:received,graph:graph)
            }
        }
    }
    private func predicted(_ actor:Actor,at time:Double,graph:NativeAmbientPedestrianPaths)->(SIMD3<Double>,SIMD2<Double>,Double,UInt8?)? {
        var motion=actor.motion
        // Convert receipt to monotonic once; wall-clock adjustments cannot
        // move an already admitted timeline backwards during presentation.
        let seconds=actor.identity.flags&9 != 0 ? 0:max(0,time-actor.received)
        guard let (position,direction)=try? motion.advance(min(9,seconds),graph:graph)else{return nil}
        let elapsed=max(0,time-actor.correctionAt)
        let slow=max(0,min(elapsed,(actor.arrivalUntil ?? actor.correctionAt)-actor.correctionAt))
        let correction=actor.residual*exp(-slow/0.6-(elapsed-slow)/0.3)
        return(position+correction,direction,motion.speed,motion.waitingLinkKind)
    }
    private func admit(identity:Wire.Identity,motion:Motion,time:Double,serverNow:Double,received:Double,graph:NativeAmbientPedestrianPaths) {
        guard time.isFinite,serverNow-time<=9000,time-serverNow<=2000 else{return}
        let old=actors[identity.id]
        if let old,time<=old.serverAt{return}
        if old==nil && actors.count>=4096{return}
        let same=old?.identity.skin==identity.skin && old?.identity.seed==identity.seed
        if !same{generation &+= 1;if generation==0{generation=1}}
        let lifetime=same ? old!.generation:generation
        // Retain packet age in the monotonic origin; clamp small future skew.
        var value=Actor(identity:identity,motion:motion,serverAt:time,received:received-max(0,serverNow-time)/1000,generation:lifetime,
            state:same ? old?.state:nil,correctionAt:received,heading:same ? old?.heading:nil,lastDisplay:same ? old?.lastDisplay:nil,
            admittedAt:same ? old!.admittedAt:received,arrivalUntil:same ? old?.arrivalUntil:nil)
        if same,let old,let before=predicted(old,at:received,graph:graph),let after=predicted(value,at:received,graph:graph) {
            var residual=before.0-after.0;residual.z=0
            if simd_length(residual)<=(received<(value.arrivalUntil ?? received) ? 12:5){value.residual=residual}
        }
        actors[identity.id]=value
    }
    /// Adopt a completed rider only into the same existing NPC generation.
    /// This changes local correction/facing, never authoritative goals/flags.
    @discardableResult func acceptRider(id:UInt16,generation:UInt64,feet:SIMD3<Double>,heading:Double,at time:Double)->Bool {
        guard time.isFinite,heading.isFinite,feet.x.isFinite,feet.y.isFinite,feet.z.isFinite,
              var actor=actors[id],actor.generation==generation,let graph else{return false}
        var uncorrected=actor;uncorrected.residual = .zero
        guard let point=predicted(uncorrected,at:time,graph:graph)?.0 else{return false}
        var correction=feet-point;correction.z=0
        if simd_length(correction)>12{correction = .zero}
        actor.residual=correction;actor.correctionAt=time;actor.arrivalUntil=time+1.5
        actor.heading=heading;actor.lastDisplay=time;actors[id]=actor
        return true
    }
    func frames(at time:Double,near origin:SIMD3<Double>,active:Bool=true,maximum:Int=40,
                turningRate:(UInt16)->Double={_ in 6.5})->[Frame] {
        guard active,time.isFinite,let graph else{for id in actors.keys{actors[id]?.lastDisplay=nil};return[]}
        for (id,actor) in actors where time-actor.received>9 || time<actor.received-2{actors[id]=nil}
        let ordered=actors.compactMap{ id,actor -> (UInt16,Double)? in
            guard let point=predicted(actor,at:time,graph:graph)?.0 else{return nil}
            return(id,simd_length_squared(point-origin))
        }.sorted{$0.1==$1.1 ? $0.0<$1.0:$0.1<$1.1}.map{$0.0}
        var result:[Frame]=[]
        for id in ordered.prefix(max(0,min(40,maximum))) {
            guard var actor=actors[id],let (position,direction,speed,waitingLinkKind)=predicted(actor,at:time,graph:graph),
                  simd_distance(position,origin)<110 else{continue}
            let mood=actor.state?.mood ?? 0
            let stopped=simd_length_squared(direction)<1e-9 || (speed<0.2 && mood != 0 && mood != 7)
            // Wire face is counterclockwise from GTA +X; native heading is
            // clockwise from GTA +Y. No CPed or Three.js axis conversion here.
            let desired=stopped ? .pi/2-(actor.state?.faceWire ?? 0):atan2(direction.x,direction.y)
            // A fallen body retains its last facing while authoritative
            // goals/face updates continue. Only an upright task may steer.
            if actor.identity.flags&1 == 0 || actor.heading==nil {
                if let heading=actor.heading,let previous=actor.lastDisplay,time>=previous,time-previous<=0.5 {
                    let supplied=turningRate(actor.identity.skin)
                    let rate=supplied.isFinite && supplied>0 && supplied<=100 ? supplied:6.5
                    let change=atan2(sin(desired-heading),cos(desired-heading)),amount=rate*(time-previous)
                    actor.heading=heading+max(-amount,min(amount,change))
                }else{actor.heading=desired}
            }
            actor.lastDisplay=time;actors[id]=actor
            let travelDirection=simd_length_squared(direction)<1e-9 ? SIMD2(cos(actor.state?.faceWire ?? 0),sin(actor.state?.faceWire ?? 0)):direction
            let velocity=actor.identity.flags&9 != 0 ? .zero:SIMD3(travelDirection.x*speed,travelDirection.y*speed,0)
            result.append(.init(id:id,skin:actor.identity.skin,seed:actor.identity.seed,flags:actor.identity.flags,
                position:position,velocity:velocity,heading:actor.heading ?? desired,state:actor.state,
                generation:actor.generation,admittedAt:actor.admittedAt,waitingLinkKind:waitingLinkKind))
        }
        return result
    }
}
