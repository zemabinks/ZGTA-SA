// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// NPC pose ownership around the existing common original-animation controller.
/// Flags, task moods and hit counters are authoritative observations, not
/// human health or timed knockdown requests. Motion remains separately owned.
final class NativeAmbientPedestrianAnimation {
    struct Snapshot {
        var position = SIMD3<Double>.zero
        var heading:Double = 0
        var speed:Double = 0
        var flags:UInt8 = 0
        var state:NativeAmbientPedestrianProtocol.State?
        var id:UInt16 = 0
        var seed:UInt8 = 0
        var femaleActivity = false
        var waitingLinkKind:UInt8?=nil
        var down:Bool {flags&1 != 0}
    }
    let animator:NativeFootAnimation
    private let weapons:[Int:NativeFootWeaponAnimation]
    private var displayTime:Double?
    private var displayRemainder:Double = 0
    private var displayFrame:NativeFootAnimation.Frame?
    private var ratio:Double = 0
    private var hits:UInt8?
    private var hitUntil = -Double.infinity
    private var wasDown = false
    private var faceDown = false
    private var arrivalLying = false
    private var activity=NativeAmbientPedestrianActivity()
    private var waiting=NativeAmbientPedestrianWaiting()
    private let walkStyle:String
    private let duration:(String)->Double?

    init(library:NativeSkeletalAnimationLibrary,style:NativeFootAnimationStyle,
         weapons:[Int:NativeFootWeaponAnimation],random:()->Double = {Double.random(in:0..<1)}) {
        animator=NativeFootAnimation(library:library,style:style,random:random)
        self.weapons=weapons;walkStyle=style.walk
        duration={library.duration(of:$0)}
    }
    func resetDisplayClock(){displayTime=nil;displayRemainder=0}
    /// Existing server flags still choose down/recovery. A lying arrival skips
    /// replaying the fall from upright after its vehicle animation completed.
    func acceptRider(lying:Bool) {
        arrivalLying=lying
        if lying{wasDown=false;animator.revive()}
    }

