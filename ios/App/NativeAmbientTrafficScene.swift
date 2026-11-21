// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Connection-owned traffic presentation. Authoritative records and prediction
/// remain separate; a registered car suppresses its compact traffic source.
/// This does not acquire physics ownership or invent traffic/server AI.
final class NativeAmbientTrafficScene {
    typealias Wire=NativeAmbientTrafficProtocol
    struct Frame {
        let identity:Wire.Identity,generation:UInt64
        let body:NativeAmbientTrafficPresentation.Output
        let speed:Double,health:Double
        let flags:UInt8,crewCount:UInt8?,deadSeats:UInt8,plate:String?
        var code:String{"\(identity.model).\(identity.first).\(identity.second).0."}
    }
    private struct Pending {let event:Wire.Event,now:Double,received:Double}
    private struct State {
        let generation:UInt64
        var motion=NativeAmbientTrafficMotion.History()
        var body=NativeAmbientTrafficPresentation(),time:Double?
    }
    let traffic=NativeAmbientTraffic()
    private(set) var source:String?
    private(set) var pendingCount=0,overflowCount=0
    private var pending:[Pending]=[],pendingRecords=0
    private var anchor:(server:Double,local:Double)?
    private var states:[UInt16:State]=[:],staged:[UInt16:State]=[:]
    private var counter=0
    static let maximumPendingEvents=256,maximumPendingRecords=16384

    func reset() {
        traffic.reset();source=nil;pending=[];pendingCount=0;pendingRecords=0
        anchor=nil;states=[:];staged=[:];counter=0;overflowCount=0
    }
    @discardableResult func configure(level:Double,roads:String?,source:String)->Bool {
        if self.source != source{reset();self.source=source}
        let previous=traffic.roadsHash
        let needed=traffic.configure(level:level,roads:roads)
        if previous != traffic.roadsHash || traffic.level<=0 {
            pending=[];pendingCount=0;pendingRecords=0;states=[:];staged=[:]
            if traffic.level<=0{anchor=nil}
        }
        return needed
    }
    @discardableResult func install(_ graph:NativeAmbientTrafficRoads)->Bool {
        guard traffic.level>0,traffic.install(graph)else{return false}
        let buffered=pending;pending=[];pendingCount=0;pendingRecords=0
        for value in buffered{traffic.receive(value.event,serverNow:value.now,received:value.received)}
        return true
    }
    /// Bound initial records while the asynchronous graph load is pending.
    /// Delayed shots are deliberately not replayed as fresh visual effects.
    func receive(_ event:Wire.Event,serverNow:Double,received:Double) {
        guard traffic.level>0,traffic.roadsHash != nil,serverNow.isFinite,serverNow>0,received.isFinite else{return}
        staged=[:]
        anchor=(serverNow,received)
        guard traffic.graph==nil else{traffic.receive(event,serverNow:serverNow,received:received);return}
        if case .shots=event{return}
        guard event.count<=Self.maximumPendingRecords else{return}
        if pending.count>=Self.maximumPendingEvents || pendingRecords+event.count>Self.maximumPendingRecords {
            // Retire an incomplete prefix as one unit. Metadata alone can
            // never create a car; a subsequent base must establish it again.
            pending=[];pendingRecords=0;overflowCount+=1
        }
        pending.append(.init(event:event,now:serverNow,received:received))
        pendingRecords+=event.count;pendingCount=pending.count
    }
    /// Model readiness supplies original dimensions. Missing models are not
    /// replaced with decorative geometry. State is staged until a draw occurs.
    func frames(at time:Double,near:SIMD3<Double>,active:Bool,promoted:Set<UInt16>,
                length:(UInt16)->Double?,ray:NativeAmbientTrafficPresentation.DownRay?)->[Frame] {
        staged=[:]
        guard active,time.isFinite,near.x.isFinite,near.y.isFinite,near.z.isFinite,
              let anchor,time>=anchor.local,let graph=traffic.graph else{
            for id in states.keys{states[id]?.time=nil};return []
        }
        let now=anchor.server+(time-anchor.local)*1000
        let actors=traffic.snapshots(serverNow:now)
        let live=Set(actors.map{$0.identity.id}).subtracting(promoted)
        states=states.filter{live.contains($0.key)}
        if counter==Int.max{states=[:];counter=0};counter+=1
        var result:[Frame]=[]
        for var actor in actors where !promoted.contains(actor.identity.id) {
            let id=actor.identity.id
            var work=states[id].flatMap{$0.generation==actor.generation ? $0:nil} ?? State(generation:actor.generation)
            let delta=work.time.map{min(0.25,max(0,time-$0))} ?? 0
            guard let sample=try? NativeAmbientTrafficMotion.present(&actor,history:&work.motion,
                serverNow:now,renderDelta:delta,geometry:graph),
                simd_distance(sample.pose.position,near)<130,let length=length(actor.identity.model),length.isFinite,length>0 else{continue}
            let point=sample.sample.pose.position,direction=sample.sample.pose.direction
            let input=NativeAmbientTrafficPresentation.Input(id:id,frame:counter,position:SIMD2(point.x,point.y),
                direction:direction,baseline:point.z,length:length,distance:simd_distance(point,near),delta:delta,
                free:sample.sample.free,freePosition:actor.free.map{SIMD2($0.position.x,$0.position.y)},freeStamp:actor.freeAt,
                speed:sample.sample.speed,side:sample.sample.road?.side ?? actor.road.side,
                aim:sample.sample.road?.aim ?? actor.road.aim,flags:sample.sample.road?.flags ?? actor.flags,
                residual:work.motion.offset,yawResidual:work.motion.yawOffset)
            guard let body=try? work.body.update(input,ray:ray)else{continue}
            work.time=time;staged[id]=work
            result.append(.init(identity:actor.identity,generation:actor.generation,body:body,
                speed:sample.sample.speed,health:actor.health,flags:actor.flags,
                crewCount:actor.crewCount,deadSeats:actor.deadSeats,plate:traffic.plates[id]))
        }
        return result
    }
    /// Called by the actual mesh draw, not by a timer/model request. Failed
    /// or culled candidates do not accumulate correction/wheel history.
    func didPresent(_ id:UInt16,generation:UInt64) {
        guard var work=staged[id],work.generation==generation,
              traffic.actors[id]?.generation==generation else{return}
        work.motion.shown=true;states[id]=work;staged[id]=nil;traffic.markPresented([id])
    }
}
