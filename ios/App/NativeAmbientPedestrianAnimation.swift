// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

/// NPC pose ownership around the existing common original-animation controller.
/// Flags and hit counters are authoritative observations, not human health or
/// timed knockdown requests. Social activities/events remain a separate layer.
final class NativeAmbientPedestrianAnimation {
    struct Snapshot {
        var position = SIMD3<Double>.zero
        var heading:Double = 0
        var speed:Double = 0
        var flags:UInt8 = 0
        var state:NativeAmbientPedestrianProtocol.State?
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

    init(library:NativeSkeletalAnimationLibrary,style:NativeFootAnimationStyle,
         weapons:[Int:NativeFootWeaponAnimation],random:()->Double = {Double.random(in:0..<1)}) {
        animator=NativeFootAnimation(library:library,style:style,random:random)
        self.weapons=weapons
    }
    func resetDisplayClock(){displayTime=nil;displayRemainder=0}

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
            animator.die(kind)
        }else if !down && wasDown {
            animator.revive()
            _=animator.act(faceDown ? "ped/getup_front":"ped/getup",cut:true,once:true)
        }
        wasDown=down
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
