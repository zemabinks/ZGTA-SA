// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main enum NPCAnimationCandidateTests {
    static var checks=0
    static func check(_ value:Bool,_ message:String){
        checks+=1
        if !value{FileHandle.standardError.write(Data(("FAIL: "+message+"\n").utf8));exit(1)}
    }
    static func word(_ value:UInt32,_ data:inout Data){var v=value.littleEndian;withUnsafeBytes(of:&v){data.append(contentsOf:$0)}}
    static func number(_ value:Float,_ data:inout Data){word(value.bitPattern,&data)}
    static func text(_ value:String,_ data:inout Data){var n=UInt16(value.utf8.count).littleEndian;withUnsafeBytes(of:&n){data.append(contentsOf:$0)};data.append(contentsOf:value.utf8)}
    static func fixture()->NativeSkeletalAnimationLibrary {
        // Authored single-root CLP tracks exercise the real decoder/controller.
        // They are not original animation assets or a visual timing oracle.
        let names=Set(NativeFootAnimation.actions.values.map { "ped/"+$0 } + ["ped/idle_stance","ped/walk_player","ped/run_player","ped/sprint_civi"]).sorted()
        var data=Data();[UInt32(0x31504c43),UInt32(names.count),0,1].forEach{word($0,&data)}
        for name in names {
            text(name,&data);number(1,&data);word(1,&data);word(0,&data);word(2,&data);word(1,&data)
            let distance:Float=name=="ped/walk_player" ? 1:name=="ped/run_player" ? 3:name=="ped/sprint_civi" ? 4:0
            for time in [Float(0),1]{number(time,&data);[Float(0),0,0,1,0,distance*time,0].forEach{number($0,&data)}}
        }
        guard let library=NativeSkeletalAnimationLibrary(data:data)else{fatalError("Authored CLP reader rejected fixture")}
        return library
    }
    static func state(hits:UInt8=0,weapon:UInt8=0,from:Double = .pi/2,crouched:Bool=false,mood:UInt8=0,held:UInt8=0)->NativeAmbientPedestrianProtocol.State {
        .init(id:1,mood:mood,burning:false,phone:false,crouching:crouched,cpr:false,weapon:held,hitWeapon:weapon,
            hitCounter:hits,hitPiece:3,hitFromWire:from,faceWire:.pi/2,foe:65535,thrown:0)
    }
    static func has(_ frame:NativeFootAnimation.Frame?,_ clip:String)->Bool{frame?.blends.contains{$0.clip==clip && $0.weight>0} ?? false}
    static func main() {
        let library=fixture()
        func owner()->NativeAmbientPedestrianAnimation{.init(library:library,style:.init(),weapons:[:],random:{0.25})}
        for schedule in [[1.0/20],[1.0/30],[1.0/60],[1.0/120],[0.2,0.05],[0.011,0.039,0.2,0.04]] {
            let npc=owner();var snapshot=NativeAmbientPedestrianAnimation.Snapshot(state:state())
            _=npc.update(at:10,active:true,snapshot:snapshot)
            snapshot.flags=1
            var time=10.0,index=0,frame:NativeFootAnimation.Frame?
            while time<15-1e-9 {
                time=min(15,time+schedule[index%schedule.count]);index+=1
                frame=npc.update(at:time,active:true,snapshot:snapshot)
                check(npc.animator.dead,"Server-held down state automatically recovered")
            }
            check(has(frame,"ped/floor_hit"),"Persistent causal floor clip missing")
            check(!has(frame,"ped/getup"),"Get-up started before down flag cleared")
            snapshot.flags=0
            frame=npc.update(at:15.02,active:true,snapshot:snapshot)
            check(!npc.animator.dead && has(frame,"ped/getup"),"Down clear did not explicitly revive/get up")
        }
        do {
            let npc=owner();var snapshot=NativeAmbientPedestrianAnimation.Snapshot(state:state())
            _=npc.update(at:10,active:true,snapshot:snapshot)
            snapshot.state=state(hits:1)
            let hit=npc.update(at:10.1,active:true,snapshot:snapshot)
            check(has(hit,"ped/hit_walk"),"NPC melee response lost fixed reaction damage25")
            check(!npc.animator.stunned,"NPC forwarded human stun ownership")
            let before=hit!.blends.first{$0.clip=="ped/hit_walk"}!.time
            let repeated=npc.update(at:10.2,active:true,snapshot:snapshot)
            check(repeated!.blends.first{$0.clip=="ped/hit_walk"}!.time>before,"Unchanged counter restarted flinch")
        }
        for suppressed in [UInt8(49),51] {
            let npc=owner();var snapshot=NativeAmbientPedestrianAnimation.Snapshot(state:state())
            _=npc.update(at:10,active:true,snapshot:snapshot);snapshot.state=state(hits:1,weapon:suppressed)
            let frame=npc.update(at:10.1,active:true,snapshot:snapshot)
            check(!frame!.blends.contains{$0.clip.contains("hit_") || $0.clip.contains("dam_")},"Suppressed NPC weapon invented flinch")
        }
        do {
            let npc=owner();var snapshot=NativeAmbientPedestrianAnimation.Snapshot(state:state(hits:31))
            _=npc.update(at:10,active:true,snapshot:snapshot);snapshot.state=state(hits:0)
            check(!has(npc.update(at:10.1,active:true,snapshot:snapshot),"ped/hit_walk"),"Zero wrap reacted")
            snapshot.state=state(hits:1)
            check(has(npc.update(at:10.2,active:true,snapshot:snapshot),"ped/hit_walk"),"Counter after zero wrap was lost")
        }
        do {
            let npc=owner();var snapshot=NativeAmbientPedestrianAnimation.Snapshot(flags:1,state:state(hits:1,weapon:25))
            _=npc.update(at:10,active:true,snapshot:snapshot)
            check(npc.animator.dead,"Causal down did not persist")
            _=npc.update(at:10.2,active:true,snapshot:snapshot);snapshot.flags=0
            check(has(npc.update(at:10.22,active:true,snapshot:snapshot),"ped/getup_front"),"Face-down get-up orientation lost")
        }
        do {
            let npc=owner();var snapshot=NativeAmbientPedestrianAnimation.Snapshot(flags:1,state:state())
            _=npc.update(at:10,active:true,snapshot:snapshot)
            npc.acceptRider(lying:true)
            let arrived=npc.update(at:10.01,active:true,snapshot:snapshot)!
            check(npc.animator.dead,"Lying handoff lost authoritative down state")
            check(arrived.blends.contains{$0.clip=="ped/floor_hit" && $0.time>=1 && $0.weight>0},"Lying rider replayed upright death animation")
            snapshot.flags=0
            check(has(npc.update(at:10.03,active:true,snapshot:snapshot),"ped/getup"),"Lying arrival could not recover after server down cleared")
        }
        do {
            let npc=owner();var snapshot=NativeAmbientPedestrianAnimation.Snapshot(flags:1,state:state())
            _=npc.update(at:10,active:true,snapshot:snapshot)
            npc.acceptRider(lying:false);snapshot.flags=0
            check(has(npc.update(at:10.1,active:true,snapshot:snapshot),"ped/getup"),"Upright handoff erased existing NPC recovery transition")
        }
        let side=NativeAmbientPedestrianAnimation.incomingSide
        check(side(.pi/2,0)==0,"North front")
        check(side(0,0)==3,"East/right converted to left")
        check(side(.pi,0)==1,"West/left converted to right")
        check(side(3 * .pi/2,0)==2,"South back")
        let weaponData=Data("""
        {"weapons":[
        {"id":0,"twin":false,"arm":false,"reloads":false,"through":false,"clips":{"guardIdle":"ped/fightsh_fwd"}},
        {"id":22,"twin":false,"arm":true,"reloads":false,"through":false,"loop":{"start":0,"end":0.5,"fire":0.1},"clips":{"fire":"ped/gun_stand","aim":"ped/gun_stand"}}
        ]}
        """.utf8)
        let kits=try! NativeFootWeaponAnimation.load(data:weaponData)
        for mood in [UInt8(0),4,6,7] {
            for speed in [0.0,0.15,0.151,1.0] {
                let npc=NativeAmbientPedestrianAnimation(library:library,style:.init(),weapons:kits,random:{0.25})
                let snapshot=NativeAmbientPedestrianAnimation.Snapshot(speed:speed,state:state(crouched:true,mood:mood))
                _=npc.update(at:10,active:true,snapshot:snapshot)
                let frame=npc.update(at:10.3,active:true,snapshot:snapshot)!
                let taskStance=mood != 0 && mood != 7 && speed<=0.15
                check((frame.crouchShare>0)==taskStance,"NPC crouch escaped task/speed admission")
                check(npc.animator.armedWith==(mood==4 ? 0:nil),"Calm NPC acquired unarmed fighting kit")
                check((npc.animator.reportedAction==36)==(mood==4 && speed<=0.15),"NPC guard escaped fight/stationary task")
            }
        }
        let aim=NativeAmbientPedestrianAnimation(library:library,style:.init(),weapons:kits,random:{0.25})
        let aiming=NativeAmbientPedestrianAnimation.Snapshot(state:state(mood:6,held:22))
        _=aim.update(at:10,active:true,snapshot:aiming);_=aim.update(at:10.3,active:true,snapshot:aiming)
        check(aim.animator.armedWith==22 && aim.animator.gunUp,"Stationary armed AIM task did not aim")
        // The actual common controller receives the same120Hz pose intervals
        // regardless of display cadence; input speed selects pace, not an
        // unintended idle/walk mixture. These are authored tracks, not retail.
        let schedules=[[1.0/20],[1.0/30],[1.0/60],[1.0/120],[0.2],[0.011,0.039,0.2,0.04]]
        for (speed,flags,mood) in [(1.1,UInt8(0),UInt8(0)),(3.2,4,0),(3.2,0,4)] {
            var reference:NativeFootAnimation.Frame?,referenceTravel=SIMD2<Double>.zero,referenceSteps:[String]=[]
            for schedule in schedules {
                let npc=owner(),snapshot=NativeAmbientPedestrianAnimation.Snapshot(speed:speed,flags:flags,state:state(mood:mood))
                var time=10.0,index=0,travel=SIMD2<Double>.zero,steps:[String]=[]
                var frame=npc.update(at:time,active:true,snapshot:snapshot)!
                while time<13.2-1e-9 {
                    time=min(13.2,time+schedule[index%schedule.count]);index+=1
                    frame=npc.update(at:time,active:true,snapshot:snapshot)!
                    travel+=frame.travel;steps+=frame.steps
                }
                if let expected=reference {
                    check(simd_length(travel-referenceTravel)<1e-7,"NPC gait root distance depends on display cadence")
                    check(steps==referenceSteps,"NPC cadence loses/duplicates footstep markers")
                    check(frame.blends.count==expected.blends.count,"NPC cadence changes pose roles")
                    for (a,b) in zip(frame.blends,expected.blends) {
                        check(a.clip==b.clip && abs(a.time-b.time)<1e-7 && abs(a.weight-b.weight)<1e-7,"NPC cadence changes pose phase/blend")
                    }
                }else{reference=frame;referenceTravel=travel;referenceSteps=steps}
            }
        }
        print("PASS NPC animation candidate: \(checks) authored actual-CLP/controller checks; integration, actual archived pose comparison and retail remain separate")
    }
}
