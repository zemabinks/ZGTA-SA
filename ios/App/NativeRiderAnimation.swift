import Foundation

struct NativeRiderDefinitions: Decodable {
    struct Group:Decodable {
        var open:[String],openRear:[String],getIn:[String],getInRear:[String],pullOut:[String]
        var closeIn:[String],closeInRear:[String],getOut:[String],getOutRear:[String],closeOut:[String],closeOutRear:[String]
        var getInTime:Double,getOutTime:Double
        var doorOpenOut:[Double],doorCloseIn:[Double],doorOpenIn:[Double],doorCloseOut:[Double]
        var special:Int
        var shuffle:String
    }
    struct Seat: Decodable {
        var at: [Float]
        var side: Int
        var rear: Bool
        var opens: Bool
        var door: Int?
        var via: [Float]?
        var shift: [Float]?
        var turn: Double?
        var position: SIMD3<Float>? {
            guard at.count == 3 else { return nil }
            var value = SIMD3(at[0],at[1],at[2])
            if let shift,shift.count == 3 { value += SIMD3(shift[0],shift[1],shift[2]) }
            return value
        }
    }
    struct Definition: Decodable {
        var model: String
        var astride: Bool
        var clips: [String:String]
        var seats: [Seat]
        var origin: Double
        var bike: [String:Double]?
        var afloat:Bool?
        var group:Group?
        func configuration(seat: Int = 0) -> NativeRiderAnimation.Configuration {
            NativeRiderAnimation.Configuration(astride:astride,clips:clips,passenger:seat>0,side:seats.indices.contains(seat) ? seats[seat].side:-1)
        }
    }
    var models: [String:Definition]
}

/// Seated public bA.es/ec clip selection and state; root/figure anchoring is
/// supplied independently by the raw rider poser, never by the foot motor.
final class NativeRiderAnimation {
    struct Configuration { var astride: Bool;var clips: [String:String];var passenger = false;var side: Int = -1 }
    struct Input { var speed: Double = 0;var steer: Double = 0;var lean: Double = 0;var tuck: Double = 0;var pedal: Int?;var crank: Double?;var hop: Double = 0;var dead = false }
    struct Sample { var clip: String;var time: Double;var weight: Double }
    struct Frame { var base: String?;var time: Double = 0;var mixes: [Sample] = [] }
    private let duration:(String)->Double?
    private var presentationPreviousEnd:Double?
    private var still:Double=1,lean:Double=0,tuck:Double=0,steer:Double=0,pedal:Double=0,sprint:Double=0,hop:Double=0,crank:Double=0,hopTime:Double=0
    init(duration:@escaping(String)->Double?){self.duration=duration}
    /// A newly admitted pose owns no earlier display time. Missing draws do
    /// not accumulate debt, and duplicate intervals cannot advance it twice.
    /// The tuple keeps this CPU planner independent of the renderer clock type.
    func update(presentation interval:(start:Double,end:Double,valid:Bool),configuration:Configuration,input:Input)->Frame {
        let previous=presentationPreviousEnd
        presentationPreviousEnd=interval.end.isFinite ? interval.end:nil
        guard interval.valid,interval.start.isFinite,interval.end.isFinite,
              interval.end>=interval.start,interval.end-interval.start<=0.5,
              let previous,interval.end>=previous else {
            return update(delta:0,configuration:configuration,input:input)
        }
        let delta=interval.end-max(interval.start,previous)
        if delta<=0.1{return update(delta:delta,configuration:configuration,input:input)}
        let count=min(5,max(1,Int(ceil(delta/0.1))))
        var final:Frame?
        for index in 0..<count {
            let step=min(0.1,max(0,delta-Double(index)*0.1))
            if step>0{final=update(delta:step,configuration:configuration,input:input)}
        }
        return final ?? update(delta:0,configuration:configuration,input:input)
    }
    func update(delta dt:Double,configuration c:Configuration,input t:Input)->Frame {
        func clip(_ role:String)->String?{guard let name=c.clips[role],let length=duration(name),length>0 else{return nil};return name}
        func clamp(_ value:Double)->Double{min(1,max(-1,value))}
        var result=Frame(base:clip("sit"))
        func mix(_ role:String,_ time:Double?,_ weight:Double){guard weight>0.001,let name=clip(role),let length=duration(name) else{return};result.mixes.append(Sample(clip:name,time:time ?? length,weight:min(1,weight)))}
        let ease=min(1,6*dt),speed=abs(t.speed)
        if c.astride {
            if c.passenger {result.base=clip("passenger") ?? clip("sit");return result}
            let progress=min(1,max(0,(speed-1.2)/(3.5-1.2))),smooth=progress*progress*(3-2*progress)
            still += (1-smooth-still)*ease;lean += (clamp(t.lean/0.6)-lean)*ease;tuck += (clamp(t.tuck)-tuck)*ease
            mix("still",0,still);mix(lean<0 ? "left":"right",nil,abs(lean)*(1-still));mix(tuck>0 ? "forward":"backward",nil,abs(tuck))
            if let pedalling=clip("pedal"),let length=duration(pedalling){
                let mode=t.pedal ?? (speed>3.5 ? 1:0)
                if t.crank == nil && mode != 0 {crank += 1.1*dt}
                let rotation=t.crank ?? crank,phase=rotation-floor(rotation)
                pedal += ((mode==1 ? 1.0:0)-pedal)*ease;sprint += ((mode==2 ? 1.0:0)-sprint)*ease
                mix("pedal",phase*length,pedal)
                if let clip=clip("sprint"),let duration=duration(clip){mix("sprint",phase*duration,sprint)}
                if let clip=clip("bunnyhop"),let length=duration(clip){
                    hopTime=t.hop<0 ? hopTime+1.5*dt:0;hop += ((t.hop != 0 ? 1.0:0)-hop)*min(1,8*dt)
                    mix("bunnyhop",t.hop<0 ? min(length,0.2+hopTime):0.2*t.hop,hop)
                }
            }
            return result
        }
        if t.dead,let name=clip((c.side == 0 ? -1:c.side)<0 ? "deadLeft":"deadRight") {result.base=name;result.time=duration(name) ?? 0;return result}
        if c.passenger {result.base=clip("passenger") ?? clip("sit");return result}
        steer += (clamp(t.steer/0.61)-steer)*min(1,10*dt)
        let normal=steer<0 ? "left":"right",slow=steer<0 ? "slowLeft":"slowRight"
        mix(speed<=20 && clip(slow) != nil ? slow:normal,nil,abs(steer))
        return result
    }
}