    func update(at time:Double,active:Bool,snapshot:Snapshot)->NativeFootAnimation.Frame? {
        guard active,time.isFinite,(time*1000).isFinite else {
            resetDisplayClock();return heldFrame()
        }
        let elapsed=displayTime.map{time-$0} ?? 0
        displayTime=time
        let accepted=elapsed.isFinite && elapsed>=0 && elapsed<=0.5
        if !accepted{displayRemainder=0}
        let interval=accepted ? elapsed:0,step=1.0/120,total=interval+displayRemainder
        let count=max(0,min(60,Int(floor(total/step+1e-9))))
        displayRemainder=max(0,total-Double(count)*step)
        // Observe authoritative task edges immediately, then advance pose on
        // one fixed clock. Fractional display time is retained rather than
        // changing blend integration with the rendering rate.
        var final=advance(delta:0,now:time*1000,snapshot:snapshot)
        var travel=SIMD2<Double>.zero,steps:[String]=[]
        if count>0 {
            for index in 1...count {
                let frame=advance(delta:step,now:(time-total+Double(index)*step)*1000,snapshot:snapshot)
                travel+=frame.travel;steps+=frame.steps;final=frame
            }
        }
        final.travel=travel;final.steps=steps;displayFrame=final;return final
    }
    private func heldFrame()->NativeFootAnimation.Frame? {
        guard var frame=displayFrame else{return nil}
        frame.travel = .zero;frame.steps=[];frame.shots=[];frame.shot=false;frame.canopySamples=[]
        return frame
    }
    private func advance(delta:Double,now:Double,snapshot:Snapshot)->NativeFootAnimation.Frame {
        let down=snapshot.down
        let state=snapshot.state
        // A first observation establishes a baseline. Counter zero denotes no
        // new reaction, including the31->0 wrap. NPC responses deliberately do
        // not forward the reaction helper's human input-stun result.
        if let state {
            if let previous=hits,previous != state.hitCounter,state.hitCounter != 0 {
                if snapshot.flags&8 != 0,state.hitPiece==9,
                   [UInt8(24),25,26,27,30,31,33,34,38].contains(state.hitWeapon){animator.loseHead()}
                if !down,state.hitWeapon != 49,state.hitWeapon != 51 {
                    let reaction=NativePedestrianReaction.reaction(.init(weapon:Int(state.hitWeapon),
                        side:Self.incomingSide(wireFrom:state.hitFromWire,nativeHeading:snapshot.heading),
                        piece:state.hitPiece==0 ? 3:Int(state.hitPiece),still:snapshot.speed<0.2,
                        damage:25,now:now,until:hitUntil))
                    hitUntil=reaction.until
                    if let kind=reaction.kind{animator.flinch(kind)}
                }
            }
            hits=state.hitCounter
        }
        if down && !wasDown {
            animator.rest(cut:true)
            let kind:String
            if let state,state.hitCounter != 0 {
                kind=Self.deathKind(weapon:state.hitWeapon==51 ? 16:Int(state.hitWeapon),
                    side:Self.incomingSide(wireFrom:state.hitFromWire,nativeHeading:snapshot.heading))
            }else{kind="floorHit"}
            faceDown=kind=="koSkidFront" || kind=="floorHitF"
            animator.die(kind,fallen:arrivalLying)
            arrivalLying=false
        }else if !down && wasDown {
            animator.revive()
            _=animator.act(faceDown ? "ped/getup_front":"ped/getup",cut:true,once:true)
        }
        wasDown=down
        if let state {
            let input=NativeAmbientPedestrianActivity.Input(id:snapshot.id,seed:snapshot.seed,
                mood:state.mood,down:down,female:snapshot.femaleActivity,foe:state.foe != 0,cpr:state.cpr)
            for command in activity.update(now:now,input:input,duration:duration) {
                switch command {
                case .rest:animator.rest()
                case .play(let clip,let loop,let rooted,let once):
                    _=animator.act(clip,loop:loop,rooted:rooted,once:once)
                }
            }
        }
        let waitingInput=NativeAmbientPedestrianWaiting.Input(id:snapshot.id,seed:snapshot.seed,
            mood:state?.mood ?? 0,flags:snapshot.flags,linkKind:snapshot.waitingLinkKind,
            style:NativeAmbientPedestrianWaiting.style(walk:walkStyle,female:snapshot.femaleActivity))
        for command in waiting.update(now:now,input:waitingInput) {
            switch command {
            case .rest:animator.rest()
            case .play(let clip,let loop,let rooted,let once):
                _=animator.act(clip,loop:loop,rooted:rooted,once:once)
            }
        }
        let weapon=Int(state?.weapon ?? 0),mood=state?.mood ?? 0
        // An unarmed calm civilian has no fighting kit. NPC stance belongs
        // to its announced task, rather than human crouch/aim action bits.
        animator.arm(!down && (weapon>0 || mood==4) ? weapons[weapon]:nil)
        let speed=max(0,snapshot.speed)
        let moving = !down && speed>0.15,taskStance=mood != 0 && mood != 7 && !down
        let running=moving && speed>2.5 && (taskStance || snapshot.flags&4 != 0)
        ratio+=((running ? 2:moving ? 1:0)-ratio)*min(1,8*delta)
        let walk=animator.walkSpeed>0.3 ? animator.walkSpeed:1.4
        let run=animator.runSpeed>1 ? animator.runSpeed:4.2
        let pace=running ? min(1.6,max(0.7,speed/run)):moving ? min(2.2,max(0.6,speed/walk)):1
        var input=NativeFootAnimation.Input()
        input.position=snapshot.position;input.heading=snapshot.heading
        input.ratio=ratio
        let stationary = !moving
        input.crouch=taskStance && stationary && (state?.crouching ?? false)
        input.gun=taskStance && mood==6 && weapon>0 && stationary ? .init(pitch:0):nil
        input.guarding=taskStance && mood==4 && weapon==0 && stationary
        return animator.update(delta:delta*pace,input:input)
    }
    /// Input directions use GTA Z-up, clockwise native heading from+Y and
    /// counterclockwise wire angle from+X. Exact45/135degree boundaries are
    /// lateral, matching the directional selector rather than rounded bins.
    static func incomingSide(wireFrom:Double,nativeHeading:Double)->Int {
        let relative=nativeHeading-(Double.pi/2-wireFrom)
        // Match the reference's Euclidean wrap before strict sector tests.
        // A sin/cos/atan2 round trip can move an exact45degree tie inward.
        let period=2*Double.pi,shifted=relative+Double.pi
        let angle=(shifted.truncatingRemainder(dividingBy:period)+period).truncatingRemainder(dividingBy:period)-Double.pi
        if abs(angle)<Double.pi/4{return 0}
        if abs(angle)>3*Double.pi/4{return 2}
        return angle>0 ? 1:3
    }
    static func deathKind(weapon:Int,side:Int)->String {
        let side=max(0,min(3,side))
        if weapon==49 || weapon==50{return["koSkidBack","koSpinR","koSkidFront","koSpinL"][side]}
        if [24,25,26,27,30,31,38,16,35,36,39].contains(weapon){return["koSkidFront","koSpinR","koSkidBack","koSpinL"][side]}
        return "koFront"
    }
}

