// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main enum NPCActivityTests {
    static var checks=0
    static func check(_ value:Bool,_ message:String){checks+=1;if !value{FileHandle.standardError.write(Data(("FAIL: "+message+"\n").utf8));exit(1)}}
    static func word(_ value:UInt32,_ data:inout Data){var v=value.littleEndian;withUnsafeBytes(of:&v){data.append(contentsOf:$0)}}
    static func number(_ value:Float,_ data:inout Data){word(value.bitPattern,&data)}
    static func text(_ value:String,_ data:inout Data){var n=UInt16(value.utf8.count).littleEndian;withUnsafeBytes(of:&n){data.append(contentsOf:$0)};data.append(contentsOf:value.utf8)}
    static func fixture()->NativeSkeletalAnimationLibrary {
        var names=Set(NativeFootAnimation.actions.values.map{"ped/"+$0}+[
            "ped/idle_stance","ped/walk_player","ped/run_player","ped/sprint_civi",
            "ped/seat_down","ped/seat_idle","ped/seat_up","ped/cower","ped/handsup","ped/arrestgun",
            "ped/roadcross","ped/roadcross_female","ped/roadcross_old","ped/roadcross_gang",
            "ped/idle_hbhb","ped/xpressscratch","ped/idle_tired","ped/woman_idlestance",
            "ped/idlestance_old","ped/idle_gang1","ped/idlestance_fat","ped/idle_chat","ped/endchat_01","medic/cpr"])
        for mood in [UInt8(9),10,11,14,15] {for female in [false,true] {
            if let value=NativeAmbientPedestrianActivity.definition(mood:mood,female:female) {
                names.insert(value.enter);if let loop=value.loop{names.insert(loop)};if let exit=value.exit{names.insert(exit)}
            }
        }}
        var data=Data();[UInt32(0x31504c43),UInt32(names.count),0,1].forEach{word($0,&data)}
        for name in names.sorted() {
            let duration:Float=name=="ped/seat_down" ? 1.5:1
            text(name,&data);number(duration,&data);word(1,&data);word(0,&data);word(2,&data);word(1,&data)
            let distance:Float=name=="ped/walk_player" ? 1:name=="ped/run_player" ? 3:name=="ped/sprint_civi" ? 4:0.1
            for time in [Float(0),duration] {number(time,&data);[Float(0),0,0,1,0,distance*time,0].forEach{number($0,&data)}}
        }
        guard let value=NativeSkeletalAnimationLibrary(data:data)else{fatalError("Authored CLP rejected")};return value
    }
    static func state(_ mood:UInt8)->NativeAmbientPedestrianProtocol.State {
        .init(id:17,mood:mood,burning:false,phone:false,crouching:false,cpr:false,weapon:0,hitWeapon:0,
            hitCounter:0,hitPiece:0,hitFromWire:0,faceWire:0,foe:0,thrown:0)
    }
    static func blend(_ frame:NativeFootAnimation.Frame?,_ name:String)->NativeSkeletalBlend?{frame?.blends.first{$0.clip==name && $0.weight>0.001}}
    static func main()throws {
        let authored=fixture()
        func owner(_ library:NativeSkeletalAnimationLibrary)->NativeAmbientPedestrianAnimation{.init(library:library,style:.init(),weapons:[:],random:{0.25})}
        var libraries:[(String,NativeSkeletalAnimationLibrary)]=[("authored",authored)]
        if CommandLine.arguments.count>1 {
            guard let original=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))else{fatalError("Original CLP rejected")}
            libraries.append(("owner-local original",original))
        }
        for (label,library) in libraries {
            for mood in [UInt8(9),10,11,14,15] {for female in [false,true] {
                let npc=owner(library),activity=NativeAmbientPedestrianActivity.definition(mood:mood,female:female)!
                let snapshot=NativeAmbientPedestrianAnimation.Snapshot(state:state(mood),id:17,seed:9,femaleActivity:female)
                _=npc.update(at:10,active:true,snapshot:snapshot)
                let frame=npc.update(at:10.2,active:true,snapshot:snapshot)
                let expected=activity.loop ?? activity.enter
                check(library.contains(expected),label+" original activity unavailable: "+expected)
                check(blend(frame,expected) != nil,label+" initial activity did not reach actual common-controller blends: "+expected)
                check(blend(frame,expected)?.rooted==(activity.loop != nil),label+" activity root policy")
                var down=snapshot;down.flags=1
                _=npc.update(at:10.25,active:true,snapshot:down)
                check(npc.animator.dead,label+" activity blocked persistent death")
                var up=snapshot;up.state=state(0)
                _=npc.update(at:10.3,active:true,snapshot:up)
                check(!npc.animator.dead,label+" activity blocked authoritative recovery")
            }}
            for (walk,expected) in [("ped/walk_player","ped/roadcross"),("ped/walk_old","ped/roadcross_old"),
                ("ped/walk_fat","ped/roadcross"),("ped/walk_gang","ped/roadcross_gang"),("ped/woman_walknorm","ped/roadcross_female")] {
                var style=NativeFootAnimationStyle();style.walk=walk
                let waiting=NativeAmbientPedestrianAnimation(library:library,style:style,weapons:[:],random:{0.25})
                var snapshot=NativeAmbientPedestrianAnimation.Snapshot(flags:2,state:state(0),id:17,seed:9,waitingLinkKind:1)
                _=waiting.update(at:40,active:true,snapshot:snapshot)
                check(blend(waiting.update(at:40.2,active:true,snapshot:snapshot),expected) != nil,label+" waiting clip/style not integrated")
                snapshot.flags=3;_=waiting.update(at:40.3,active:true,snapshot:snapshot)
                check(waiting.animator.dead,label+" waiting script prevented server down")
                snapshot.flags=0;_=waiting.update(at:40.4,active:true,snapshot:snapshot)
                check(!waiting.animator.dead,label+" waiting script prevented authoritative recovery")
            }
            let delayed=owner(library)
            var wait=NativeAmbientPedestrianAnimation.Snapshot(flags:2,state:state(0),id:17,seed:9,waitingLinkKind:0)
            _=delayed.update(at:50,active:true,snapshot:wait)
            var waitTime=50.0
            while waitTime<53.5 {waitTime=min(53.5,waitTime+0.1);_=delayed.update(at:waitTime,active:true,snapshot:wait)}
            check(blend(delayed.update(at:53.5,active:true,snapshot:wait),"ped/idle_tired")==nil,label+" delayed idle before strict boundary")
            check(blend(delayed.update(at:53.7,active:true,snapshot:wait),"ped/idle_tired") != nil,label+" delayed original idle not rendered by common controller")
            wait.flags=0;_=delayed.update(at:53.8,active:true,snapshot:wait)
            var cleared:NativeFootAnimation.Frame?
            for i in 1...6 {cleared=delayed.update(at:53.8+Double(i)*0.1,active:true,snapshot:wait)}
            check(blend(cleared,"ped/idle_tired")==nil,label+" clear failed to fade waiting script")
            // A calm lifetime must enter a newly selected seat, using its real
            // admitted duration before looping, then run the original exit.
            let npc=owner(library);var snapshot=NativeAmbientPedestrianAnimation.Snapshot(state:state(0),id:17,seed:9)
            _=npc.update(at:20,active:true,snapshot:snapshot);snapshot.state=state(9)
            _=npc.update(at:20.1,active:true,snapshot:snapshot)
            check(blend(npc.update(at:20.2,active:true,snapshot:snapshot),"ped/seat_down") != nil,label+" missing seat entry")
            let deadline=20.1+max(0,library.duration(of:"ped/seat_down")!-0.15)
            var time=20.2
            while time<deadline-0.02 {time=min(deadline-0.02,time+0.1);_=npc.update(at:time,active:true,snapshot:snapshot)}
            check(blend(npc.update(at:deadline-0.01,active:true,snapshot:snapshot),"ped/seat_idle")==nil,label+" seat loop too early")
            _=npc.update(at:deadline+0.01,active:true,snapshot:snapshot)
            check(blend(npc.update(at:deadline+0.15,active:true,snapshot:snapshot),"ped/seat_idle") != nil,label+" seat deadline lost")
            snapshot.state=state(0);_=npc.update(at:deadline+0.2,active:true,snapshot:snapshot)
            check(blend(npc.update(at:deadline+0.3,active:true,snapshot:snapshot),"ped/seat_up") != nil,label+" seat exit lost")
        }
        for cadence in [20.0,30,60,120] {
            let npc=owner(authored);var snapshot=NativeAmbientPedestrianAnimation.Snapshot(state:state(0))
            _=npc.update(at:30,active:true,snapshot:snapshot);snapshot.state=state(9)
            _=npc.update(at:30.1,active:true,snapshot:snapshot)
            var time=30.1,frame:NativeFootAnimation.Frame?
            while time<32-1e-9 {time=min(32,time+1/cadence);frame=npc.update(at:time,active:true,snapshot:snapshot)}
            check(blend(frame,"ped/seat_idle") != nil,"Seat loop lost at cadence \(cadence)")
            check(abs((blend(frame,"ped/seat_idle")?.time ?? -1)-0.55)<0.06,"Seat clock diverged at cadence \(cadence)")
        }
        do {
            let rows:[[String:Any]]=[["legacyID":10,"nativeID":2,"model":"sample_a","femaleActivity":true],["legacyID":11,"nativeID":3,"model":"sample_b"]]
            func data(_ rows:[[String:Any]])throws->Data{try JSONSerialization.data(withJSONObject:["schema":1,"skins":rows])}
            let catalog=try NativeSAMPSkinCatalog(data:data(rows))
            check(catalog.femaleActivity(forModel:"sample_a"),"Original category lost")
            check(!catalog.femaleActivity(forModel:"sample_b") && !catalog.femaleActivity(forModel:"unknown"),"Absent category guessed")
            check(catalog.nativeSkin(forLegacy:10)==2,"Activity metadata changed skin identity")
            let owned=try NativeSAMPSkinCatalog(data:data(rows),sourceIdentity:"source-a")
            check(owned.femaleActivity(forModel:"sample_a",sourceIdentity:"source-a"),"Current resource category rejected")
            check(!owned.femaleActivity(forModel:"sample_a",sourceIdentity:"source-b"),"Old resource category survived source replacement")
            let invalidValues:[Any]=[1,"true",NSNull()]
            for invalid in invalidValues {
                var broken=rows;broken[0]["femaleActivity"]=invalid
                check((try? NativeSAMPSkinCatalog(data:data(broken)))==nil,"Nonboolean category admitted")
            }
            var conflict=rows;conflict[1]["model"]="sample_a";conflict[1]["femaleActivity"]=false
            check((try? NativeSAMPSkinCatalog(data:data(conflict)))==nil,"Conflicting model category admitted")
        }
        print("PASS \(checks) actual NPC/common-controller, admitted CLP and catalog checks; \(libraries.count) libraries. No rendered, retail or hardware claim.")
    }
}
