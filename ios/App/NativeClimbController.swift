import Foundation
import simd

/// Independently written native candidate. Coordinates are original Rapier
/// Y-up. Authority is the archived browser implementation, not retail GTA SA.
final class NativeClimbController {
    typealias V = SIMD3<Double>
    enum Part:Int {case jump=20,hang=21,pull=22,edge=23,stand=24,vault=25}
    enum End:String {case drop,top,over}
    struct Durations {var jump:Double;var pull:Double;var stand:Double;var vault:Double}
    struct Ledge {var hold:V;var into:V;var heading:Double;var high:Bool;var vault:Bool;var fixed:Bool=true}
    private(set) var feet:V
    private(set) var part:Part
    let heading:Double
    private let ledge:Ledge
    private let durations:Durations
    private let hanging:V,edge:V,standing:V,over:V
    private var elapsed=0.0,unsettled=0.0
    private var displacement=V.zero
    init(ledge:Ledge,feet:V,durations:Durations) {
        self.ledge=ledge;self.feet=feet;self.durations=durations;heading=ledge.heading
        part=ledge.high ? .jump:.edge
        func point(_ forward:Double,_ vertical:Double)->V {
            var p=ledge.hold+ledge.into*forward;p.y=ledge.hold.y+vertical-1;return p
        }
        hanging=point(-0.4,-1.1);edge=point(-0.4,0);standing=point(0.15,1);over=point(0.5,0)
    }
    private func approach(_ target:V,_ delta:Double)->Bool {
        displacement=target-feet
        let distance=simd_length(displacement)
        if distance>0.0001 {
            feet += displacement*min(1,min(distance*(1-pow(0.75,50*delta)),10*delta)/distance)
        }
        return distance<0.316
    }
    private func select(_ part:Part) {self.part=part;elapsed=0}
    func step(delta:Double,pull:Bool,drop:Bool)->End? {
        elapsed += delta
        if drop {return .drop}
        switch part {
        case .jump,.hang:
            let close=approach(hanging,delta)
            unsettled=close ? 0:unsettled+delta
            if unsettled>(part == .jump ? 1+durations.jump:0.5) {return .drop}
            if part == .jump && elapsed>=durations.jump && close {
                if pull {feet=hanging}
                select(pull ? .pull:.hang)
            } else if part == .hang && pull && close && elapsed>=0.25 {
                feet=hanging;select(.pull)
            }
        case .pull:
            if elapsed>=durations.pull {feet=edge;select(ledge.vault ? .vault:.stand)}
        case .edge:
            if approach(edge,delta) && simd_length(displacement)<0.06 {
                feet=edge;select(ledge.vault ? .vault:.stand)
            } else if elapsed>1 {return .drop}
        case .stand:
            if elapsed>=durations.stand {feet=standing;return .top}
        case .vault:
            if elapsed>=durations.vault {feet=over;return .over}
        }
        return nil
    }
}

/// Exact query ordering and thresholds of the bounded archived ledge finder.
/// The adapter must apply group0xffff0087 and ignore PED colliders before
/// choosing a nearest ray hit. Slow/fixed checks then occur here, after hit.
struct NativeClimbProbe {
    typealias V=SIMD3<Double>
    struct Collider {var fixed:Bool;var speed:Double;var material:Int;var known:Bool=true}
    struct Hit {var distance:Double;var normal:V;var collider:Collider}
    var ray:(V,V,Double,UInt32)->Hit?
    var overlaps:(V,Double,UInt32)->[Collider]
    static let groups:UInt32=0xffff0087
    private func stable(_ body:Collider)->Bool {body.known && (body.fixed || body.speed<0.5)}
    private func trace(_ origin:V,_ direction:V,_ distance:Double)->Hit? {
        guard let hit=ray(origin,direction,distance,Self.groups),stable(hit.collider) else{return nil}
        return hit
    }
    private func free(_ samples:[SIMD2<Double>],_ radius:Double,_ origin:V,_ direction:V)->Bool {
        for sample in samples {
            var p=origin+direction*sample.x;p.y=origin.y+sample.y
            if overlaps(p,radius,Self.groups).contains(where:{!$0.known || stable($0)}) {return false}
        }
        return true
    }
    func find(feet:V,heading:Double,extended:Bool=true)->NativeClimbController.Ledge? {
        let direction=V(-sin(heading),0,-cos(heading)),maximum=extended ? 3.4:2.9
        func at(_ height:Double)->V {V(feet.x,feet.y+height,feet.z)}
        if trace(at(1.8),V(0,1,0),3.9-1.8) != nil || trace(at(3.9),direction,1.4) != nil {return nil}
        var previous:Hit?,selected:Hit?,height=0.0,level=maximum+0.1
        while level>=1-0.000001 {
            let hit=trace(at(level),direction,1.8)
            if let hit,level<=maximum,(previous==nil || previous!.distance>hit.distance+0.3) {selected=hit;height=level;break}
            previous=hit;level -= 0.1
        }
        guard var hit=selected,hit.collider.material != 17,hit.collider.material != 18 else{return nil}
        var lower=height,upper=height+0.1
        for _ in 0..<4 {
            let midpoint=(lower+upper)/2
            if let next=trace(at(midpoint),direction,1.8),next.distance<hit.distance+0.3 {lower=midpoint;hit=next}
            else {upper=midpoint}
        }
        var inward=V(-hit.normal.x,0,-hit.normal.z)
        if abs(hit.normal.x)<=0.05 && abs(hit.normal.z)<=0.05 {inward=direction}
        else {
            inward /= simd_length(inward)
            if simd_dot(inward,direction)<0 {inward = -inward}
            if simd_dot(inward,direction)<0.3 {return nil}
        }
        let top=(lower+upper)/2
        var distance=hit.distance
        if !hit.collider.fixed {
            for depth in [0.15,0.3,0.45] {
                distance=min(distance,trace(at(top-depth),direction,1.8)?.distance ?? distance)
            }
        }
        var hold=feet+direction*distance;hold.y=feet.y+top
        let behind=hold+inward*(-0.4)
        let bodySamples:[SIMD2<Double>]=[SIMD2(0.6,1.75),SIMD2(0.6,1.3),SIMD2(0.6,0.85),SIMD2(0.3,0.65),SIMD2(0,0.5),SIMD2(0,0.1),SIMD2(0,-0.3)]
        guard free(bodySamples,0.3,behind,inward) else{return nil}
        let vaultSamples:[SIMD2<Double>]=[SIMD2(1.1,-0.2),SIMD2(1.1,0.2),SIMD2(1.1,0.6),SIMD2(0.7,0.6),SIMD2(0.35,0.6),SIMD2(0,0.6)]
        return .init(hold:hold,into:inward,heading:atan2(-inward.x,-inward.z),high:hold.y-(feet.y+1)>=1.4,
                     vault:hit.collider.fixed && free(vaultSamples,0.26,behind,inward),fixed:hit.collider.fixed)
    }
}