/// Server task -> existing original-clip script transitions. The complete
/// native library is already admitted before this owner is created, so there
/// is no speculative block download or delayed callback publishing a script.
/// Actor/source replacement retires this value with its animation owner.
struct NativeAmbientPedestrianActivity {
    struct Input {
        var id:UInt16 = 0
        var seed:UInt8 = 0
        var mood:UInt8 = 0
        var down=false,female=false,foe=false,cpr=false
        // Explicit event owners may supply these later. No proximity or
        // speech event is inferred from a roster or an untrusted string.
        var waving=false,talking=false
        var chat:String?
    }
    enum Command:Equatable {
        case rest
        case play(String,loop:Bool,rooted:Bool,once:Bool)
    }
    struct Activity:Equatable {let enter:String,loop:String?,exit:String?}
    struct Pending:Equatable {let clip:String;let at:Double;let rooted:Bool}
    private(set) var firstMood:UInt8?
    private(set) var selected:String?
    private(set) var seated:Activity?
    private(set) var pending:Pending?
    private var clock = -Double.infinity

    mutating func update(now:Double,input:Input,duration:(String)->Double?)->[Command] {
        guard now.isFinite else{return []}
        clock=max(clock,now)
        if firstMood==nil{firstMood=input.mood}
        let definition=Self.definition(mood:input.mood,female:input.female)
        let choice=Self.selection(input,activity:definition)
        var result:[Command]=[]
        func valid(_ clip:String)->Bool {
            guard let seconds=duration(clip)else{return false}
            return seconds.isFinite && seconds>0
        }
        if selected != choice {
            let previous=selected,previousActivity=seated
            selected=choice;seated=definition;pending=nil
            if previous != nil{result.append(.rest)}
            if choice != nil,let definition {
                let rooted=definition.loop != nil
                if firstMood==input.mood,let loop=definition.loop {
                    if valid(loop){result.append(.play(loop,loop:true,rooted:rooted,once:false))}
                }else if valid(definition.enter) {
                    result.append(.play(definition.enter,loop:false,rooted:rooted,once:false))
                    if let loop=definition.loop,valid(loop),let seconds=duration(definition.enter) {
                        pending=Pending(clip:loop,at:clock+1000*max(0,seconds-0.15),rooted:rooted)
                    }
                }
            }else if let choice {
                let held=choice=="ped/handsup" || choice=="ped/arrestgun" || choice=="ped/roadcross" || Self.endChat.contains(choice)
                if valid(choice){result.append(.play(choice,loop:!held,rooted:false,once:false))}
            }else if !input.down,let exit=previousActivity?.exit,valid(exit) {
                result.append(.play(exit,loop:false,rooted:true,once:true))
            }
        }
        if let next=pending,clock>=next.at {
            pending=nil
            if valid(next.clip){result.append(.play(next.clip,loop:true,rooted:next.rooted,once:false))}
        }
        return result
    }
    static func definition(mood:UInt8,female:Bool)->Activity? {
        switch mood {
        case 9:return .init(enter:"ped/seat_down",loop:"ped/seat_idle",exit:"ped/seat_up")
        case 10:return .init(enter:"attractors/stepsit_in",loop:"attractors/stepsit_loop",exit:"attractors/stepsit_out")
        case 11:
            let variant=female ? "w":"m"
            return .init(enter:"sunbathe/parksit_\(variant)_in",loop:"beach/parksit_\(variant)_loop",exit:"sunbathe/parksit_\(variant)_out")
        case 14:return .init(enter:"gangs/dealer_deal",loop:nil,exit:nil)
        case 15:return .init(enter:"gangs/drugs_buy",loop:nil,exit:nil)
        default:return nil
        }
    }
    private static let talkClips=["gangs/prtial_gngtlka","gangs/prtial_gngtlkb","gangs/prtial_gngtlke","gangs/prtial_gngtlkf","gangs/prtial_gngtlkh"]
    private static let standClips=["gangs/prtial_gngtlka","gangs/prtial_gngtlkb","gangs/smkcig_prtl","gangs/prtial_gngtlke","ped/idle_chat","gangs/prtial_gngtlkf","gangs/leanidle","gangs/prtial_gngtlkh","gangs/drnkbr_prtl"]
    private static let endChat:Set<String>=["ped/endchat_01","ped/endchat_02","ped/endchat_03"]
    private static func selection(_ value:Input,activity:Activity?)->String? {
        guard !value.down else{return nil}
        let variant=Int(value.id)+Int(value.seed)
        switch value.mood {
        case 1:return "ped/cower"
        case 2:return "ped/handsup"
        case 3:return value.foe ? talkClips[variant%talkClips.count]:"ped/roadcross"
        case 5:
            if value.waving{return "on_lookers/wave_loop"}
            return value.talking ? talkClips[variant%talkClips.count]:standClips[variant%standClips.count]
        case 8:return "ped/arrestgun"
        default:
            if value.cpr{return "medic/cpr"}
            if let activity{return activity.enter}
            if value.mood==13,let chat=value.chat,chat=="ped/idle_chat" || endChat.contains(chat){return chat}
            return nil
        }
    }
}

