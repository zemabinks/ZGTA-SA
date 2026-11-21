// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main enum TrafficTransitionTests {
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
    static func main(){do{try run()}catch{print("FAIL \(error)");exit(1)}}
    static func run()throws {
        let geometry=try graph(),scene=NativeAmbientTrafficScene()
        _=scene.configure(level:1,roads:geometry.crc32,source:"lane");_=scene.install(geometry)
        let row=P.Base(identity:.init(id:17,model:420,first:6,second:1),first:.init(link:0,lane:1),second:.init(link:1,lane:0),next:.init(link:0,lane:1),nextLane:1,progress:1,speed:2,wanted:2,rate:1)
        scene.receive(.base(atServerMilliseconds:1_000_000,[row]),serverNow:1_000_000,received:100)
        var predicted=scene.traffic.actors[17]!.road
        try NativeAmbientTrafficMotion.advance(&predicted,seconds:0.05,geometry:geometry)
        try check(predicted.flags==4 && predicted.side == -5.4,"Authored road did not exercise predicted lane state")
        try check(scene.traffic.actors[17]!.flags==0,"Prediction mutated authoritative metadata")
        let result=frames(scene,100.05)
        try check(result.count==1,"Lane-transition scene admission")
        try check(result[0].flags==0,"Presentation changed authoritative metadata flags")
        let expected=try NativeAmbientTrafficMotion.position(predicted,geometry:geometry).heading+atan(0.15)
        try check(abs(atan2(sin(result[0].body.heading-expected),cos(result[0].body.heading-expected)))<1e-8,"Lane body used authoritative flags instead of predicted lane flags")
        print("PASS native traffic lane bridge: \(checks) checks; authored geometry and actual prediction/scene/body code, no UI or retail acceptance")
    }
}
