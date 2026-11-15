import Foundation
import simd

/// Public bA.eu/ed phase planner. Anchors and door clocks derive from the
/// original animation root tracks and per-model group, including rear doors,
/// low jump-in entries, shuffles, bikes, boats and special door flags.
final class NativeBoardingAnimation {
    struct Seat {var at:SIMD3<Double>;var side:Int;var rear:Bool;var opens:Bool;var door:Int?;var via:SIMD3<Double>?}
    struct Configuration {
        var seats:[Seat]
        var seat:Int
        var origin:Double
        var astride:Bool
        var afloat:Bool
        var clips:[String:[String]]
        var shuffle:String?
        var getInTime:Double
        var getOutTime:Double
        var special:Int
        var doorOpenOut:[Double]
        var doorCloseIn:[Double]
        var doorOpenIn:[Double]
        var doorCloseOut:[Double]
    }
    struct Phase {
        var clip:String
        var anchor:SIMD3<Double>
        var lower:SIMD4<Double>?
        var door:SIMD4<Double>?
        var part:Int?
        var quits=false
        var closes=false
    }
    struct Plan {var phases:[Phase];var anchor:SIMD3<Double>}
    private let duration:(String)->Double?
    private let root:(String,Double)->SIMD3<Double>
    init(duration:@escaping(String)->Double?,root:@escaping(String,Double)->SIMD3<Double>){self.duration=duration;self.root=root}
    func enter(_ c:Configuration,side:Int = -1,jack:Bool=false,doorOpen:Double=0)->Plan {
        guard c.seats.indices.contains(c.seat) else{return Plan(phases:[],anchor:.zero)}
        let seat=c.seats[c.seat],shuffle=jack ? nil:shuffleSeat(c,side),chosen=shuffle ?? seat,index=shuffle != nil ? 1:sideIndex(seat,side)
        let entry=clip(c,"getIn",index),lift=1-c.origin
        var anchor=(chosen.via ?? chosen.at)
        if let entry{anchor-=root(entry,duration(entry) ?? 0)}
        anchor.z=lift
        guard let entry,!c.afloat else{return Plan(phases:[],anchor:c.afloat ? seat.at:anchor)}
        let end=(chosen.via ?? chosen.at)-root(entry,duration(entry) ?? 0)
        let jump = !seat.rear && (rawClip(c,"getIn",index)?.contains("jumpin") ?? false)
        let door=min(1,max(0,doorOpen)),pull=jack ? clip(c,"pullOut",index):nil
        var phases:[Phase]=[]
        func doorRange(_ from:Double,_ to:Double,_ values:[Double])->SIMD4<Double>{SIMD4(from,to,values.first ?? 0,values.count>1 ? values[1]:0)}
        if let open=clip(c,"open",index),chosen.opens,!jump,c.special&64==0,door<0.95 {
            phases.append(.init(clip:open,anchor:anchor,door:doorRange(door,1,c.doorOpenOut),part:chosen.door,quits:true))
        }
        if let pull {phases.append(.init(clip:pull,anchor:anchor,door:chosen.opens ? SIMD4(1,1,0,0):nil,part:chosen.door,quits:true))}
        phases.append(.init(clip:entry,anchor:anchor,lower:SIMD4(lift,end.z,0,max(0.1,c.getInTime)),door:chosen.opens && !(jump && pull==nil) ? SIMD4(1,1,0,0):nil,part:chosen.door))
        if let close=clip(c,"closeIn",index),chosen.opens,!(jump && pull==nil),c.special&2==0 {
            phases.append(.init(clip:close,anchor:end,door:doorRange(1,0,c.doorCloseIn),part:chosen.door))
        }
        if shuffle != nil,let clip=c.shuffle,duration(clip) != nil {phases.append(.init(clip:clip,anchor:end))}
        return Plan(phases:phases,anchor:anchor)
    }
    /// The original upright door exit path. The separately selected rollover
    /// crawl uses the world bounds and ground query, not this door planner.
    func leave(_ c:Configuration,side:Int = -1,leaveOpen:Bool=false)->Plan {
        guard c.seats.indices.contains(c.seat) else{return Plan(phases:[],anchor:.zero)}
        let seat=c.seats[c.seat],index=sideIndex(seat,side),lift=1-c.origin
        guard let exit=clip(c,"getOut",index),!c.afloat else{return Plan(phases:[],anchor:seat.at)}
        let start=(seat.via ?? seat.at)-root(exit,0),length=duration(exit) ?? 0,lower=min(length,abs(c.getOutTime)>0 ? abs(c.getOutTime):0.5)
        var stood=start;stood.z=lift
        func doorRange(_ from:Double,_ to:Double,_ values:[Double])->SIMD4<Double>{SIMD4(from,to,values.first ?? 0,values.count>1 ? values[1]:0)}
        var phases=[Phase(clip:exit,anchor:start,lower:SIMD4(start.z,lift,length-lower,length),door:seat.opens ? doorRange(0,1,c.doorOpenIn):nil)]
        if let close=clip(c,"closeOut",index),seat.opens,c.special&1==0,!leaveOpen {
            phases.append(.init(clip:close,anchor:stood,door:doorRange(1,0,c.doorCloseOut),closes:true))
        }
        return Plan(phases:phases,anchor:stood)
    }
    private func shuffleSeat(_ c:Configuration,_ side:Int)->Seat? {
        guard side>0,c.shuffle != nil,!c.astride,!c.afloat,c.seat==0,c.seats.indices.contains(0),c.seats[0].side == -1,c.seats.count>1 else{return nil}
        let right=c.seats[1]
        return right.side==1 && !right.rear && right.via==nil && c.clips["getIn"]?.indices.contains(1)==true && !(c.clips["getIn"]?[1].isEmpty ?? true) ? right:nil
    }
    private func sideIndex(_ seat:Seat,_ side:Int)->Int{(seat.side==0 ? (side<0 ? -1:1):seat.side)<0 ? 0:1}
    private func rawClip(_ c:Configuration,_ role:String,_ side:Int)->String? {
        let seat=c.seats[c.seat],key=seat.rear && !c.astride && role != "pullOut" ? role+"Rear":role
        guard let values=c.clips[key] else{return nil}
        // Nullish fallback in the public group loader: an absent clip falls
        // back to the opposite side after loading, including an empty path.
        if values.indices.contains(side),!values[side].isEmpty{return values[side]}
        let other=1-side;return values.indices.contains(other) && !values[other].isEmpty ? values[other]:nil
    }
    private func clip(_ c:Configuration,_ role:String,_ side:Int)->String? {
        guard let name=rawClip(c,role,side),duration(name) != nil else{return nil};return name
    }
}
