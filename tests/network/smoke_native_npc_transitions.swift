// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main enum NPCTransitionTests {
    static var checks=0
    static func check(_ value:Bool,_ message:String){
        checks+=1
        if !value{FileHandle.standardError.write(Data(("FAIL: "+message+"\n").utf8));exit(1)}
    }
    static let deaths:Set<String>=["ped/ko_shot_front","ped/ko_skid_front","ped/ko_skid_back","ped/ko_spin_l","ped/ko_spin_r","ped/floor_hit"]
    static func death(_ frame:NativeFootAnimation.Frame)->NativeSkeletalBlend {
        guard let value=frame.blends.first(where:{deaths.contains($0.clip)&&$0.weight>0})else{fatalError("No visible authored death pose")}
        return value
    }
    static func owner()->NativeAmbientPedestrianAnimation {
        .init(library:NPCAnimationCandidateTests.fixture(),style:.init(),weapons:[:],random:{0.25})
    }
    struct Replay {
        let npc:NativeAmbientPedestrianAnimation,frame:NativeFootAnimation.Frame
        let snapshot:NativeAmbientPedestrianAnimation.Snapshot,time:Double
    }
    static func replay(_ document:[String:Any],schedule:[Double],split:Bool,missingCause:Bool=false)throws->Replay {
        let baseline=document["baseline"]as! [String:Any],rows=document["evidence"]as! [[String:Any]]
        let epoch=(baseline["time"]as! NSNumber).doubleValue,npc=owner()
        var current=try PopulationHitPieceTests.snapshot(baseline),time=10.0,index=0
        var frame=npc.update(at:time,active:true,snapshot:current)!
        func before(_ target:Double){
            while time+schedule[index%schedule.count]<target-1e-9 {
                time+=schedule[index%schedule.count];index+=1
                frame=npc.update(at:time,active:true,snapshot:current)!
            }
        }
        for row in rows {
            let target=10+((row["time"]as! NSNumber).doubleValue-epoch)/1000
            before(target)
            let next=try PopulationHitPieceTests.snapshot(row)
            if split && row["label"]as! String=="terminal-head" {
                var status=next;status.state=missingCause ? nil:current.state;current=status
                time=target;frame=npc.update(at:time,active:true,snapshot:current)!
                check(npc.animator.dead,"Status receipt delayed the authoritative down state")
                let late=target+schedule[0];before(late);current=next;time=late
                frame=npc.update(at:time,active:true,snapshot:current)!
            }else{current=next;time=target;frame=npc.update(at:time,active:true,snapshot:current)!}
        }
        let target=10+((rows.last!["time"]as! NSNumber).doubleValue-epoch)/1000+0.3
        before(target);time=target;frame=npc.update(at:time,active:true,snapshot:current)!
        return .init(npc:npc,frame:frame,snapshot:current,time:time)
    }
    static func replacing(_ state:NativeAmbientPedestrianProtocol.State,hits:UInt8?=nil,from:Double?=nil,weapon:UInt8?=nil)->NativeAmbientPedestrianProtocol.State {
        .init(id:state.id,mood:state.mood,burning:state.burning,phone:state.phone,crouching:state.crouching,cpr:state.cpr,
              weapon:state.weapon,hitWeapon:weapon ?? state.hitWeapon,hitCounter:hits ?? state.hitCounter,hitPiece:state.hitPiece,
              hitFromWire:from ?? state.hitFromWire,faceWire:state.faceWire,foe:state.foe,thrown:state.thrown)
    }
    static func main()throws {
        let document=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))as! [String:Any]
        let schedules=[[1.0/20],[1.0/30],[1.0/60],[1.0/120],[0.011,0.039,0.2,0.04,0.31,0.1]]
        for schedule in schedules {
            let atomic=try replay(document,schedule:schedule,split:false),expected=death(atomic.frame)
            check(abs(expected.time-0.3)<1e-8,"Native death phase advances before the observed event")
            for missing in [false,true] {
                let split=try replay(document,schedule:schedule,split:true,missingCause:missing),actual=death(split.frame)
                check(actual.clip==expected.clip,"Packet arrival order changes the native death cause")
                check(abs(actual.time-expected.time)<1e-8,"Late cause restarts or backdates the death phase")
                check(split.npc.animator.dead && split.npc.animator.lostHead && split.frame.hiddenBones.contains(5),"Split cause lost persistent task/head state")
                let held=split.npc.update(at:split.time+0.1,active:true,snapshot:split.snapshot)!
                check(abs(death(held).time-0.4)<1e-8,"Unchanged metadata restarted the death clock")
            }
        }
        let terminal=(document["evidence"]as! [[String:Any]]).last!
        let dead=try PopulationHitPieceTests.snapshot(terminal)
        for counter in [dead.state!.hitCounter,UInt8(0)] {
            let npc=owner();var snapshot=dead;snapshot.state=replacing(dead.state!,hits:counter)
            let first=npc.update(at:10,active:true,snapshot:snapshot)!
            check(npc.animator.dead && npc.animator.lostHead && first.hiddenBones.contains(5),"Late observer lost the established head visibility state")
            check(!npc.animator.stunned,"Baseline metadata acquired human input stun")
            snapshot.flags=0
            let recovered=npc.update(at:10.2,active:true,snapshot:snapshot)!
            check(!npc.animator.dead && !npc.animator.lostHead && !recovered.hiddenBones.contains(5),"Down clear failed to restore the new life")
        }
        // A newly streamed status can precede the first supplemental record.
        do {
            let npc=owner();var unknown=dead;unknown.state=nil
            _=npc.update(at:10,active:true,snapshot:unknown)
            _=npc.update(at:10.04,active:true,snapshot:dead)
            let frame=npc.update(at:10.3,active:true,snapshot:dead)!
            let reference=try replay(document,schedule:[1.0/60],split:false)
            check(death(frame).clip==death(reference.frame).clip && abs(death(frame).time-0.3)<1e-8,"First cause failed to replace an unknown streamed fallback")
        }
        // The corrected cause also owns subsequent get-up orientation.
        do {
            let npc=owner();var alive=dead;alive.flags=0
            alive.state=replacing(dead.state!,hits:1,from:.pi/2,weapon:22)
            _=npc.update(at:10,active:true,snapshot:alive)
            var status=alive;status.flags=9;_=npc.update(at:10.1,active:true,snapshot:status)
            status.state=replacing(alive.state!,hits:2,weapon:24);_=npc.update(at:10.14,active:true,snapshot:status)
            var up=status;up.flags=0
            let frame=npc.update(at:10.4,active:true,snapshot:up)!
            check(frame.blends.contains{$0.clip=="ped/getup_front"&&$0.weight>0},"Late cause did not correct get-up orientation")
        }
        // Pause/invalid clocks preserve a held pose without catch-up or events.
        do {
            let value=try replay(document,schedule:[1.0/60],split:false),before=death(value.frame).time
            let held=value.npc.update(at:100,active:false,snapshot:value.snapshot)!
            check(held.travel == .zero && held.steps.isEmpty && held.shots.isEmpty,"Held pose replayed movement/events")
            let resumed=value.npc.update(at:100,active:true,snapshot:value.snapshot)!
            check(abs(death(resumed).time-before)<1e-8,"Resume consumed paused wall time")
            _=value.npc.update(at:.nan,active:true,snapshot:value.snapshot)
            let restored=value.npc.update(at:101,active:true,snapshot:value.snapshot)!
            check(abs(death(restored).time-before)<1e-8,"Invalid clock resumed with animation catch-up")
        }
        // A lying rider handoff holds its landed pose rather than replaying an
        // upright death when delayed metadata appears. It starts a new clock.
        do {
            let npc=owner();var snapshot=dead;snapshot.state=nil
            _=npc.update(at:10,active:true,snapshot:snapshot)
            npc.acceptRider(lying:true)
            let arrival=npc.update(at:10.5,active:true,snapshot:snapshot)!
            check(death(arrival).clip=="ped/floor_hit" && death(arrival).time>=1,"Lying handoff replayed upright motion")
            let late=npc.update(at:10.6,active:true,snapshot:dead)!
            check(death(late).clip=="ped/floor_hit" && death(late).time>=1,"Delayed cause replaced the retained lying pose")
        }
        print("PASS native NPC transition clocks: \(checks) checks, actual backend bytes/decoder/common pose owner; authored tracks, not rendered or retail verification")
    }
}
