// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Authoritative traffic record ownership. Road geometry, presentation and
/// traffic AI remain separate. In particular, a free update cannot invent a
/// car and traffic occupants never become human player roster entries.
final class NativeAmbientTraffic {
    typealias Wire=NativeAmbientTrafficProtocol
    struct RoadState {
        var first:Wire.Leg,second:Wire.Leg,next:Wire.Leg?,nextLane:UInt8
        var progress:Double,speed:Double,wanted:Double,rate:Double
        var side:Double=0,aim:Double=0,flags:UInt8=0
        var ahead:[Wire.Leg]=[],taken=0
        init(_ base:Wire.Base) {
            first=base.first;second=base.second;next=base.next;nextLane=base.nextLane
            progress=base.progress;speed=base.speed;wanted=base.wanted;rate=base.rate
        }
    }
    struct Actor {
        let identity:Wire.Identity,generation:UInt64
        var road:RoadState,baseAt:Double,received:Double
        var fresh=true,before:RoadState?,beforeAt:Double?
        var health:Double=1000,flags:UInt8=0
        var crewCount:UInt8?,deadSeats:UInt8=0
        var free:Wire.Free?,freeAt:Double?,freeBefore:Wire.Free?,freeBeforeAt:Double?
        var targetID:String{"t\(identity.id)"}
        func occupantTargetID(seat:Int)->String?{(0...2).contains(seat) ? "c\(identity.id).\(seat)":nil}
        mutating func captureBefore() {
            if !fresh && baseAt != 0{before=road;beforeAt=baseAt;fresh=true}
        }
    }
    private(set) var level:Double=0
    private(set) var roadsHash:String?
    private(set) var graph:NativeAmbientTrafficRoads?
    private(set) var actors:[UInt16:Actor]=[:]
    private var actorOrder:[UInt16]=[]
    private(set) var plates:[UInt16:String]=[:]
    private var plateOrder:[UInt16]=[]
    private var generation:UInt64=0

    func reset() {
        actors.removeAll();actorOrder.removeAll();plates.removeAll();plateOrder.removeAll()
        level=0;roadsHash=nil;graph=nil
    }
    /// Geometry changes retire actors; disabling level retains the matching
    /// geometry and plate cache within this connection. Full disconnect/source
    /// replacement must call reset(), including the independent plate cache.
    @discardableResult func configure(level:Double,roads:String?)->Bool {
        if let roads,roads != roadsHash{roadsHash=roads;graph=nil;actors.removeAll();actorOrder.removeAll()}
        self.level=level.isFinite ? level:0
        if self.level<=0{actors.removeAll();actorOrder.removeAll()}
        guard self.level>0,let hash=roadsHash,hash.utf8.count==8,
              hash.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)})else{return false}
        return graph==nil
    }
    @discardableResult func install(_ graph:NativeAmbientTrafficRoads)->Bool {
        guard graph.crc32==roadsHash else{return false};self.graph=graph;return true
    }
    /// A frame consumer calls this only for actors it actually presented.
    /// Following metadata can then retain the previous authoritative sample.
    func markPresented(_ ids:[UInt16]){for id in ids{actors[id]?.fresh=false}}
    func snapshots(serverNow:Double)->[Actor] {
        guard serverNow.isFinite,serverNow>0,graph != nil else{return []}
        for (id,actor) in actors where serverNow-actor.baseAt>6500{actors[id]=nil}
        actorOrder.removeAll{actors[$0]==nil}
        return actorOrder.compactMap{actors[$0]}
    }
    /// Returns shot observations for a separate visible/ranged effects owner.
    /// These are not damage instructions and never alter health themselves.
    @discardableResult func receive(_ event:Wire.Event,serverNow:Double,received:Double)->[Wire.Shot] {
        guard serverNow.isFinite,received.isFinite else{return []}
        switch event {
        case .base(let time,let values):
            guard level>0,serverNow>0,time.isFinite,let graph else{return []}
            for value in values {
                guard Int(value.first.link)<graph.linkCount,Int(value.second.link)<graph.linkCount,
                      value.next.map({Int($0.link)<graph.linkCount}) ?? true else{continue}
                let old=actors[value.identity.id]
                if old?.identity != value.identity {
                    guard old != nil || actors.count<4096 else{continue}
                    if old==nil{actorOrder.append(value.identity.id)}
                    generation &+= 1;if generation==0{generation=1}
                    actors[value.identity.id]=Actor(identity:value.identity,generation:generation,
                        road:RoadState(value),baseAt:time,received:received)
                }else if var actor=old {
                    actor.captureBefore()
                    // Preserve side/aim/flags and crew across ordinary base
                    // rows; ahead is a new route window. Older base stamps
                    // still replace the base, as observed on this channel.
                    let side=actor.road.side,aim=actor.road.aim,flags=actor.road.flags
                    actor.road=RoadState(value);actor.road.side=side;actor.road.aim=aim;actor.road.flags=flags
                    actor.baseAt=time;actor.received=received;actor.fresh=true;actors[value.identity.id]=actor
                }
            }
        case .gone(let ids):
            for id in ids{actors[id]=nil}
            actorOrder.removeAll{actors[$0]==nil}
        case .plates(let values):
            for value in values {
                plates[value.id]=value.text;plateOrder.removeAll{$0==value.id};plateOrder.append(value.id)
                if plateOrder.count>600{plates[plateOrder.removeFirst()]=nil}
            }
        case .more(let values):
            for value in values where actors[value.id] != nil {
                var actor=actors[value.id]!;actor.captureBefore()
                actor.road.side=value.side;actor.road.aim=value.aim;actor.road.flags=value.flags
                actor.health=value.health;actor.flags=value.flags;actors[value.id]=actor
            }
        case .fast(let values):
            for value in values where actors[value.id] != nil {
                var actor=actors[value.id]!;actor.captureBefore()
                actor.road.speed=value.speed;actor.road.wanted=value.wanted;actors[value.id]=actor
            }
        case .crew(let values):
            for value in values where actors[value.id] != nil{actors[value.id]?.crewCount=value.count;actors[value.id]?.deadSeats=value.deadSeats}
        case .ahead(let values):
            guard let graph else{return []}
            for value in values where actors[value.id] != nil {
                var actor=actors[value.id]!;actor.captureBefore()
                actor.road.ahead=Array(value.legs.prefix{Int($0.link)<graph.linkCount});actor.road.taken=0;actors[value.id]=actor
            }
        case .free(let time,let values):
            guard serverNow>0,time.isFinite else{return []}
            for value in values where actors[value.id] != nil {
                var actor=actors[value.id]!
                if actor.free != nil{actor.freeBefore=actor.free;actor.freeBeforeAt=actor.freeAt}
                actor.free=value;actor.freeAt=time;actor.fresh=true;actors[value.id]=actor
            }
        case .shots(let values):return values.filter{actors[$0.id] != nil}
        }
        return []
    }
}
