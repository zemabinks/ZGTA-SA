// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main enum TrafficSceneTests {
    typealias P=NativeAmbientTrafficProtocol
    static var checks=0
    static func check(_ value:Bool,_ message:String)throws{checks+=1;if !value{throw NSError(domain:message,code:1)}}
    static func bytes<T:FixedWidthInteger>(_ values:[T])->Data {
        var result=Data();for value in values{var v=value.littleEndian;withUnsafeBytes(of:&v){result.append(contentsOf:$0)}};return result
    }
    // Independently authored graph bytes and traffic records. No original
    // game resources, private captures or measurements are embedded here.
    static func graph()throws->NativeAmbientTrafficRoads {
        var data=bytes([UInt32(0x44524453),1,2,2,1,0,0,0])
        let parts:[Data]=[bytes([Int16(0),0,0,80,0,0]),bytes([UInt32(0),2,2]),bytes([UInt32(0),0]),Data([0,0]),
            bytes([UInt32(1),1]),bytes([UInt32(0),0]),bytes([Int16(40),0]),bytes([UInt32(1)]),Data([100,0]),bytes([UInt32(1<<8|1<<11)])]
        for part in parts{data.append(part);data.append(Data(count:(4-part.count%4)%4))}
        return try .init(data:data,expectedCRC:NativeAmbientPedestrianPaths.crc32(data))
    }
    static func base(model:UInt16=420)->P.Base {
        .init(identity:.init(id:17,model:model,first:6,second:1),first:.init(link:0,lane:0),second:.init(link:1,lane:0),
            next:nil,nextLane:0,progress:0.5,speed:2,wanted:2,rate:1)
    }
    static func receive(_ scene:NativeAmbientTrafficScene,model:UInt16=420,at:Double=1_000_000,local:Double=100) {
        scene.receive(.base(atServerMilliseconds:at,[base(model:model)]),serverNow:at,received:local)
        scene.receive(.free(atServerMilliseconds:at,[.init(id:17,position:SIMD3(10,20,3),headingWire:0,speed:2,wanted:2,rate:1,turn:0)]),serverNow:at,received:local)
    }
    static func frames(_ scene:NativeAmbientTrafficScene,_ time:Double,promoted:Set<UInt16>=[],ready:Bool=true,active:Bool=true)->[NativeAmbientTrafficScene.Frame] {
        scene.frames(at:time,near:SIMD3(10,20,3),active:active,promoted:promoted,length:{_ in ready ? 4:nil},ray:{origin,maximum in
            let distance=origin.z-3;return distance>=0 && distance<=maximum ? distance:nil
        })
    }
    static func presented(_ scene:NativeAmbientTrafficScene,_ frame:NativeAmbientTrafficScene.Frame){scene.didPresent(frame.identity.id,generation:frame.generation)}
    static func main()throws {
        let graph=try graph(),scene=NativeAmbientTrafficScene()
        receive(scene);try check(scene.pendingCount==0,"Unconfigured traffic was queued")
        try check(scene.configure(level:1,roads:graph.crc32,source:"first"),"Missing graph did not request loading")
        receive(scene)
        scene.receive(.plates([.init(id:17,text:"AUTHORED")]),serverNow:1_000_000,received:100)
        scene.receive(.more([.init(id:17,side:0,aim:0,health:500,flags:0)]),serverNow:1_000_000,received:100)
        scene.receive(.crew([.init(id:17,count:0,deadSeats:1)]),serverNow:1_000_000,received:100)
        try check(scene.pendingCount==5 && scene.traffic.actors.isEmpty && frames(scene,100).isEmpty,"Async graph boundary invented an ungrounded car")
        try check(scene.install(graph) && scene.pendingCount==0,"Initial traffic did not replay after graph install")
        let first=frames(scene,100).first!
        try check(first.code=="420.6.1.0." && first.health==500 && first.plate=="AUTHORED" && first.crewCount==0 && first.deadSeats==1,"Buffered metadata or original appearance lost")
        try check(simd_distance(first.body.position,SIMD3(10,20,3))<1e-8,"GTA XYZ/origin ownership changed")
        try check(abs(first.body.heading-Double.pi/2)<1e-8,"Free wire +X did not face native +X")
        try check(frames(scene,100.1,ready:false).isEmpty,"Missing original model received substitute geometry")
        try check(scene.traffic.actors[17]!.fresh,"Unencoded candidates were marked presented")
        let still=frames(scene,100.2).first!;try check(still.body.wheelPhase==0,"Undrawn frame accumulated wheel history")
        presented(scene,still);try check(!scene.traffic.actors[17]!.fresh,"Actual draw did not consume fresh sample")
        let next=frames(scene,100.3).first!;try check(next.body.wheelPhase<0,"Drawn traffic wheel phase did not advance")
        scene.receive(.fast([.init(id:17,speed:3,wanted:3)]),serverNow:1_000_300,received:100.3)
        presented(scene,next);try check(scene.traffic.actors[17]!.fresh,"Stale staged draw consumed a newer authoritative revision")
        try check(frames(scene,100.3,promoted:[17]).isEmpty,"Registered promotion duplicated compact traffic")
        let restored=frames(scene,100.3).first!;try check(restored.body.wheelPhase==0,"Promotion retained stale compact wheel history")
        scene.receive(.gone([17]),serverNow:1_000_300,received:100.3);presented(scene,restored)
        receive(scene,model:411,at:1_000_400,local:100.4)
        let reused=frames(scene,100.4).first!
        try check(reused.generation != first.generation && reused.identity.model==411 && reused.body.wheelPhase==0,"Reused traffic ID inherited old presentation")
        try check(frames(scene,107).isEmpty && scene.traffic.actors.isEmpty,"Stale traffic remained visible")
        _=scene.configure(level:0,roads:nil,source:"first");receive(scene)
        try check(scene.pendingCount==0 && scene.traffic.graph != nil,"Disabled traffic lost reusable graph or retained updates")
        _=scene.configure(level:1,roads:graph.crc32,source:"second")
        try check(scene.traffic.graph==nil && scene.traffic.plates.isEmpty && scene.traffic.actors.isEmpty,"Resource source change retained foreign state")
        for _ in 0...NativeAmbientTrafficScene.maximumPendingEvents{scene.receive(.gone([17]),serverNow:1_000_000,received:100)}
        try check(scene.overflowCount==1 && scene.pendingCount==1,"Pending event budget did not retire whole prefix")
        let huge=[P.More](repeating:.init(id:17,side:0,aim:0,health:1000,flags:0),count:4096)
        for _ in 0..<5{scene.receive(.more(huge),serverNow:1_000_000,received:100)}
        try check(scene.overflowCount>=2 && scene.pendingCount<=4,"Pending record budget unbounded")
        _=scene.install(graph);try check(scene.traffic.actors.isEmpty,"Metadata after overflow invented traffic")
        scene.reset();try check(scene.source==nil && scene.traffic.graph==nil && scene.pendingCount==0,"Disconnect leaked scene state")
        var ends:[NativeAmbientTrafficScene.Frame]=[]
        for fps in [30,60,120] {
            let owner=NativeAmbientTrafficScene();_=owner.configure(level:1,roads:graph.crc32,source:"rate")
            _=owner.install(graph);receive(owner)
            for step in 0...fps {
                let values=frames(owner,100+Double(step)/Double(fps));try check(values.count==1,"Frame-rate traffic admission")
                presented(owner,values[0]);if step==fps{ends.append(values[0])}
            }
        }
        for end in ends {
            try check(simd_distance(end.body.position,SIMD3(12,20,3))<1e-8,"Render cadence accumulated authoritative prediction")
            try check(abs(end.body.wheelPhase+2/0.36)<1e-8,"Wheel distance depends on frame rate")
        }
        print("PASS native traffic scene: \(checks) checks; authored graph/records, connection and draw lifetime, ground boundary and 30/60/120Hz. No GPU/retail/AI acceptance")
    }
}
