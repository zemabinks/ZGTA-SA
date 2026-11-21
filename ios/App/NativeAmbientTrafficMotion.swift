// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// Geometry queries consumed by prediction. The production implementation is
/// the validated compact road graph; controlled scalar tests can supply small
/// invented roads without changing the predictor or original graph data.
protocol NativeAmbientTrafficGeometry {
    var linkTo:[UInt16]{get}
    func lanePoint(_ link:UInt16,lane:UInt8)throws->(position:SIMD2<Double>,direction:SIMD2<Double>)
    func speedClass(_ node:UInt16)throws->UInt8
    func height(from first:UInt16,to second:UInt16,progress:Double)throws->Double
}
extension NativeAmbientTrafficRoads:NativeAmbientTrafficGeometry {}

/// Horizontal browser-world traffic prediction, independent of local vehicle
/// driving, server AI and terrain/body fitting. All positions remain GTA XYZ.
/// Authoritative records are copied for every query: render frequency must not
/// become another acceleration/integration clock.
enum NativeAmbientTrafficMotion {
    typealias Road=NativeAmbientTraffic.RoadState
    struct Free {
        var position:SIMD3<Double>,heading:Double,speed:Double,wanted:Double,rate:Double,turn:Double
        init(_ value:NativeAmbientTrafficProtocol.Free) {
            position=value.position;heading=value.headingWire;speed=value.speed
            wanted=value.wanted;rate=value.rate;turn=value.turn
        }
    }
    struct Pose {
        var position:SIMD3<Double>,direction:SIMD2<Double>
        /// Native vehicle heading is clockwise from GTA+Y, unlike free wire
        /// heading, which is counterclockwise from GTA+X.
        var heading:Double{atan2(direction.x,direction.y)}
    }
    struct Sample {
        let free:Bool,ageMilliseconds:Double
        let pose:Pose,speed:Double
        let road:Road?,loose:Free?
    }
    /// Presentation history belongs to an entity lifetime, never its model or
    /// shared mesh. The owner must replace this value when generation changes.
    struct History {
        var shown=false,wasFree=false,lastFreeCorrection:Double?
        var offset=SIMD2<Double>.zero,yawOffset:Double=0
        var position=SIMD3<Double>.zero
    }
    enum Failure:Error{case invalidTime,invalidState,workLimit}
    static func sideRate(_ flags:UInt8)->Double{flags&16 != 0 ? 0.07:flags&4 != 0 ? 0.15:0.6}
    private static func sign(_ value:Double)->Double{value>0 ? 1:value<0 ? -1:0}
    private static func cross(_ a:SIMD2<Double>,_ b:SIMD2<Double>)->Double{a.x*b.y-a.y*b.x}
    static func intersection(_ p:SIMD2<Double>,_ u:SIMD2<Double>,_ q:SIMD2<Double>,_ v:SIMD2<Double>)->Double {
        let denominator=cross(u,v)
        return denominator==0 ? -1:-cross(p-q,v)/denominator
    }
    static func curveFactor(_ p:SIMD2<Double>,_ u:SIMD2<Double>,_ q:SIMD2<Double>,_ v:SIMD2<Double>)->Double {
        let dot=simd_dot(u,v)
        if dot<=0{return 1.0/3}
        if dot>0.7 {let distance=simd_distance(p,q);return distance==0 ? 0:abs(cross(p-q,v))/distance/3}
        return (1-dot/0.7)/3
    }
    /// Travel parameter length, not asserted to be the physical arc length.
    static func length(_ p:SIMD2<Double>,_ u:SIMD2<Double>,_ q:SIMD2<Double>,_ v:SIMD2<Double>)->Double {
        let first=intersection(p,u,q,v),second=intersection(q,-v,p,u)
        if first>0 && second>0{return first+second}
        return simd_distance(p,q)/(1-curveFactor(p,u,q,v))
    }
    /// Raw curve parameter is intentionally not clamped here. Position()
    /// clamps the selected road progress at the actual presentation boundary.
    static func curve(_ p:SIMD2<Double>,_ u:SIMD2<Double>,_ q:SIMD2<Double>,_ v:SIMD2<Double>,progress:Double)->SIMD2<Double> {
        let first=intersection(p,u,q,v),second=intersection(q,-v,p,u)
        if first>0 && second>0 {
            let corner=min(5,min(first,second)),entry=first-corner,exit=second-corner
            let total=entry+2*corner+exit,distance=progress*total
            if distance<entry{return p+u*distance}
            if distance>entry+2*corner{return q+v*(distance-total)}
            let t=(distance-entry)/(2*corner)
            let a=p+u*(entry+corner*t),b=q-v*(exit+corner*(1-t))
            return a+(b-a)*t
        }
        let distance=simd_distance(p,q),factor=curveFactor(p,u,q,v),total=distance/(1-factor),at=progress*total
        let blend=total<1e-5 ? 0.5:0.5-0.5*cos(Double.pi*at/total)
        let travel=total<1e-5 ? 0:total/(2*Double.pi)*sin(2*Double.pi*at/total)*factor+(1-factor)*at
        let a=p+u*travel,b=q+v*(travel-distance)
        return a+(b-a)*blend
    }
    static func advance(_ state:inout Free,seconds:Double)throws {
        guard seconds.isFinite else{throw Failure.invalidTime}
        guard seconds>0 else{return}
        // Live sample age is at most6.5s. Keep a bounded work policy for direct
        // callers rather than converting an unbounded Double to an Int.
        guard seconds<=60 else{throw Failure.workLimit}
        guard [state.position.x,state.position.y,state.position.z,state.heading,state.speed,state.wanted,state.rate,state.turn].allSatisfy(\.isFinite)else{throw Failure.invalidState}
        let count=Int(ceil(seconds/0.05)),step=seconds/Double(count),acceleration=max(0.05,state.rate)
        for _ in 0..<count {
            let next=state.wanted>state.speed ? min(state.wanted,state.speed+acceleration*step):max(state.wanted,state.speed-acceleration*step)
            let speed=(state.speed+next)/2,turn=state.turn*step*min(1,speed),middle=state.heading+turn/2
            state.position.x+=speed*step*cos(middle);state.position.y+=speed*step*sin(middle)
            state.heading+=turn;state.speed=next
        }
    }
    private static func endpoints(_ state:Road,_ geometry:some NativeAmbientTrafficGeometry)throws->(SIMD2<Double>,SIMD2<Double>,SIMD2<Double>,SIMD2<Double>) {
        let a=try geometry.lanePoint(state.first.link,lane:state.first.lane)
        let b=try geometry.lanePoint(state.second.link,lane:state.second.lane)
        return(a.position,a.direction,b.position,b.direction)
    }
    static func advance(_ state:inout Road,seconds:Double,geometry:some NativeAmbientTrafficGeometry)throws {
        guard seconds.isFinite else{throw Failure.invalidTime}
        guard seconds>0 else{return}
        guard seconds<=60 else{throw Failure.workLimit}
        guard [state.progress,state.speed,state.wanted,state.rate,state.side,state.aim].allSatisfy(\.isFinite)else{throw Failure.invalidState}
        let acceleration=max(0.05,state.rate),reach=abs(state.wanted-state.speed)/acceleration
        let next:Double,distance:Double
        if seconds<reach {
            next=state.speed+sign(state.wanted-state.speed)*acceleration*seconds
            distance=(state.speed+next)*seconds/2
        }else{
            next=state.wanted;distance=(state.speed+state.wanted)*reach/2+state.wanted*(seconds-reach)
        }
        state.speed=next
        state.side+=sign(state.aim-state.side)*min(abs(state.aim-state.side),sideRate(state.flags)*distance)
        var (p,u,q,v)=try endpoints(state,geometry)
        var travel=length(p,u,q,v)
        state.progress+=distance/max(0.01,travel)
        var transitions=0
        while state.progress>=1,let next=state.next {
            transitions+=1;guard transitions<=4097 else{throw Failure.workLimit}
            let excess=(state.progress-1)*travel
            state.first=state.second;state.second=next
            if state.taken<state.ahead.count {
                state.next=state.ahead[state.taken];state.nextLane=state.next!.lane;state.taken+=1
            }else{state.next=nil}
            (p,u,q,v)=try endpoints(state,geometry)
            if state.first.lane != state.second.lane,state.aim==0,simd_dot(u,v)>0.95 {
                let shift=Double(Int(state.first.lane)-Int(state.second.lane))*5.4
                if abs(state.side+shift)<=7.5 {
                    state.first = .init(link:state.first.link,lane:state.second.lane);state.side+=shift
                    guard Int(state.first.link)<geometry.linkTo.count else{throw Failure.invalidState}
                    let fast=try geometry.speedClass(geometry.linkTo[Int(state.first.link)])==2
                    state.flags=(state.flags & ~20)|4|(fast ? 16:0)
                    (p,u,q,v)=try endpoints(state,geometry)
                }
            }
            travel=length(p,u,q,v);state.progress=excess/max(0.01,travel)
        }
        if state.progress>1{state.progress=1}
    }
    static func position(_ state:Road,geometry:some NativeAmbientTrafficGeometry)throws->Pose {
        let (p,u,q,v)=try endpoints(state,geometry),t=min(1,max(0,state.progress))
        let location=curve(p,u,q,v,progress:t)
        let difference=curve(p,u,q,v,progress:min(1,state.progress+0.01))-curve(p,u,q,v,progress:max(0,state.progress-0.01))
        var tangent=difference,magnitude=simd_length(difference)
        if magnitude<1e-6{tangent=u+(v-u)*state.progress;magnitude=simd_length(tangent)}
        tangent=magnitude==0 ? SIMD2(1,0):tangent/magnitude
        let xy=location+SIMD2(tangent.y,-tangent.x)*state.side
        let z=try geometry.height(from:state.first.link,to:state.second.link,progress:t)
        return .init(position:SIMD3(xy.x,xy.y,z),direction:tangent)
    }
    static func select(_ actor:NativeAmbientTraffic.Actor,serverNow:Double,wasFree:Bool,geometry:some NativeAmbientTrafficGeometry)throws->Sample? {
        guard serverNow.isFinite,actor.baseAt.isFinite else{throw Failure.invalidTime}
        if serverNow-actor.baseAt>6500{return nil}
        if let free=actor.free,let at=actor.freeAt,(at>=actor.baseAt || (wasFree && serverNow-actor.baseAt<250)) {
            var work=Free(free);try advance(&work,seconds:(serverNow-at)/1000)
            let pose=Pose(position:work.position,direction:SIMD2(cos(work.heading),sin(work.heading)))
            // Mode hysteresis/staleness use the base sample's age. Free
            // prediction has its own timestamp, including during hysteresis.
            return .init(free:true,ageMilliseconds:serverNow-actor.baseAt,pose:pose,speed:work.speed,road:nil,loose:work)
        }
        var work=actor.road;try advance(&work,seconds:(serverNow-actor.baseAt)/1000,geometry:geometry)
        return .init(free:false,ageMilliseconds:serverNow-actor.baseAt,pose:try position(work,geometry:geometry),speed:work.speed,road:work,loose:nil)
    }
    /// Smooth only horizontal snapshot discontinuities. Height, suspension,
    /// terrain pitch and collision ownership need their separate native owner.
    static func present(_ actor:inout NativeAmbientTraffic.Actor,history:inout History,serverNow:Double,renderDelta:Double,geometry:some NativeAmbientTrafficGeometry)throws->(sample:Sample,pose:Pose)? {
        guard renderDelta.isFinite,renderDelta>=0 else{throw Failure.invalidTime}
        guard let sample=try select(actor,serverNow:serverNow,wasFree:history.wasFree,geometry:geometry)else{return nil}
        let xy=SIMD2(sample.pose.position.x,sample.pose.position.y)
        if actor.fresh || sample.free != history.wasFree {
            if sample.free,history.wasFree,let previous=actor.freeBefore,let at=actor.freeBeforeAt,let current=sample.loose {
                if history.lastFreeCorrection != actor.freeAt {
                    var before=Free(previous);try advance(&before,seconds:(serverNow-at)/1000)
                    history.offset+=SIMD2(before.position.x,before.position.y)-xy
                    let turn=before.heading-current.heading
                    history.yawOffset+=atan2(sin(turn),cos(turn))
                    history.lastFreeCorrection=actor.freeAt
                    if simd_length(history.offset)>8{history.offset = .zero}
                    if abs(history.yawOffset)>0.8{history.yawOffset=0}
                }
            }else if !sample.free && !history.wasFree, var before=actor.before,let at=actor.beforeAt {
                try advance(&before,seconds:(serverNow-at)/1000,geometry:geometry)
                let old=try position(before,geometry:geometry)
                history.offset+=SIMD2(old.position.x,old.position.y)-xy
                if simd_length(history.offset)>8{history.offset = .zero}
            }else if history.shown {
                history.offset=SIMD2(history.position.x,history.position.y)-xy
            }
            if sample.free{history.lastFreeCorrection=actor.freeAt}
            actor.fresh=false;history.wasFree=sample.free
        }
        let decay=exp(-renderDelta/0.25)
        history.offset*=decay;history.yawOffset=sample.free ? history.yawOffset*decay:0
        history.position=sample.pose.position+SIMD3(history.offset.x,history.offset.y,0)
        var pose=sample.pose;pose.position=history.position
        if sample.free,let free=sample.loose{pose.direction=SIMD2(cos(free.heading+history.yawOffset),sin(free.heading+history.yawOffset))}
        return(sample,pose)
    }
}
