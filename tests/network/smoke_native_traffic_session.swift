// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main enum TrafficSessionTests {
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
    final class Task {var cancelled=0;var onCancel:(()->Void)?;func cancel(){cancelled+=1;onCancel?()}}
    final class Bodies {var clears=0;func removeAll(){clears+=1}}
    final class Renderer {
        let ambientTraffic=NativeAmbientTrafficScene()
        var ambientRoadToken=UUID(),ambientRoadTask:Task?,ambientRoadRetryAfter=99.0
        var presentedAmbientTraffic:[NativeAmbientTrafficScene.Frame]=[]
        var ambientTrafficBodies:Bodies?=Bodies()
        // Explicit occupant ownership spies; actual request/source lifetime
        // methods have their separate composed-loader gate.
        var trafficGangs=[1],trafficOccupantSeats=[1],trafficOccupantAnimations=["old":1]
        var trafficOccupantDrawn=["old":"old"]
        var occupantLoadCancellations=0
        func cancelTrafficOccupantLoad(){occupantLoadCancellations+=1}
        func configureAmbientTraffic(level:Double,roads:String?){_=ambientTraffic.configure(level:level,roads:roads,source:"same-assets")}
        // ACTUAL_RESET_HELPER
        func resetWorld(){
            // ACTUAL_RESET_DISPATCH
        }
    }
    static func main(){do{try run();print("PASS native traffic session: \(checks) checks; actual graph/store/scene and literal renderer reset helper/dispatch, task/body boundaries explicit; no UI or retail acceptance")}
        catch{print("FAIL \(error)");exit(1)}}
    static func run()throws {
        let graph=try graph(),renderer=Renderer(),scene=renderer.ambientTraffic
        renderer.configureAmbientTraffic(level:1,roads:graph.crc32);_=scene.install(graph);receive(scene)
        scene.receive(.plates([.init(id:17,text:"AUTHORED-OLD")]),serverNow:1_000_000,received:100)
        let before=scene.traffic.actors[17]!.generation
        renderer.configureAmbientTraffic(level:0,roads:nil)
        try check(scene.traffic.graph != nil && scene.traffic.plates[17]=="AUTHORED-OLD","Same-connection disable lost reusable graph/plate cache")
        renderer.configureAmbientTraffic(level:1,roads:nil);receive(scene)
        renderer.resetWorld()
        try check(scene.traffic.actors.isEmpty,"Old traffic actor survived reconnect")
        try check(scene.traffic.graph==nil && scene.traffic.plates.isEmpty && scene.traffic.roadsHash==nil,"New connection retained old traffic graph or plates")
        try check(scene.source==nil && renderer.presentedAmbientTraffic.isEmpty && renderer.ambientTrafficBodies!.clears==1,"Old scene/source/contact owner survived reset")
        try check(renderer.trafficGangs.isEmpty && renderer.trafficOccupantSeats.isEmpty && renderer.trafficOccupantAnimations.isEmpty && renderer.trafficOccupantDrawn.isEmpty && renderer.occupantLoadCancellations==1,"Old traffic occupant owner survived reset")
        renderer.configureAmbientTraffic(level:1,roads:graph.crc32)
        receive(scene);try check(scene.pendingCount==2,"Pending graph sample setup")
        let task=Task(),token=renderer.ambientRoadToken;renderer.ambientRoadTask=task
        var retiredBeforeCancellation=false
        task.onCancel={retiredBeforeCancellation=renderer.ambientRoadToken != token}
        renderer.resetWorld()
        try check(task.cancelled==1 && retiredBeforeCancellation && renderer.ambientRoadTask==nil,"Traffic request token not retired before cancellation")
        try check(scene.pendingCount==0 && renderer.ambientRoadRetryAfter==0,"Pending records or retry clock survived connection replacement")
        renderer.configureAmbientTraffic(level:1,roads:graph.crc32);_=scene.install(graph);receive(scene)
        let fresh=frames(scene,100).first!
        try check(fresh.generation != before && fresh.plate==nil && fresh.health==1000,"Reused ID inherited previous session state")
    }
}
