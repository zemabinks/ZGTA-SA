// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
private struct Failure:Error,CustomStringConvertible {let description:String;init(_ text:String){description=text}}
private var checks=0
private func check(_ value:Bool,_ text:String)throws{guard value else{throw Failure(text)};checks+=1}
private func rejects(_ text:String,_ operation:()throws->Void)throws {
    var rejected=false;do{try operation()}catch{rejected=true};try check(rejected,text)
}
private func hex(_ value:String)->Data {
    let chars=Array(value);return Data(stride(from:0,to:chars.count,by:2).map{UInt8(String(chars[$0...$0+1]),radix:16)!})
}
private struct Reference:Decodable {
    struct State:Decodable {let free:Bool;let x:Double?,y:Double?,z:Double?,tx:Double?,ty:Double?,v:Double,want:Double
        let a:UInt16?,b:UInt16?,c:Int?,t:Double?,side:Double?,aim:Double?}
    struct Sample:Decodable {let seconds:Double,position:[Double],direction:[Double],speed:Double}
    struct Case:Decodable {let name:String,seed:UInt8,mood:UInt8,face:Double,state:State,samples:[Sample]}
    let cases:[Case]
}
@main private enum Main {
    static func main(){do{try run()}catch{fputs("FAIL \(error)\n",stderr);exit(1)}}
    static func run()throws {
        typealias P=NativeAmbientPedestrianProtocol
        let near=Double(0x112345678)+100
        // Literal protocol rows below are independently authored packing
        // examples with invented IDs/coordinates, not captured game packets.
        // Optional archived measurements are decoded only from a caller's
        // local file at runtime; no original reference samples are embedded.
        let free=hex("12345678010250072a000004e2fffff63c0019000800103040")
        guard case .free(let at,let actors)=try P.decode(tag:10,payload:free,nowServerMilliseconds:near)else{throw Failure("Typed free record missing")}
        try check(at==Double(0x112345678) && actors.count==1,"Nearest32-bit epoch reconstruction")
        let actor=actors[0]
        try check(actor.identity == .init(id:258,skin:7,flags:5,seed:42),"NPC identity/skin/flags/seed packing")
        try check(actor.feet==SIMD3(1.25,-2.5,3.125) && actor.goal==SIMD2(1.75,-1.5),"NPC GTA axes/feet/goal acquired a CPed offset")
        try check(actor.speed==1.5 && actor.desiredSpeed==2,"NPC speeds")
        let path=hex("12345678010250072a00110022ffff80003040f804")
        guard case .path(_,let paths)=try P.decode(tag:7,payload:path,nowServerMilliseconds:near)else{throw Failure("Typed path record missing")}
        try check(paths[0].from==17 && paths[0].to==34 && paths[0].next==nil,"Compact path IDs/sentinel")
        try check(paths[0].progress==Double(32768)/65535 && paths[0].side == -0.5 && paths[0].desiredSide==0.25,"Progress/signed lateral units")
        try check(paths[0].speed==1.5 && paths[0].desiredSpeed==2,"Path speed units")
        let more=hex("0102531618402380ffff05")
        guard case .state(let states)=try P.decode(tag:11,payload:more,nowServerMilliseconds:near)else{throw Failure("Supplemental state missing")}
        let state=states[0]
        try check(state.id==258 && state.mood==3 && state.burning && !state.phone && state.crouching && !state.cpr,"Supplemental flags")
        try check(state.weapon==22 && state.hitWeapon==24 && state.hitCounter==3 && state.hitPiece==3,"Hit counter/piece namespace")
        try check(state.hitFromWire == .pi/2 && state.faceWire == .pi && state.foe==65535 && state.thrown==1.25,"Wire angles/foe/thrown")
        try check(try P.recoverTime(0xfffffffa,near:4294967300)==4294967290,"Past wrap recovery")
        try check(try P.recoverTime(8,near:4294967300)==4294967304,"Future wrap recovery")
        try rejects("NaN epoch accepted"){_ = try P.recoverTime(0,near:.nan)}
        try rejects("Unbounded payload accepted"){_ = try P.decode(tag:10,payload:Data(count:32768),nowServerMilliseconds:near)}
        for length in 0..<free.count where length != 4 {
            try rejects("Partial free record accepted"){_ = try P.decode(tag:10,payload:Data(free.prefix(length)),nowServerMilliseconds:near)}
        }
        for length in 0..<path.count where length != 4 {
            try rejects("Partial path record accepted"){_ = try P.decode(tag:7,payload:Data(path.prefix(length)),nowServerMilliseconds:near)}
        }
        for length in 1..<more.count {
            try rejects("Partial state record accepted"){_ = try P.decode(tag:11,payload:Data(more.prefix(length)),nowServerMilliseconds:near)}
        }
        try rejects("Duplicate removal IDs accepted"){_ = try P.decode(tag:8,payload:hex("01020102"),nowServerMilliseconds:near)}
        try rejects("Duplicate supplemental IDs accepted"){_ = try P.decode(tag:11,payload:more+more,nowServerMilliseconds:near)}
        let message=hex("0a19")+free+hex("0b0b")+more+hex("080401020001")
        let decoded=try P.decodeMessage(message,nowServerMilliseconds:near)
        try check(decoded.count==3,"Separate framed NPC records missing")
        let sliced=(Data([99])+message).dropFirst()
        try check(try P.decodeMessage(sliced,nowServerMilliseconds:near)==decoded,"Data-slice indices leaked into frame offsets")
        try rejects("Partial outer record accepted"){_ = try P.decodeMessage(Data(message.dropLast()),nowServerMilliseconds:near)}
        try rejects("Partial two-byte length accepted"){_ = try P.decodeMessage(hex("0a80"),nowServerMilliseconds:near)}
        try check(try P.decode(tag:12,payload:Data(),nowServerMilliseconds:near)==nil,"Unimplemented shot channel claimed as complete")
        // Independently authored SDPD graph: two invented nodes at(1,2,3)
        // and(10,20,30), one link each way. Reproducible from the public
        // format fields; no original path node data is included here.
        let golden=hex("53445044010000000200000002000000000000000000000000000000000000000800100018005000a000f00000000000010000000200000000000000081000000100000003010000")
        typealias G=NativeAmbientPedestrianPaths
        try check(G.crc32(Data("123456789".utf8))=="cbf43926","Standard CRC32 golden")
        let graph=try G(data:golden,expectedCRC:"410b5926")
        try check(graph.nodeCount==2 && graph.linkCount==2,"Compact graph counts")
        try check(try graph.point(0)==SIMD3(1,2,3) && graph.point(1)==SIMD3(10,20,30),"Graph units or axes")
        try check(try graph.widthRaw(0)==8 && graph.widthRaw(1)==16,"Raw width changed")
        let links=try graph.neighbors(0)
        try check(links.count==1 && links[0].id==1 && links[0].crossesRoad && links[0].hasPedSignal,"Compact cross-area adjacency/kinds")
        try check(try graph.nearest(to:SIMD3(1.1,2,3),radius:1)?.id==0,"Native spatial query")
        try rejects("Huge coordinates reached integer conversion"){_ = try graph.nearest(to:SIMD3(1e300,0,0),radius:20)}
        try rejects("Native scan budget ignored"){_ = try graph.nearest(to:SIMD3(1,2,3),radius:100,maximumScannedNodes:1)}
        try rejects("Graph CRC mismatch accepted"){_ = try G(data:golden,expectedCRC:"00000000")}
        for length in [0,31,32,33,44,45,60,64,68,71] {
            let partial=Data(golden.prefix(length))
            try rejects("Partial native graph accepted"){_ = try G(data:partial,expectedCRC:G.crc32(partial))}
        }
        var invalid=golden;invalid[64]=3
        try rejects("Native unresolved graph node accepted"){_ = try G(data:invalid,expectedCRC:G.crc32(invalid))}
        try check(try graph.place(0,seed:119)==SIMD3(1,2,3),"Neutral seed altered raw coordinates")
        let offset=try graph.place(0,seed:0)
        try check(abs(offset.x-(1-8*7*0.00775))<1e-12 && abs(offset.y-(2-8*7*0.00775))<1e-12,"Original width/seed placement")
        let walk=P.Free(identity:.init(id:1,skin:7,flags:0,seed:119),feet:SIMD3(0,0,3.125),goal:SIMD2(10,0),speed:0,desiredSpeed:2)
        func owner()->NativeAmbientPedestrians {
            let value=NativeAmbientPedestrians();value.configure(level:1,paths:graph.crc32);_ = value.install(graph)
            value.receive(.free(atServerMilliseconds:100000,[walk]),serverNow:100000,received:100);return value
        }
        // A remove and re-admission can both arrive between rendered frames.
        // Ordinary updates keep the lifetime; removal/replacement never does.
        let lifetime=owner(),firstLife=lifetime.frames(at:100,near:.zero)[0].generation
        try check(firstLife != 0,"NPC missing local admission lifetime")
        lifetime.receive(.free(atServerMilliseconds:100001,[walk]),serverNow:100001,received:100.001)
        try check(lifetime.frames(at:100.001,near:.zero)[0].generation==firstLife,"Ordinary update replaced lifetime")
        lifetime.receive(.gone([1]),serverNow:100002,received:100.002)
        lifetime.receive(.free(atServerMilliseconds:100003,[walk]),serverNow:100003,received:100.003)
        let secondLife=lifetime.frames(at:100.003,near:.zero)[0].generation
        try check(secondLife != firstLife,"Same ID/skin/seed inherited removed NPC lifetime")
        lifetime.receive(.free(atServerMilliseconds:100002,[walk]),serverNow:100003,received:100.003)
        try check(lifetime.frames(at:100.003,near:.zero)[0].generation==secondLife,"Stale packet changed lifetime")
        let replaced=P.Free(identity:.init(id:1,skin:14,flags:0,seed:119),feet:walk.feet,goal:walk.goal,speed:0,desiredSpeed:2)
        lifetime.receive(.free(atServerMilliseconds:100004,[replaced]),serverNow:100004,received:100.004)
        try check(lifetime.frames(at:100.004,near:.zero)[0].generation != secondLife,"Skin replacement retained pose lifetime")
        lifetime.reset();lifetime.configure(level:1,paths:graph.crc32);_ = lifetime.install(graph)
        lifetime.receive(.free(atServerMilliseconds:100000,[walk]),serverNow:100000,received:100)
        try check(lifetime.frames(at:100,near:.zero)[0].generation>secondLife,"Connection reset reused local lifetime")
        let waitingRoute=NativeAmbientPedestrians();waitingRoute.configure(level:1,paths:graph.crc32);_=waitingRoute.install(graph)
        let route=P.Path(identity:walk.identity,from:0,to:1,next:0,progress:0.25,speed:1,desiredSpeed:1,side:0,desiredSide:0)
        waitingRoute.receive(.path(atServerMilliseconds:100000,[route]),serverNow:100000,received:100)
        try check(waitingRoute.frames(at:100,near:.zero)[0].waitingLinkKind==1,"Waiting context lost actual next-edge kind")
        let consumed=P.Path(identity:walk.identity,from:0,to:1,next:0,progress:1,speed:1,desiredSpeed:1,side:0,desiredSide:0)
        waitingRoute.receive(.path(atServerMilliseconds:100001,[consumed]),serverNow:100001,received:100.001)
        try check(waitingRoute.frames(at:100.001,near:.zero)[0].waitingLinkKind==nil,"Consumed next edge retained old waiting kind")
        try check(owner().frames(at:100,near:.zero)[0].waitingLinkKind==nil,"Free motion invented a next edge")
        var schedules:[Int:[SIMD3<Double>]]=[:]
        for hz in [20,30,60,120] {
            let value=owner();var points:[SIMD3<Double>]=[]
            for frame in 0...hz*6 {
                let now=100+Double(frame)/Double(hz),sample=value.frames(at:now,near:.zero)
                try check(sample.count==1 && sample[0].targetID=="p1","NPC identity entered another namespace")
                try check(sample[0].position.z==3.125,"NPC feet acquired CPed metre or wrong axes")
                if frame%hz==0{points.append(sample[0].position)}
            }
            schedules[hz]=points
        }
        for points in schedules.values{for(index,point)in points.enumerated(){try check(simd_distance(point,schedules[60]![index])<1e-10,"NPC prediction depends on display cadence")}}
        let value=owner()
        // Real authoritative motion/state records reproduce a fallen body
        // turning toward a later face update in the pre-correction store.
        // No animation or renderer state is substituted in this witness.
        for hz in [20,30,60,120] {
            let turning=owner()
            let initial=turning.frames(at:100,near:.zero)[0].heading
            let down=P.Free(identity:.init(id:1,skin:7,flags:1,seed:119),feet:walk.feet,goal:SIMD2(walk.feet.x,walk.feet.y),speed:0,desiredSpeed:0)
            turning.receive(.free(atServerMilliseconds:100001,[down]),serverNow:100001,received:100.001)
            turning.receive(.state([.init(id:1,mood:9,burning:false,phone:false,crouching:false,cpr:false,weapon:0,hitWeapon:0,
                hitCounter:0,hitPiece:0,hitFromWire:0,faceWire:.pi/2,foe:0,thrown:0)]),serverNow:100000,received:100)
            for tick in 1...hz {
                let frame=turning.frames(at:100+Double(tick)/Double(hz),near:.zero,turningRate:{_ in 1})[0]
                try check(frame.down,"Authored down record was not admitted")
                try check(abs(frame.heading-initial)<1e-12,"Fallen NPC rotated with live face task")
            }
            let upright=P.Free(identity:walk.identity,feet:walk.feet,goal:SIMD2(0,10),speed:1,desiredSpeed:1)
            turning.receive(.free(atServerMilliseconds:101001,[upright]),serverNow:101001,received:101.001)
            let resumed=turning.frames(at:101+1/Double(hz),near:.zero,turningRate:{_ in 1})[0]
            try check(abs(resumed.heading-(initial-1/Double(hz)))<1e-10,"Recovery inherited a whole fallen second of turning")
        }
        for rate in [1.0,3.0,Double.nan,Double.infinity,-1] {
            let turning=owner();_=turning.frames(at:100,near:.zero)
            let turned=P.Free(identity:walk.identity,feet:walk.feet,goal:SIMD2(0,10),speed:1,desiredSpeed:1)
            turning.receive(.free(atServerMilliseconds:100001,[turned]),serverNow:100001,received:100.001)
            let frame=turning.frames(at:100.1,near:.zero,turningRate:{_ in rate})[0]
            let expected=rate.isFinite && rate>0 ? rate:6.5
            try check(abs(frame.heading-(Double.pi/2-0.1*expected))<1e-10,"Model turning rate or finite fallback lost")
        }
        try check(abs(value.frames(at:100.25,near:.zero)[0].position.x-0.125)<1e-10,"NPC acceleration trapezoid")
        try check(abs(value.frames(at:100.5,near:.zero)[0].position.x-0.5)<1e-10,"NPC acceleration boundary")
        try check(abs(value.frames(at:102,near:.zero)[0].position.x-3.5)<1e-10,"NPC constant-speed tail")
        try check(value.frames(at:106,near:.zero)[0].position.x==10,"NPC passed its authoritative goal")
        try check(value.frames(at:106,near:.zero)[0].velocity == .zero,"NPC kept walking after goal")
        let corrected=P.Free(identity:walk.identity,feet:SIMD3(3.7,0,3.125),goal:walk.goal,speed:2,desiredSpeed:2)
        let correction=owner(),before=correction.frames(at:102,near:.zero)[0].position
        correction.receive(.free(atServerMilliseconds:102000,[corrected]),serverNow:102000,received:102)
        try check(simd_distance(correction.frames(at:102,near:.zero)[0].position,before)<1e-10,"Fresh NPC correction snapped instead of preserving continuity")
        correction.receive(.free(atServerMilliseconds:101000,[walk]),serverNow:102000,received:102)
        try check(simd_distance(correction.frames(at:102,near:.zero)[0].position,before)<1e-10,"Stale server sample replaced NPC")
        let reused=P.Free(identity:.init(id:1,skin:2,flags:0,seed:1),feet:SIMD3(20,0,3),goal:SIMD2(30,0),speed:1,desiredSpeed:1)
        correction.receive(.free(atServerMilliseconds:102001,[reused]),serverNow:102001,received:102.001)
        try check(correction.frames(at:102.001,near:.zero)[0].position.x==20,"Skin/seed replacement inherited old correction")
        correction.receive(.gone([1]),serverNow:102002,received:102.002)
        try check(correction.count==0 && correction.frames(at:102.002,near:.zero).isEmpty,"NPC streamout left a ghost")
        let pending=NativeAmbientPedestrians();pending.configure(level:1,paths:graph.crc32)
        pending.receive(.free(atServerMilliseconds:100000,[walk]),serverNow:100000,received:100)
        try check(pending.count==0,"Unverified graph admitted NPC")
        _ = pending.install(graph);try check(pending.count==1,"Verified graph lost bounded pending state")
        pending.configure(level:1,paths:"00000000");try check(pending.count==0 && pending.graph==nil,"Path change retained foreign actors")
        pending.configure(level:0,paths:nil);try check(pending.pathsHash==nil,"Disabled population retained graph namespace")
        let stale=owner();try check(stale.frames(at:109.001,near:.zero).isEmpty && stale.count==0,"Nine-second actor expiry")
        let suspended=owner();try check(suspended.frames(at:100.5,near:.zero,active:false).isEmpty,"Inactive display sampled actor")
        try check(abs(suspended.frames(at:102,near:.zero)[0].position.x-3.5)<1e-10,"Resume replayed stale display delta")
        let pathMotion=P.Path(identity:walk.identity,from:0,to:1,next:nil,progress:0.25,speed:0,desiredSpeed:0,side:0,desiredSide:0)
        let pathOwner=owner();pathOwner.receive(.gone([1]),serverNow:100000,received:100)
        pathOwner.receive(.path(atServerMilliseconds:100000,[pathMotion]),serverNow:100000,received:100)
        try check(simd_distance(pathOwner.frames(at:100,near:.zero)[0].position,SIMD3(3.25,6.5,9.75))<1e-10,"Native graph path progress/height")
        try check(abs(pathOwner.frames(at:100,near:.zero)[0].heading-atan2(9.0,18.0))<1e-10,"Missing supplemental state invented a noncalm facing task")
        if CommandLine.arguments.count>=3 {
            let bytes=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
            let owned=try G(data:bytes,expectedCRC:CommandLine.arguments[2])
            var edges=0
            for id in 0..<owned.nodeCount{edges += try owned.neighbors(UInt16(id)).count}
            try check(edges==owned.linkCount,"Original compact graph omitted edges")
            try check(try owned.nearest(to:SIMD3(1480,-1738,13),radius:100) != nil,"Original exterior query missing")
            print("PASS private native graph: \(owned.nodeCount) nodes; \(edges) edges; data/query scope only")
            if CommandLine.arguments.count==4 {
                let reference=try JSONDecoder().decode(Reference.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[3])))
                var samples=0
                for row in reference.cases {for expected in row.samples {
                    let value=NativeAmbientPedestrians();value.configure(level:1,paths:owned.crc32);_ = value.install(owned)
                    let state=row.state,identity=P.Identity(id:1,skin:7,flags:0,seed:row.seed)
                    let event:P.Event
                    if state.free {
                        event = .free(atServerMilliseconds:100000,[.init(identity:identity,feet:SIMD3(state.x!,state.y!,state.z!),goal:SIMD2(state.tx!,state.ty!),speed:state.v,desiredSpeed:state.want)])
                    }else{
                        event = .path(atServerMilliseconds:100000,[.init(identity:identity,from:state.a!,to:state.b!,next:state.c!<0 ? nil:UInt16(state.c!),progress:state.t!,speed:state.v,desiredSpeed:state.want,side:state.side!,desiredSide:state.aim!)])
                    }
                    value.receive(event,serverNow:100000,received:100)
                    value.receive(.state([.init(id:1,mood:row.mood,burning:false,phone:false,crouching:false,cpr:false,weapon:0,hitWeapon:0,hitCounter:0,hitPiece:0,hitFromWire:0,faceWire:row.face,foe:65535,thrown:0)]),serverNow:100000,received:100)
                    guard let frame=value.frames(at:100+expected.seconds,near:SIMD3(expected.position[0],expected.position[1],expected.position[2])).first else{throw Failure("Reference actor missing "+row.name)}
                    let target=SIMD3(expected.position[0],expected.position[1],expected.position[2])
                    try check(simd_distance(frame.position,target)<1e-8,"Archived NPC position mismatch "+row.name)
                    try check(abs(sin(frame.heading)-expected.direction[0])<1e-8 && abs(cos(frame.heading)-expected.direction[1])<1e-8,"Archived NPC direction/native heading mismatch "+row.name)
                    try check(abs(hypot(frame.velocity.x,frame.velocity.y)-expected.speed)<1e-8,"Archived NPC speed mismatch "+row.name)
                    samples+=1
                }}
                print("PASS actual archived NPC kernel comparison: \(reference.cases.count) authored cases; \(samples) measured samples")
            }
        }
        print("PASS native NPC channel/graph: \(checks) authored checks; no actor scene, AI, server, damage, GPU or retail acceptance")
    }
}
