import Foundation
import simd

/// Public bA boarding queue and 0.25 s pose transitions. A capture event names
/// the exact raw phase-end pose, rather than the preceding displayed frame.
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
    private(set) var state:State = .out
    init?(definition:NativeRiderDefinitions.Definition,seat:Int=0,library:NativeSkeletalAnimationLibrary){
        guard let configuration=Self.configuration(definition,seat:seat) else{return nil}
        self.definition=definition;self.configuration=configuration
        self.duration=library.duration(of:);self.planner=NativeBoardingAnimation(duration:library.duration(of:),root:library.rootPosition(_:at:))
        self.seated=NativeRiderAnimation(duration:library.duration(of:))
    }
    var inside:Bool{state == .inside}
    func sit(){queue=[];phase=nil;state = .inside;capture=nil;transition=1;turn=definition.seats[configuration.seat].turn ?? 0}
    func enter(side:Int = -1,jack:Bool=false,doorOpen:Double=0){
        let plan=planner.enter(configuration,side:side,jack:jack,doorOpen:doorOpen)
        anchor=plan.anchor;queue=plan.phases;phase=queue.isEmpty ? nil:queue.removeFirst();elapsed=0
        state=phase==nil ? .inside:.entering;transition=0;serial+=1
        capture = .sample(.init(pose:.init(base:"ped/idle_stance"),anchor:anchor))
        seated=NativeRiderAnimation(duration:duration)
    }
    func leave(side:Int = -1,leaveOpen:Bool=false){
        let plan=planner.leave(configuration,side:side,leaveOpen:leaveOpen)
        anchor=plan.anchor;queue=plan.phases;phase=queue.isEmpty ? nil:queue.removeFirst();elapsed=0
        state=phase==nil ? .stood:.leaving;transition=0;serial+=1;capture = .current
    }
    func update(delta dt:Double,input:NativeRiderAnimation.Input)->Frame? {
        guard state != .out else{return nil}
        var sample:Sample?
        var released:(Int,Double)?
        if let phase {
            elapsed+=dt;let length=duration(phase.clip) ?? 0
            var place=phase.anchor
            if let lower=phase.lower {place.z=lower.x+(lower.y-lower.x)*smooth(elapsed,lower.z,lower.w)}
            sample=Sample(pose:.init(base:phase.clip,time:min(elapsed,length)),anchor:place)
            if let door=phase.door {
                part=phase.part ?? configuration.seats[configuration.seat].door
                opening=elapsed>=length ? door.y:door.x+(door.y-door.x)*(door.w>door.z ? min(1,max(0,(elapsed-door.z)/(door.w-door.z))):1)
            }
            if elapsed>=length {
                serial+=1;capture = .sample(sample!);transition=0;elapsed=0
                self.phase=queue.isEmpty ? nil:queue.removeFirst()
                if self.phase==nil {
                    state=state == .entering ? .inside:.stood
                    if let part{released=(part,opening)}
                    part=nil
                }
            }
        }
        if phase==nil {
            if state == .inside {
                let seat=definition.seats[configuration.seat],at=seat.position.map(SIMD3<Double>.init) ?? configuration.seats[configuration.seat].at
                sample=Sample(pose:seated.update(delta:dt,configuration:definition.configuration(seat:configuration.seat),input:input),anchor:at)
            } else {sample=Sample(pose:.init(base:"ped/idle_stance"),anchor:anchor)}
        }
        let transitioning=transition<1
        transition=min(1,transition+dt/0.25)
        let target=phase==nil && state == .inside ? definition.seats[configuration.seat].turn ?? 0:0
        turn+=(target-turn)*min(1,dt/0.25*2)
        let frame=Frame(sample:sample ?? Sample(pose:.init(base:"ped/idle_stance"),anchor:anchor),turn:turn,capture:capture,captureSerial:serial,
            transition:smooth(transition,0,1),transitioning:transitioning,doorPart:part,doorOpen:opening,releasedDoor:released,state:state)
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