/// Waiting pose policy for an authoritative route. This owner does not decide
/// when a pedestrian should stop, cross, or resume; it presents flag2 only.
struct NativeAmbientPedestrianWaiting {
    struct Input {
        var id:UInt16=0
        var seed:UInt8=0,mood:UInt8=0,flags:UInt8=0
        var linkKind:UInt8?
        var style=""
    }
    typealias Command=NativeAmbientPedestrianActivity.Command
    private(set) var waited=false,idled=false
    private(set) var waitedFrom:Double?
    private var clock = -Double.infinity
    static func style(walk:String,female:Bool)->String {
        if walk.contains("old"){return "old"}
        if walk.contains("fat"){return "fat"}
        if walk.contains("gang"){return "gang"}
        if ["woman","wom","sexy","pro"].contains(where:walk.contains) || female{return "woman"}
        return ""
    }
    mutating func update(now:Double,input:Input)->[Command] {
        guard now.isFinite else{return []}
        clock=max(clock,now)
        let down=input.flags&1 != 0
        // Other task owners handle the frame without changing this timer.
        guard down || input.mood==0 || input.mood==7 else{return []}
        let enabled=input.flags&2 != 0 && !down
        let delayed=input.linkKind.map{$0&3 != 1} ?? false
        var result:[Command]=[]
        func play(_ clip:String)->Command{.play("ped/"+clip,loop:false,rooted:false,once:true)}
        if enabled && !waited {
            waitedFrom=clock;idled=false
            if !delayed {
                let clip:[String:String] = ["woman":"roadcross_female","old":"roadcross_old","gang":"roadcross_gang"]
                result.append(play(clip[input.style] ?? "roadcross"))
            }
        }
        if enabled && delayed && !idled,let start=waitedFrom,clock-start>3500 {
            idled=true
            let clips:[String:[String]] = ["woman":["woman_idlestance"],"old":["idlestance_old"],
                "gang":["idle_gang1"],"fat":["idlestance_fat"]]
            let options=clips[input.style] ?? ["idle_hbhb","xpressscratch","idle_tired"]
            result.append(play(options[(Int(input.seed)+Int(input.id))%options.count]))
        }
        if !enabled && waited{result.append(.rest)}
        waited=enabled
        return result
    }
}
