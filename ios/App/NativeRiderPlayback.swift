import Foundation
import simd

/// Successful pose draws own these intervals; this is not the gameplay clock.
/// Rejection remains distinct from valid zero (which may consume empty phases).
struct NativeRiderPoseClock {
    enum Admission {case elapsed(Double),rejected(Double)}
    struct Interval {
        let start:Double,end:Double,rejection:Double?
        var canPrime:Bool{rejection == nil && start.isFinite && end.isFinite && end>=start && end-start<=0.5}
        /// Presentation consumers without a timed command share the same
        /// active/suspension boundary as boarding, without dropping slow frames.
        var presentationDelta:Double {
            switch admission(commandAt:start) {
            case .elapsed(let delta):return delta
            case .rejected:return 0
            }
        }
        func admission(commandAt:Double)->Admission {
            if let rejection{return .rejected(rejection)}
            guard canPrime,commandAt.isFinite else{return .rejected(.nan)}
            let delta=end-max(start,commandAt)
            guard delta>=0,delta<=0.5 else{return .rejected(delta)}
            return .elapsed(delta)
        }
    }
    private var previous:Double?
    private var wasActive=false
    mutating func reset(at time:Double?=nil){
        if let time,time.isFinite{previous=time;wasActive=true}
        else{previous=nil;wasActive=false}
    }
    mutating func interval(at time:Double,active:Bool)->Interval {
        guard time.isFinite else{reset();return .init(start:0,end:0,rejection:.nan)}
        let before=previous;previous=time
        guard active else{wasActive=false;return .init(start:time,end:time,rejection:.nan)}
        let start=wasActive ? before ?? time:time;wasActive=true
        guard time>=start else{return .init(start:start,end:time,rejection:time-start)}
        guard time-start<=0.5 else{return .init(start:start,end:time,rejection:time-start)}
        return .init(start:start,end:time,rejection:nil)
    }
}

extension NativeRiderAnimation {
    /// Keep the existing per-step response and direct-delta reference API.
    /// Ordinary slow displays carry time in bounded slices; suspension holds.
    func update(interval:NativeRiderPoseClock.Interval,configuration:Configuration,input:Input)->Frame {
        update(presentation:(interval.start,interval.end,interval.canPrime),configuration:configuration,input:input)
    }
}

