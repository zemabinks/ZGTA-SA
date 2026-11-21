// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

enum Failure:Error{case failed(String)}
@main struct HumanShotGate {
    static var checks=0
    static func require(_ yes:Bool,_ text:String)throws{checks+=1;if !yes{throw Failure.failed(text)}}
    static func near(_ a:SIMD3<Double>,_ b:SIMD3<Double>,_ text:String)throws{
        try require(simd_distance(a,b)<1e-10,text)
    }
    static func row(_ kind:Any=1,weapon:Int=22,origin:[Double]=[0,0,1.3],end:[Double]=[12,0,1.3],piece:Any=9)->[String:Any] {
        ["from":"peer","w":weapon,"o":origin,"h":end,"ht":kind,"bp":piece]
    }
    static func particles()throws->NativeParticleEffects {
        var systems:[String:Any]=[:]
        let names=["prt_blood","prt_gunshell","gunsmoke"]
        for name in names{
            let infos:[String:Any]=["emlife":["life":[[0,1]]],"emrate":["rate":[[0,10]]],
                "size":["sizex":[[0,1]],"sizey":[[0,1]]],"groundcollide":["enabled":[[0,1]]],
                "colour":["red":[[0,1]],"green":[[0,1]],"blue":[[0,1]],"alpha":[[0,1]]]]
            systems[name]=["length":0.2,"emitters":[["texture":name,"infos":infos]]]
        }
        return try .init(data:JSONSerialization.data(withJSONObject:["systems":systems]),textures:Set(names),random:{0.5})
    }
    static func main()throws {
        typealias V=SIMD3<Double>
        let expected:[NativeOrdinaryShot.Impact?]=[nil,.person,.car,.car,.world,.world]
        for (index,kind)in [0,1,2,3,4,255].enumerated(){
            let packet=NativeHumanShots.Packet(row(kind))!
            try require(packet.kind==expected[index],"Human hit-kind mapping")
            try require(packet.reportsWorldShot==(kind==4),"Exact world callback kind")
            try require(packet.piece==9,"Protocol HEAD piece was lost")
        }
        for bad:Any in [true,"9",9.5,Double.nan] {
            try require(NativeHumanShots.Packet(row(piece:bad))?.piece==nil,"Noninteger body piece accepted")
        }
        for field in ["from","w","o","h"] {
            var bad=row();bad.removeValue(forKey:field)
            try require(NativeHumanShots.Packet(bad)==nil,"Missing packet field")
        }
        for bad:Any in [true,[0,1],[0,Double.infinity,1],["0",1,2]] {
            var invalid=row();invalid["o"]=bad
            try require(NativeHumanShots.Packet(invalid)==nil,"Malformed origin accepted")
        }
        let owner=NativeHumanShots()
        let received=NativeHumanShots.Packet(row(3,weapon:38))!
        let immediate=owner.receive(received,footAppearance:false,at:10)!
        try require(immediate.soundWeapon==31 && immediate.event.weapon==38,"Nonfoot minigun audio remap")
        try require(immediate.event.impact == .car && owner.queued("peer")==0,"Immediate branch was queued")
        let muzzle=V(0,0,1.3)
        let exactMilliseconds=NativeHumanShots()
        _=exactMilliseconds.receive(.init(row())!,footAppearance:true,at:1)
        let tied=exactMilliseconds.marker(shooter:"peer",weapon:31,left:false,at:1.6,muzzle:muzzle,
            heading:0,pitch:0,range:100,along:nil)!
        try require(tied.usedPacket,"Exact600ms hit expired because its lifetime used seconds subtraction")
        for index in 0..<8 {
            let packet=NativeHumanShots.Packet(row(1,weapon:22,end:[Double(index),2,3]))!
            try require(owner.receive(packet,footAppearance:true,at:10)==nil,"Foot receive emitted early")
        }
        try require(owner.queued("peer")==6,"Foot pending queue cap")
        for index in 2..<8 {
            let marker=owner.marker(shooter:"peer",weapon:31,left:true,at:10.6,muzzle:muzzle,
                heading:0,pitch:0,range:100,along:{_,_,_ in fatalError("Queued packet queried prediction")})!
            try require(marker.usedPacket && marker.event.weapon==31,"Marker did not use current weapon")
            try near(marker.event.end,V(Double(index),2,3),"Queue order or inclusive 600ms lifetime")
            try near(marker.event.origin,muzzle,"Near packet did not use held muzzle")
            try near(marker.direction,V(0,1,0),"Native heading direction")
            try require(marker.event.piece==9 && marker.left,"Hand or body piece lost")
        }
        try require(owner.queued("peer")==0,"Consumed packets retained")
        for distance in [2.999,3.0,3.001] {
            _=owner.receive(.init(row(4,origin:[distance,0,1.3]))!,footAppearance:true,at:20)
            let marker=owner.marker(shooter:"peer",weapon:24,left:false,at:20,muzzle:muzzle,
                heading:.pi/2,pitch:0,range:30,along:nil)!
            try near(marker.event.origin,distance<3 ? muzzle:V(distance,0,1.3),"Strict 3m origin boundary")
            try near(marker.muzzle,muzzle,"Packet origin replaced smoke/audio/pass source")
            try near(marker.direction,V(1,0,0),"Quarter-turn axis conversion")
            try require(marker.reportsWorldShot,"Queued world kind metadata")
        }
        _=owner.receive(.init(row())!,footAppearance:true,at:30)
        var queries=0
        let predicted=owner.marker(shooter:"peer",weapon:22,left:false,at:30.60001,muzzle:muzzle,
            heading:0,pitch:.pi/6,range:60,along:{p,d,r in
                queries+=1;try! near(p,muzzle,"Prediction start");return 12
            })!
        try require(!predicted.usedPacket && queries==1 && predicted.event.impact == .world,"Expired packet did not predict")
        try near(predicted.event.end,muzzle+V(0,sqrt(3)/2,0.5)*12,"Predicted ray pitch or distance")
        for value:Double? in [nil,-1,61,.infinity,.nan] {
            let marker=owner.marker(shooter:"peer",weapon:22,left:false,at:40,muzzle:muzzle,
                heading:0,pitch:0,range:60,along:{_,_,_ in value})!
            try require(marker.event.impact==nil,"Invalid prediction became world hit")
            try near(marker.event.end,muzzle+V(0,60,0),"Missing/invalid ray did not use range")
        }
        _=owner.receive(.init(row())!,footAppearance:true,at:40);owner.retain(["other"])
        try require(owner.queued("peer")==0,"Removed shooter retained queue")
        _=owner.receive(.init(row())!,footAppearance:true,at:40);owner.clear()
        try require(owner.queued("peer")==0,"World reset retained queue")
        let particles=try particles(),fx=NativeOrdinaryShotEffects(random:{0.5})
        fx.particles=particles;fx.eye=muzzle
        fx.shot(.init(weapon:22,origin:muzzle,end:muzzle+V(1,0,0),impact:.person,piece:9),gunsmoke:false)
        try require(particles.shown.count==16,"Head shot did not double blood")
        particles.clear();fx.shot(.init(weapon:22,origin:muzzle,end:muzzle+V(1,0,0),impact:.person,piece:5),gunsmoke:false)
        try require(particles.shown.count==8,"Skeleton bone5 was mistaken for protocol HEAD9")
        var floorAt:V?;fx.shellFloor={p,drop in floorAt=p;return 0.25}
        for (weapon,back,size) in [(22,0.2,0.25),(25,0.3,0.45),(26,0.3,0.45),(29,0.2,0.3),(31,0.65,0.25)] {
            particles.clear();fx.casing(weapon:weapon,at:muzzle,direction:V(0,1,0))
            try require(particles.shown.count==1,"Supported casing did not spawn")
            let shell=particles.shown[0]
            try near(shell.position,muzzle-V(0,back,0),"Shell back offset")
            try near(shell.velocity,V(1,0,1),"Shell ejection axes/vertical random")
            try require(shell.big==size && shell.floor==0.25,"Shell size or ground ownership")
            try near(floorAt!,shell.position,"Floor sampled at muzzle instead of actual shell spawn")
            try near(shell.tint,NativeOrdinaryShotEffects.linear(weapon==25 ? V(0.6,0.1,0.1):V(repeating:0.5)),"Shell tint/shotgun26 exception")
        }
        particles.clear();fx.casing(weapon:38,at:muzzle,direction:V(0,1,0))
        try require(particles.shown.isEmpty,"First minigun casing must skip")
        fx.casing(weapon:38,at:muzzle,direction:V(0,1,0))
        try require(particles.shown.count==1,"Second minigun casing must emit")
        particles.clear();fx.eye=muzzle+V(100,0,0);fx.casing(weapon:22,at:muzzle,direction:V(0,1,0))
        try require(particles.shown.isEmpty,"Far casing ignored 10m cull")
        let flashes=NativeWeaponFlash()
        flashes.fire(identity:"a",weapon:22,left:true,twin:false,at:10)
        try require(flashes.visible(identity:"a",weapon:22,left:false,at:10.049),"Single gun did not flash right")
        try require(!flashes.visible(identity:"a",weapon:22,left:true,at:10),"Single gun invented left flash")
        try require(!flashes.visible(identity:"b",weapon:22,left:false,at:10),"Shared model leaked another holder's flash")
        try require(!flashes.visible(identity:"a",weapon:22,left:false,at:10.05),"Flash exceeded .05s")
        flashes.fire(identity:"a",weapon:22,left:true,twin:true,at:11)
        try require(flashes.visible(identity:"a",weapon:22,left:true,at:11.01),"Twin hand lost")
        try require(!flashes.visible(identity:"a",weapon:31,left:true,at:11.01),"Switched weapon inherited flash")
        flashes.retain(["b"]);try require(!flashes.visible(identity:"a",weapon:22,left:true,at:11.01),"Removed holder retained flash")
        flashes.fire(identity:"a",weapon:22,left:false,twin:false,at:12,model:"first")
        flashes.select(identity:"a",weapon:31,model:"first");flashes.select(identity:"a",weapon:22,model:"first")
        try require(!flashes.visible(identity:"a",weapon:22,left:false,at:12.01),"Rapid switch back revived an old muzzle flash")
        flashes.fire(identity:"a",weapon:22,left:false,twin:false,at:13,model:"first")
        flashes.select(identity:"a",weapon:22,model:"second")
        try require(!flashes.visible(identity:"a",weapon:22,left:false,at:13.01),"New character model inherited an old flash")
        flashes.fire(identity:"a",weapon:22,left:false,twin:false,at:14,model:"second",ready:false)
        flashes.select(identity:"a",weapon:22,model:"second")
        try require(!flashes.visible(identity:"a",weapon:22,left:false,at:14.01),"A missing held resource scheduled a delayed flash")
        let audio=NativeRemoteGunAudio()
        let held=audio.hold(identity:"peer",weapon:38,at:muzzle)!
        try require(held.held && held.key=="minigun:peer","Per-player remote minigun identity")
        try require(audio.advance(delta:0.1).isEmpty,"Held loop expired before .2s")
        _=audio.hold(identity:"peer",weapon:38,at:V(2,3,4))
        try require(audio.advance(delta:0.1).isEmpty,"Marker refresh did not reset loop idle")
        let ended=audio.advance(delta:0.1)
        try require(ended.count==1 && !ended[0].held && ended[0].tail,"Minigun equality .2s stop/tail")
        try near(ended[0].position,V(2,3,4),"Stop tail lost latest muzzle")
        try require(audio.advance(delta:0.1).isEmpty,"Stop tail replayed")
        _=audio.hold(identity:"peer",weapon:38,at:muzzle)
        try require(audio.advance(delta:0.2).count==1,"Direct audio-kernel equality .2s did not expire")
        _=audio.hold(identity:"peer",weapon:38,at:muzzle)
        let cleared=audio.clear()
        try require(cleared.count==1 && !cleared[0].tail,"World cleanup invented minigun stop tail")
        for fps in [30,60,120] {
            _=audio.hold(identity:"peer",weapon:38,at:muzzle)
            var stop:[NativeRemoteGunAudio.Event]=[]
            for _ in 0..<(fps/4){stop+=audio.advance(delta:1/Double(fps))}
            try require(stop.count==1 && stop[0].tail,"Loop expiry depended on display rate")
        }
        print("PASS \(checks) actual human queue/marker, prediction, head blood, shell and flash-owner checks; authored inputs, no retail or app claim")
    }
}
