// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main enum TrafficShotTests {
    typealias P=NativeAmbientTrafficProtocol
    typealias S=NativeTrafficShotSource
    static var checks=0
    static func check(_ value:Bool,_ message:String)throws {
        checks+=1;if !value{throw NSError(domain:message,code:1)}
    }
    static func close(_ a:SIMD3<Double>,_ b:SIMD3<Double>)->Bool{simd_distance(a,b)<1e-10}
    static func car(heading:Double=0,pitch:Double=0,distance:Double=3,visible:Bool=true,rear:Bool=false)->S.Car {
        let yaw=simd_quatd(angle:-heading,axis:SIMD3(0,0,1)),tilt=simd_quatd(angle:pitch,axis:SIMD3(1,0,0))
        return .init(position:SIMD3(10,20,30),rotation:yaw*tilt,distance:distance,visible:visible,hasRearPassenger:rear)
    }
    static func origins()throws {
        var requested:[Int]=[]
        let empty:(Int)->SIMD3<Double>?={requested.append($0);return nil}
        let right=S.sample(target:SIMD3(11,25,30),car:car(),muzzle:empty)!
        try check(right.side==1 && right.seat==1 && requested==[1] && !right.posed,"Right side must select only front passenger")
        try check(close(right.origin,SIMD3(10.95,19.7,31)),"Fallback changed axis or added a model origin")
        requested=[]
        let left=S.sample(target:SIMD3(9,25,30),car:car(),muzzle:empty)!
        try check(left.side == -1 && left.seat==0 && requested==[0],"Left side without rear controller must select driver")
        try check(close(left.origin,SIMD3(9.05,19.7,31)),"Left fallback origin")
        requested=[]
        let rear=S.sample(target:SIMD3(9,25,30),car:car(rear:true),muzzle:empty)!
        try check(rear.seat==2 && requested==[2] && !rear.posed,"Missing rear muzzle must not try driver")
        requested=[]
        let boundary=S.sample(target:SIMD3(10,25,30),car:car(rear:true),muzzle:empty)!
        try check(boundary.side==1 && boundary.seat==1 && requested==[1],"Local X equality belongs to positive side")
        let yaw=S.sample(target:SIMD3(20,18,30),car:car(heading:.pi/2),muzzle:{_ in nil})!
        try check(yaw.side==1 && close(yaw.origin,SIMD3(9.7,19.05,31)),"Inverse car yaw or rotated fallback is incorrect")
        let pitch=S.sample(target:SIMD3(11,25,30),car:car(pitch:.pi/2),muzzle:{_ in nil})!
        try check(close(pitch.origin,SIMD3(10.95,19,29.7)),"Car pitch must affect all fallback coordinates")
        let posed=S.sample(target:SIMD3(9,25,30),car:car(rear:true),muzzle:{seat in seat==2 ? SIMD3(13,17,32):nil})!
        try check(posed.posed && posed.seat==2 && posed.origin==SIMD3(13,17,32),"Ready selected holder muzzle must be used unchanged")
        let invalid=S.sample(target:SIMD3(9,25,30),car:car(rear:true),muzzle:{_ in SIMD3(.nan,0,0)})!
        try check(!invalid.posed && close(invalid.origin,SIMD3(9.05,19.7,31)),"Invalid muzzle must use the car fallback")
        var calls=0
        for body in [car(distance:150.001),car(visible:false),car(heading:.nan),car(pitch:.infinity),car(distance:.nan)] {
            try check(S.sample(target:SIMD3(11,25,30),car:body,muzzle:{_ in calls+=1;return .zero})==nil,"Unadmitted car emitted a shot")
        }
        try check(calls==0,"Rejected shots touched a holder")
        try check(S.sample(target:SIMD3(11,25,30),car:car(distance:150),muzzle:{_ in nil}) != nil,"150m equality changed")
        try check(S.sample(target:SIMD3(.nan,25,30),car:car(),muzzle:{_ in nil})==nil,"Nonfinite target admitted")
    }
    static func bytes<T:FixedWidthInteger>(_ values:[T])->Data {
        var result=Data();for value in values{var v=value.littleEndian;withUnsafeBytes(of:&v){result.append(contentsOf:$0)}};return result
    }
    // Authored minimal road graph, with no original game data.
    static func graph()throws->NativeAmbientTrafficRoads {
        var data=bytes([UInt32(0x44524453),1,2,2,1,0,0,0])
        let parts:[Data]=[bytes([Int16(0),0,0,80,0,0]),bytes([UInt32(0),2,2]),bytes([UInt32(0),0]),Data([0,0]),
            bytes([UInt32(1),1]),bytes([UInt32(0),0]),bytes([Int16(40),0]),bytes([UInt32(1)]),Data([100,0]),bytes([UInt32(1<<8|1<<11)])]
        for part in parts{data.append(part);data.append(Data(count:(4-part.count%4)%4))}
        return try .init(data:data,expectedCRC:NativeAmbientPedestrianPaths.crc32(data))
    }
    static func immediateDelivery()throws {
        let graph=try graph(),scene=NativeAmbientTrafficScene()
        let shot=P.Shot(id:17,weapon:31,target:SIMD3(12,7,3),kind:1)
        try check(scene.receive(.shots([shot]),serverNow:100000,received:100).isEmpty,"Unconfigured scene emitted a shot")
        _=scene.configure(level:1,roads:graph.crc32,source:"authored-A")
        let base=P.Base(identity:.init(id:17,model:420,first:6,second:1),first:.init(link:0,lane:0),second:.init(link:1,lane:0),
            next:nil,nextLane:0,progress:0.5,speed:2,wanted:2,rate:1)
        scene.receive(.base(atServerMilliseconds:100000,[base]),serverNow:100000,received:100)
        let pending=scene.pendingCount
        try check(scene.receive(.shots([shot]),serverNow:100000,received:100).isEmpty && scene.pendingCount==pending,"Pre-graph shots were buffered or delivered")
        _=scene.install(graph)
        try check(scene.pendingCount==0 && scene.traffic.actors.count==1,"Graph replay changed the authoritative roster")
        scene.receive(.more([.init(id:17,side:0,aim:0,health:500,flags:128)]),serverNow:100000,received:100)
        let values=scene.receive(.shots([shot,.init(id:99,weapon:22,target:.zero,kind:0),shot]),serverNow:100000,received:100)
        try check(values==[shot,shot],"Known immediate observations were dropped, reordered or deduplicated")
        try check(scene.traffic.actors[17]?.health==500,"Shot observation changed authoritative health")
        scene.receive(.gone([17]),serverNow:100001,received:100.001)
        try check(scene.receive(.shots([shot]),serverNow:100001,received:100.001).isEmpty,"Removed actor still emitted observations")
        _=scene.configure(level:1,roads:graph.crc32,source:"authored-B")
        try check(scene.receive(.shots([shot]),serverNow:100001,received:100.001).isEmpty && scene.pendingCount==0,"Source replacement replayed a stale shot")
        scene.reset()
        try check(scene.receive(.shots([shot]),serverNow:100001,received:100.001).isEmpty,"Disconnect retained shot work")
    }
    static func impacts()throws {
        var calls=0
        let trace:NativeOrdinaryShot.Along={origin,direction,length in
            calls+=1
            try! check(origin==SIMD3(1,2,3) && direction==SIMD3(1,0,0) && length==10,"World query received a wrong ray")
            return 4
        }
        func event(_ kind:UInt8,_ end:SIMD3<Double> = SIMD3(11,2,3),_ along:NativeOrdinaryShot.Along?=nil)->NativeOrdinaryShot.Event? {
            NativeOrdinaryShot.traffic(.init(id:17,weapon:31,target:end,kind:kind),origin:SIMD3(1,2,3),along:along)
        }
        let world=event(0,SIMD3(11,2,3),trace)!
        try check(world.impact == .world && world.end==SIMD3(5,2,3) && calls==1,"Confirmed kind0 hit did not clip the endpoint")
        for (kind,impact) in [(UInt8(1),NativeOrdinaryShot.Impact.person),(UInt8(2),.car)] {
            let value=event(kind,SIMD3(11,2,3),trace)!
            try check(value.impact==impact && value.end==SIMD3(11,2,3) && calls==1,"Announced person/car hit queried or shortened the world ray")
        }
        for kind in [UInt8(3),7,255] {
            let value=event(kind,SIMD3(11,2,3),trace)!
            try check(value.impact==nil && value.end==SIMD3(11,2,3) && calls==1,"Unknown nonzero kind invented a hit or queried the world")
        }
        try check(event(0)!.impact==nil,"Missing geometry query invented a world impact")
        try check(event(0,SIMD3(11,2,3),{_,_,_ in nil})!.impact==nil,"World miss invented an impact")
        for end in [SIMD3(1,2,3),SIMD3(1.5,2,3)] {
            let value=event(0,end,{_,_,_ in calls+=1;return 0})!
            try check(value.impact==nil && value.end==end && calls==1,"Short/equality ray must not query the world")
        }
        for distance in [-1.0,10.001,Double.nan,Double.infinity] {
            let value=event(0,SIMD3(11,2,3),{_,_,_ in distance})!
            try check(value.impact==nil && value.end==SIMD3(11,2,3),"Invalid ray result became a visible impact")
        }
        try check(event(1,SIMD3(.nan,2,3))==nil,"Nonfinite presentation event admitted")
    }
    static func tracers()throws {
        var randomCalls=0
        let pool=NativeShotTracers(random:{randomCalls+=1;return 0.5})
        try check(!pool.shot(from:.zero,to:.zero) && randomCalls==0,"Zero-length shot reserved a tracer")
        for index in 0..<16 {
            try check(pool.shot(from:SIMD3(1,2,3),to:SIMD3(11,2,3)),"Tracer slot \(index) unavailable")
        }
        try check(!pool.shot(from:.zero,to:SIMD3(1,0,0)) && randomCalls==32,"Full pool drew random values or replaced an active line")
        try check(pool.lines.map(\.slot)==Array(0..<16),"Tracer allocation did not use first invisible slot")
        for line in pool.lines {
            try check(line.back==SIMD3(6,2,3) && line.head==SIMD3(9.5,2,3) && line.opacity==1,"Initial randomized segment is incorrect")
        }
        pool.advance(delta:0.075)
        try check(pool.lines.map(\.slot)==Array(0..<10),"Short tracer equality did not expire only slots10...15")
        for line in pool.lines {
            let fraction=line.slot<5 ? 0.75:0.5
            try check(abs(line.opacity-fraction)<1e-12 && close(line.back,SIMD3(9.5-3.5*fraction,2,3)),"Tracer tail/alpha did not share its remaining lifetime")
        }
        try check(pool.shot(from:.zero,to:SIMD3(1,0,0)) && pool.lines.last?.slot==10,"A free short-life slot was not reused")
        pool.advance(delta:-1);pool.advance(delta:.nan)
        try check(pool.lines.count==11,"Invalid display interval changed tracer lifetime")
        pool.advance(delta:0.075)
        try check(pool.lines.map(\.slot)==Array(0..<5),"Second lifetime group equality")
        pool.clear();try check(pool.lines.isEmpty,"World reset retained tracer geometry")
        for fps in [30,60,120] {
            let owner=NativeShotTracers(random:{0.5});_=owner.shot(from:.zero,to:SIMD3(10,0,0))
            for _ in 0..<(fps/5){owner.advance(delta:1/Double(fps))}
            try check(owner.lines.count==1 && abs(owner.lines[0].opacity-1/3)<1e-12,"Tracer phase depends on display rate")
        }
    }
    static func particleFixture()throws->NativeParticleEffects {
        let names=["prt_spark","prt_smokeii_3_expand","prt_blood","prt_sand","gunsmoke","water_splash"]
        var systems:[String:Any]=[:]
        for name in names {
            let infos:[String:Any]=[
                "emlife":["life":[[0,1]]],"emrate":["rate":[[0,10]]],
                "size":["sizex":[[0,1]],"sizey":[[0,1]]],
                "colour":["red":[[0,1]],"green":[[0,1]],"blue":[[0,1]],"alpha":[[0,1]]]
            ]
            let emitter:[String:Any]=["texture":name,"infos":infos]
            systems[name] = ["length":0.2,"emitters":[emitter]]
        }
        return try .init(data:JSONSerialization.data(withJSONObject:["systems":systems]),textures:Set(names),random:{0.5})
    }
    static func effects()throws {
        let particles=try particleFixture(),effects=NativeOrdinaryShotEffects(random:{0.5})
        effects.particles=particles;effects.eye = .zero
        let start=SIMD3<Double>(0,0,1),end=SIMD3<Double>(1,0,1)
        func shot(_ impact:NativeOrdinaryShot.Impact?){effects.shot(.init(weapon:31,origin:start,end:end,impact:impact))}
        func reset(){particles.clear();effects.clear()}
        shot(.car)
        try check(particles.shown.count==9,"Car impact did not create eight sparks and one smoke particle")
        try check(particles.shown.prefix(8).allSatisfy{$0.emitter?.texture=="prt_spark" && $0.velocity==SIMD3(-3,0,0) && $0.life==0.8},"Car hit normal, spark count or lifetime")
        try check(particles.shown.last?.emitter?.texture=="prt_smokeii_3_expand" && particles.shown.last?.life==0.075,"Car impact smoke identity/lifetime")
        reset();shot(.person)
        try check(particles.shown.count==8 && particles.shown.allSatisfy{$0.emitter?.texture=="prt_blood" && $0.velocity==SIMD3(-1.5,0,0) && $0.big==0.85 && $0.life==0.8},"Blood count/reverse ray/multipliers")
        try check(close(particles.shown[0].tint,SIMD3(0.21404114048223255,0,0)),"Blood tint was not converted from sRGB")
        var material=9,unseen=false,calls=0
        effects.struck={origin,direction,length in
            calls+=1
            try! check(close(origin,SIMD3(0.7,0,1)) && direction==SIMD3(1,0,0) && length==0.5,"Short impact material query changed")
            return .init(normal:SIMD3(0,0,1),material:material,surface:2,unseen:unseen)
        }
        reset();shot(.world)
        try check(calls==1 && particles.shown.count==2 && particles.shown.allSatisfy{$0.emitter?.texture=="prt_sand" && $0.velocity==SIMD3(0,0,0.3) && $0.big==0.4 && $0.life==0.3 && $0.faint==0.3},"Sand material did not reach actual particle multipliers")
        material=71;reset();shot(.world)
        try check(particles.shown.count==2 && close(particles.shown[0].tint,SIMD3(repeating:0.31854677812509186)),"Dust material tint/category")
        material=23;reset();shot(.world)
        try check(particles.shown.count==4 && particles.shown.allSatisfy{$0.emitter?.texture=="prt_blood" && $0.velocity==SIMD3(0,0,4) && $0.big==0.85 && $0.life==1},"Wood chip count/velocity/multipliers")
        unseen=true;reset();shot(.world)
        try check(particles.shown.isEmpty && effects.tracers.lines.count==1,"Unseen contact emitted an impact or suppressed tracer")
        unseen=false
        effects.eye=end+SIMD3(25,0,0);reset();shot(.world)
        try check(particles.shown.count==4,"Wood 25m equality changed")
        effects.eye=end+SIMD3(25.001,0,0);reset();shot(.world)
        try check(particles.shown.isEmpty,"Distant wood impact emitted particles")
        material=2
        effects.eye=end+SIMD3(150,0,0);reset();shot(.car)
        try check(particles.shown.count==9,"150m hit equality changed")
        effects.eye=end+SIMD3(150.001,0,0);reset();shot(.car)
        try check(particles.shown.isEmpty,"Out-of-range car impact emitted particles")
        effects.eye=end+SIMD3(1000,0,0);reset();shot(.person)
        try check(particles.shown.count==8,"Blood acquired the unrelated world-hit distance gate")
        try check(NativeOrdinaryShotEffects.style(material:-1,surface:4) == .sand && NativeOrdinaryShotEffects.style(material:-1,surface:3) == .dust && NativeOrdinaryShotEffects.style(material:2,surface:4) == .sparks,"Material presence/surface fallback priority")
        effects.waterLevel={_ in 0};effects.eye = .zero
        reset();effects.shot(.init(weapon:31,origin:SIMD3(0,0,2),end:SIMD3(0,0,-2),impact:nil));particles.update(delta:0.1)
        try check(particles.shown.filter{$0.emitter?.texture=="water_splash"}.count==1 && particles.shown.filter{$0.emitter?.texture=="gunsmoke"}.count==1,"Water crossing or immediate muzzle smoke was not played")
        effects.eye=SIMD3(25,0,0)
        reset();effects.shot(.init(weapon:31,origin:SIMD3(0,0,2),end:SIMD3(0,0,-2),impact:nil));particles.update(delta:0.1)
        try check(!particles.shown.contains{$0.emitter?.texture=="water_splash"},"Water eye25m strict boundary changed")
    }
    static func spatialAudio()throws {
        let row=[10.0,11,12,13,14,1.2,-6,0.9]
        let plan=NativeShotAudioPlan.spatial(row,random:{0.5})!,level=pow(10,-6.0/20)
        try check(plan.layers.map(\.sound)==["143_10","143_11","143_12","143_14"],"Spatial shot used the local stereo pair or omitted a layer")
        try check(plan.layers.map(\.name)==["attack","body","space","tail"],"Shot layer ownership is not stable")
        for (layer,gain) in zip(plan.layers,[0.45,0.8,1,0.3]) {try check(abs(layer.gain-gain*level)<1e-12,"Spatial shot layer gain")}
        try check(abs(plan.layers[2].rate-1.2)<1e-12 && abs(plan.layers[3].rate-0.9*1.18921)<1e-12,"Spatial body spread or tail pitch")
        var noTail=row;noTail[4] = -1
        try check(NativeShotAudioPlan.spatial(noTail,random:{0})!.layers.count==3,"Absent optional tail invented a sound")
        try check(NativeShotAudioPlan.spatial([])==nil,"Missing weapon metadata invented audio")
    }
    static func passage()throws {
        let camera=NativeBulletPass.Camera(eye:.zero,right:SIMD3(1,0,0),up:SIMD3(0,0,1),forward:SIMD3(0,1,0))
        let start=SIMD3<Double>(0,-1,0),end=SIMD3<Double>(0,3,0)
        let owner=NativeBulletPass(random:{0})
        try check(owner.pass(from:start,to:end,audioAvailable:true)==nil,"Missing camera emitted a passage sound")
        owner.update(delta:0,camera:camera)
        try check(owner.pass(from:start,to:end,audioAvailable:false)==nil,"Missing audio emitted a passage sound")
        guard case .sound(let first)?=owner.pass(from:start,to:end,audioAvailable:true)else{fatalError("Crossing camera plane emitted no whizz")}
        try check(first.sample=="28_0" && first.right && first.rear && first.distance==0 && first.rate==0.96875,"Whizz sample/side/rate")
        try check(abs(first.gain-pow(10,-0.1))<1e-12,"Whizz logarithmic proximity gain")
        try check(owner.pass(from:start,to:end,audioAvailable:true)==nil,"Whizz cooldown missing")
        owner.update(delta:1,camera:camera)
        try check(owner.pass(from:start,to:end,audioAvailable:true)==nil,"Passage clock did not retain the scene's0.1s cap")
        owner.update(delta:0.1,camera:camera)
        guard case .sound?=owner.pass(from:start,to:end,audioAvailable:true)else{fatalError("Whizz0.2s equality changed")}
        let miss=NativeBulletPass(random:{0});miss.update(delta:0,camera:camera)
        try check(miss.pass(from:SIMD3(2,-1,0),to:SIMD3(2,3,0),audioAvailable:true)==nil,"Whizz2m strict proximity boundary")
        try check(miss.pass(from:SIMD3(0,-3,0),to:SIMD3(0,-1,0),audioAvailable:true)==nil,"Same-side subsegment invented a camera crossing")
        let bank=NativeBulletPass(random:{0});bank.update(delta:0,camera:camera)
        for _ in 0..<11 {
            guard case .sound(let sound)?=bank.pass(from:start,to:end,audioAvailable:true)else{fatalError("Eleven whizzes per bank not admitted")}
            try check(sound.sample=="28_0","Premature bank rotation")
            for _ in 0..<3{bank.update(delta:0.1,camera:camera)}
        }
        try check(bank.pass(from:start,to:end,audioAvailable:true)==nil,"Bank rotated before its half-second gate")
        for _ in 0..<3{bank.update(delta:0.1,camera:camera)}
        guard case .preload(let samples)?=bank.pass(from:start,to:end,audioAvailable:true)else{fatalError("Whizz bank did not silently preload/rotate")}
        try check(samples==["29_0","29_1","29_2"],"Whizz bank sample identities")
        guard case .sound(let next)?=bank.pass(from:start,to:end,audioAvailable:true)else{fatalError("Rotated bank did not admit its next sound")}
        try check(next.sample=="29_0","New bank not used")
        let right=NativeBulletPass.curve(right:true),left=NativeBulletPass.curve(right:false)
        try check(right.values.count==15 && right.seconds==0.35 && right.values[7]==1 && left.values[7] == -1,"Whizz Float32 curve/peak/duration")
        try check(right.values[0]==right.values[14] && zip(right.values,left.values).allSatisfy{$0.0 == -$0.1},"Whizz stereo side symmetry")
        try check(right.value(at:0.175)==1 && right.value(at:1)==Double(right.values[14]),"Audio curve interpolation or held endpoint")
    }
    static func main()throws {
        try origins();try immediateDelivery();try impacts();try tracers();try effects();try spatialAudio();try passage()
        print("PASS compact traffic shots: \(checks) checks; actual routing/origin/tracer/particle/audio planners with authored data. No renderer, audio playback, damage, live server or retail acceptance")
    }
}