/// Public bA phase plans and 0.25 s pose transitions. Ordinary elapsed time
/// carries across phase boundaries instead of rounding every phase to a frame.
/// A capture names the exact raw phase-end pose, not the preceding display.
final class NativeRiderPlayback {
    enum State:String {case out,entering,inside="in",leaving,stood}
    struct Sample {var pose:NativeRiderAnimation.Frame;var anchor:SIMD3<Double>}
    enum Capture {case sample(Sample),current}
    struct Frame {
        var sample:Sample
        var turn:Double
        var capture:Capture?
        var captureSerial:Int
        var transition:Double
        var transitioning:Bool
        var doorPart:Int?
        var doorOpen:Double
        var releasedDoor:(Int,Double)?
        var state:State
    }
    private let definition:NativeRiderDefinitions.Definition
    private let configuration:NativeBoardingAnimation.Configuration
    private let planner:NativeBoardingAnimation
    private let duration:(String)->Double?
    private var seated:NativeRiderAnimation
    private var queue:[NativeBoardingAnimation.Phase]=[]
    private var phase:NativeBoardingAnimation.Phase?
    private var elapsed:Double=0,transition:Double=1,turn:Double=0
    private var anchor=SIMD3<Double>.zero
    private var part:Int?,opening:Double=0
    private var capture:Capture?
    private var serial=0
    private var timedCommandAt:Double?
    private(set) var state:State = .out
    init?(definition:NativeRiderDefinitions.Definition,seat:Int=0,library:NativeSkeletalAnimationLibrary){
        guard let configuration=Self.configuration(definition,seat:seat) else{return nil}
        self.definition=definition;self.configuration=configuration
        self.duration=library.duration(of:);self.planner=NativeBoardingAnimation(duration:library.duration(of:),root:library.rootPosition(_:at:))
        self.seated=NativeRiderAnimation(duration:library.duration(of:))
    }
    var inside:Bool{state == .inside}
    func beside(side:Int = -1,model:simd_float4x4)->SIMD3<Float>? {
        guard inside,let at=planner.beside(configuration,side:side) else{return nil}
        let point=model*SIMD4(SIMD3<Float>(at),1)
        return SIMD3(point.x,point.y,point.z)
    }
    func sit(){timedCommandAt=nil;queue=[];phase=nil;state = .inside;capture=nil;transition=1;turn=definition.seats[configuration.seat].turn ?? 0}
    func enter(side:Int = -1,jack:Bool=false,doorOpen:Double=0){
        timedCommandAt=nil
        let plan=planner.enter(configuration,side:side,jack:jack,doorOpen:doorOpen)
        anchor=plan.anchor;queue=plan.phases;phase=queue.isEmpty ? nil:queue.removeFirst();elapsed=0
        state=phase==nil ? .inside:.entering;transition=0;serial+=1
        capture = .sample(.init(pose:.init(base:"ped/idle_stance"),anchor:anchor))
        seated=NativeRiderAnimation(duration:duration)
    }
    func leave(side:Int = -1,leaveOpen:Bool=false){
        timedCommandAt=nil
        let plan=planner.leave(configuration,side:side,leaveOpen:leaveOpen)
        anchor=plan.anchor;queue=plan.phases;phase=queue.isEmpty ? nil:queue.removeFirst();elapsed=0
        state=phase==nil ? .stood:.leaving;transition=0;serial+=1;capture = .current
    }
    /// Callers inject one monotonic domain. Commands observed inside a pose
    /// draw use its timestamp; an input command between draws uses its own time.
    func sit(at time:Double){sit();timedCommandAt=time}
    func enter(at time:Double,side:Int = -1,jack:Bool=false,doorOpen:Double=0){
        enter(side:side,jack:jack,doorOpen:doorOpen);timedCommandAt=time
    }
    func leave(at time:Double,side:Int = -1,leaveOpen:Bool=false){
        leave(side:side,leaveOpen:leaveOpen);timedCommandAt=time
    }
    func update(interval:NativeRiderPoseClock.Interval,input:NativeRiderAnimation.Input)->Frame? {
        // An untimed caller switching to this adapter starts here, never at an
        // old global draw. The direct delta API below retains its own contract.
        if timedCommandAt == nil,interval.canPrime{timedCommandAt=interval.end}
        switch interval.admission(commandAt:timedCommandAt ?? .nan) {
        case .rejected:return update(delta:.nan,input:input)
        case .elapsed(let delta):
            if delta<=0.1{return update(delta:delta,input:input)}
            let count=min(5,max(1,Int(ceil(delta/0.1))))
            var final:Frame?,lastCapture:Capture?,released:(Int,Double)?
            for index in 0..<count {
                let step=min(0.1,max(0,delta-Double(index)*0.1))
                if step==0{continue}
                guard let frame=update(delta:step,input:input) else{continue}
                final=frame
                if let capture=frame.capture{lastCapture=capture}
                if let release=frame.releasedDoor{released=release}
            }
            guard var frame=final else{return nil}
            frame.capture=lastCapture;frame.releasedDoor=released
            return frame
        }
    }
    func update(delta dt:Double,input:NativeRiderAnimation.Input)->Frame? {
        guard state != .out else{return nil}
        // Suspension/invalid samples hold the clock; they do not become old
        // boarding input on a later frame. Ordinary low-FPS time is retained.
        let advances=dt.isFinite && dt>=0 && dt<=0.5
        let delta=advances ? dt:0
        var sample:Sample?
        var released:(Int,Double)?
        var transitionDelta=delta
        let hadPhase=phase != nil
        func length(_ phase:NativeBoardingAnimation.Phase)->Double {
            guard let value=duration(phase.clip),value.isFinite,value>=0 else{return 0}
            return value
        }
        func sampled(_ phase:NativeBoardingAnimation.Phase,at time:Double)->Sample {
            let clipLength=length(phase),time=min(clipLength,max(0,time))
            var place=phase.anchor
            if let lower=phase.lower {place.z=lower.x+(lower.y-lower.x)*smooth(time,lower.z,lower.w)}
            if let door=phase.door {
                part=phase.part ?? configuration.seats[configuration.seat].door
                opening=time>=clipLength ? door.y:door.x+(door.y-door.x)*(door.w>door.z ? min(1,max(0,(time-door.z)/(door.w-door.z))):1)
            }
            return Sample(pose:.init(base:phase.clip,time:time),anchor:place)
        }
        if phase != nil {
            if advances {
                elapsed+=delta
                // Every iteration consumes one finite queued phase, including
                // absent/zero-length clips; it cannot spin on a zero duration.
                var remainingPhases=queue.count+1
                while let current=phase,remainingPhases>0 {
                    let duration=length(current)
                    guard elapsed>=duration else{break}
                    let overflow=max(0,elapsed-duration)
                    serial+=1;capture = .sample(sampled(current,at:duration));transition=0
                    elapsed=overflow;transitionDelta=overflow;remainingPhases-=1
                    self.phase=queue.isEmpty ? nil:queue.removeFirst()
                    if self.phase==nil {
                        state=state == .entering ? .inside:.stood
                        if let part{released=(part,opening)}
                        part=nil;elapsed=0
                    }
                }
            }
            if let phase {sample=sampled(phase,at:elapsed)}
        }
        if phase==nil {
            if state == .inside {
                let seat=definition.seats[configuration.seat],at=seat.position.map(SIMD3<Double>.init) ?? configuration.seats[configuration.seat].at
                sample=Sample(pose:seated.update(delta:hadPhase ? transitionDelta:delta,configuration:definition.configuration(seat:configuration.seat),input:input),anchor:at)
            } else {sample=Sample(pose:.init(base:"ped/idle_stance"),anchor:anchor)}
        }
        let transitioning=transition<1
        transition=min(1,transition+transitionDelta/0.25)
        let target=phase==nil && state == .inside ? definition.seats[configuration.seat].turn ?? 0:0
        let turnDelta=hadPhase && phase==nil && state == .inside ? transitionDelta:delta
        turn+=(target-turn)*min(1,turnDelta/0.25*2)
        // Original bA's door getter hides its cached part after a forced sit.
        // Remote action cancellation must release the renderer's door override.
        let holdingDoor=state == .entering || state == .leaving
        let frame=Frame(sample:sample ?? Sample(pose:.init(base:"ped/idle_stance"),anchor:anchor),turn:turn,capture:capture,captureSerial:serial,
            transition:smooth(transition,0,1),transitioning:transitioning,doorPart:holdingDoor ? part:nil,doorOpen:opening,releasedDoor:released,state:state)
        capture=nil
        return frame
    }
    private func smooth(_ value:Double,_ lower:Double,_ upper:Double)->Double {
        if value<=lower{return 0};if value>=upper{return 1}
        let x=(value-lower)/(upper-lower);return x*x*(3-2*x)
    }
    static func configuration(_ definition:NativeRiderDefinitions.Definition,seat:Int)->NativeBoardingAnimation.Configuration? {
        guard definition.seats.indices.contains(seat),let group=definition.group else{return nil}
        let seats=definition.seats.compactMap{seat->NativeBoardingAnimation.Seat? in
            guard seat.at.count==3 else{return nil}
            let at=SIMD3(Double(seat.at[0]),Double(seat.at[1]),Double(seat.at[2])),via=seat.via.flatMap{$0.count==3 ? SIMD3(Double($0[0]),Double($0[1]),Double($0[2])):nil}
            return .init(at:at,side:seat.side,rear:seat.rear,opens:seat.opens,door:seat.door,via:via)
        }
        guard seats.count==definition.seats.count else{return nil}
        let clips=["open":group.open,"openRear":group.openRear,"getIn":group.getIn,"getInRear":group.getInRear,"pullOut":group.pullOut,
            "closeIn":group.closeIn,"closeInRear":group.closeInRear,"getOut":group.getOut,"getOutRear":group.getOutRear,"closeOut":group.closeOut,"closeOutRear":group.closeOutRear].mapValues{$0.map{$0.replacingOccurrences(of:":",with:"/")}}
        return .init(seats:seats,seat:seat,origin:definition.origin,astride:definition.astride,afloat:definition.afloat ?? false,clips:clips,
            shuffle:group.shuffle.isEmpty ? nil:group.shuffle.replacingOccurrences(of:":",with:"/"),getInTime:group.getInTime,getOutTime:group.getOutTime,special:group.special,
            doorOpenOut:group.doorOpenOut,doorCloseIn:group.doorCloseIn,doorOpenIn:group.doorOpenIn,doorCloseOut:group.doorCloseOut)
    }
}
