// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main enum TrafficSignalTests {
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
    static func base(id:UInt16=17,model:UInt16=420)->P.Base {
        .init(identity:.init(id:id,model:model,first:6,second:1),first:.init(link:0,lane:0),second:.init(link:1,lane:0),
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
    static func main(){do{try run()}catch{print("FAIL \(error)");exit(1)}}
    static func run()throws {
        typealias L=NativeAmbientTrafficPresentation
        for (hour,id,rain,lit) in [(0.0,0,0.0,true),(5.99,65535,0.0,true),(6.0,0,0.0,false),
            (6.5,1,0.0,true),(6.9,1,0.0,false),(12.0,0,0.0,false),(12.0,0,0.001,true),
            (20.0,0,0.0,false),(20.0001,0,0.0,true),(20.5,1,0.0,false),(20.9,1,0.0,true),
            (21.0,65535,0.0,true),(44.0,64,0.0,false),(45.0,65535,0.0,true),
            (12.0,65535,1.0,false)] {
            try check(L.mainLamps(hour:hour,id:UInt16(id),weatherShare:rain)==lit,"Clock/identity/weather lamp boundary")
        }
        let weatherEdge=7919.0/50000
        try check(!L.mainLamps(hour:12,id:1,weatherShare:weatherEdge),"Weather equality must not light lamps")
        try check(L.mainLamps(hour:12,id:1,weatherShare:weatherEdge.nextUp),"Weather strict upper boundary")
        try check(!L.mainLamps(hour:.nan,id:0,weatherShare:0) && !L.mainLamps(hour:12,id:0,weatherShare:.infinity),"Invalid lamp inputs admitted")
        for (speed,wanted,lit) in [(2.0,2.0,false),(2.0,1.8,false),(2.0,1.79,true),(0.0,0.0,true),
            (-2.0,-2.0,true),(-2.0,2.0,false),(0.2,0.2,false),(0.19,0.19,true),(0.0,0.2,false),
            (0.0,-0.2,true),(2.0,-2.0,true)] {
            try check(L.brakeLamps(speed:speed,wanted:wanted)==lit,"Signed speed/wanted lamp boundary")
        }
        try check(!L.brakeLamps(speed:.nan,wanted:0) && !L.brakeLamps(speed:0,wanted:.infinity),"Invalid braking inputs admitted")
        let graph=try graph()
        for fps in [30,60,120] {
            let scene=NativeAmbientTrafficScene();_=scene.configure(level:1,roads:graph.crc32,source:"signals")
            _=scene.install(graph);receive(scene)
            // Authoritative road wants forward travel, but the selected loose
            // state is decelerating. Its intent must own the lamp for this mode.
            scene.receive(.free(atServerMilliseconds:1_000_000,[.init(id:17,position:SIMD3(10,20,3),headingWire:0,speed:2,wanted:0,rate:1,turn:0)]),serverNow:1_000_000,received:100)
            for step in 0...fps {
                let values=frames(scene,100+Double(step)/Double(fps))
                try check(values.count==1,"Signal frame admission")
                try check(values[0].braking,"Loose selected intent was replaced by road or default intent")
                presented(scene,values[0])
            }
            // Existing quarter-second mode hysteresis still selects the old
            // loose sample initially. Its braking state must survive until
            // the road sample actually becomes the selected presentation.
            scene.receive(.base(atServerMilliseconds:1_001_100,[base()]),serverNow:1_001_100,received:101.1)
            let held=frames(scene,101.1).first!
            try check(held.braking,"Mode hysteresis selected braking from the newer unselected road record")
            presented(scene,held)
            let road=frames(scene,101.351).first!
            try check(!road.braking,"Road mode retained loose brake state")
            presented(scene,road)
            scene.receive(.free(atServerMilliseconds:1_001_500,[.init(id:17,position:SIMD3(10,20,3),headingWire:0,speed:-2,wanted:-2,rate:1,turn:0)]),serverNow:1_001_500,received:101.5)
            try check(frames(scene,101.5).first!.braking,"Reverse signed braking was converted to absolute speed")
            scene.reset();try check(frames(scene,101.6).isEmpty,"Signal state survived session reset")
        }
        let ordered=NativeAmbientTraffic();_=ordered.configure(level:1,roads:graph.crc32);_=ordered.install(graph)
        ordered.receive(.base(atServerMilliseconds:1_000_000,[base(id:40),base(id:2),base(id:80)]),serverNow:1_000_000,received:100)
        try check(ordered.snapshots(serverNow:1_000_000).map{ $0.identity.id }==[40,2,80],"Traffic actor insertion order was replaced by numeric ID order")
        ordered.receive(.base(atServerMilliseconds:1_000_010,[base(id:2,model:411)]),serverNow:1_000_010,received:100.01)
        try check(ordered.snapshots(serverNow:1_000_010).map{ $0.identity.id }==[40,2,80],"Model replacement changed actor insertion rank")
        ordered.receive(.gone([2]),serverNow:1_000_020,received:100.02)
        ordered.receive(.base(atServerMilliseconds:1_000_030,[base(id:2)]),serverNow:1_000_030,received:100.03)
        try check(ordered.snapshots(serverNow:1_000_030).map{ $0.identity.id }==[40,80,2],"Recreated actor retained an obsolete insertion rank")
        try check(ordered.snapshots(serverNow:1_006_501).map{ $0.identity.id }==[2],"Expired actor order retained stale entries")
        _=ordered.configure(level:0,roads:nil);_=ordered.configure(level:1,roads:graph.crc32)
        ordered.receive(.base(atServerMilliseconds:1_006_510,[base(id:2),base(id:40)]),serverNow:1_006_510,received:106.51)
        try check(ordered.snapshots(serverNow:1_006_510).map{ $0.identity.id }==[2,40],"Disabled traffic retained the previous actor order")
        print("PASS native traffic signals: \(checks) checks; authored graph/records, real selected motion, signed braking and 30/60/120Hz. No GPU, siren/beams or retail acceptance")
    }
}
