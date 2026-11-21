// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

private final class Renderer {
    var source="assets-a",camera=SIMD3<Float>(10,20,3)
    var trafficOccupantCatalog:(source:String,value:NativeTrafficOccupants.Catalog)?
    var trafficGangs:[NativeTrafficOccupants.Gang]=[]
    var trafficOccupantSeats:[NativeTrafficOccupants.Seat]=[]
    var riderDefinitions:NativeRiderDefinitions?
    var presentedAmbientTraffic:[NativeAmbientTrafficScene.Frame]=[]
    func fixedCJSourceIdentity()->String{source}
    // ACTUAL_OCCUPANT_BRIDGE
}
@main private enum TrafficOccupantSceneTests {
    static var checks=0
    static func check(_ value:Bool,_ message:String)throws{checks+=1;if !value{throw NSError(domain:message,code:1)}}
    static func main(){do{try run();print("PASS traffic occupant scene bridge: \(checks) checks; literal renderer methods, actual traffic frames/seat definitions/policy, authored records; no asset loading, poses, rendering, combat or retail acceptance")}
        catch{print("FAIL \(error)");exit(1)}}
    static func catalog(_ skin:Int)throws->NativeTrafficOccupants.Catalog {
        try .init(data:JSONSerialization.data(withJSONObject:["schema":1,"fallback":[skin],"overrides":[String:Int](),"hiddenModels":[Int]()]))
    }
    static func definitions()->NativeRiderDefinitions {
        let seats=[-1,1,-1].map{side in NativeRiderDefinitions.Seat(at:[0,0,0],side:side,rear:false,opens:false,door:nil,via:nil,shift:nil,turn:nil)}
        return .init(models:["400":.init(model:"400",astride:false,clips:[:],seats:seats,origin:0,bike:nil,afloat:nil,group:nil)])
    }
    static func frame(id:UInt16=3,generation:UInt64=10,model:UInt16=400,flags:UInt8=128,count:UInt8?=nil,dead:UInt8=4,distance:Double=10)->NativeAmbientTrafficScene.Frame {
        .init(identity:.init(id:id,model:model,first:0,second:0),generation:generation,
            body:.init(position:SIMD3(10+distance,20,3),heading:0,pitch:0,steering:0,spin:0,wheelPhase:0),
            speed:0,health:1000,flags:flags,crewCount:count,deadSeats:dead,plate:nil)
    }
    static func run()throws {
        let renderer=Renderer();renderer.riderDefinitions=definitions();renderer.presentedAmbientTraffic=[frame()]
        renderer.updateTrafficOccupantSeats()
        try check(renderer.trafficOccupantSeats.isEmpty,"Missing occupant catalog invented seats")
        renderer.trafficOccupantCatalog=("assets-a",try catalog(5))
        renderer.receiveTrafficCrews(["t":"gangs","g":[["authored",0,[7,8,9],[400]]]])
        renderer.updateTrafficOccupantSeats()
        try check(renderer.trafficOccupantSeats.map(\.skin)==[7,8,9],"Wire crew rows did not reach deterministic selected skins")
        try check(renderer.trafficOccupantSeats.map(\.index)==[0,1,2] && renderer.trafficOccupantSeats.map(\.dead)==[false,false,true],"Seat/count/death fields lost through real frame bridge")
        try check(renderer.trafficOccupantSeats.allSatisfy{$0.id==3 && $0.generation==10 && $0.model==400},"Traffic lifetime/model identity lost")
        renderer.receiveTrafficCrews(["t":"unrelated","g":[]]);renderer.updateTrafficOccupantSeats()
        try check(renderer.trafficOccupantSeats.map(\.skin)==[7,8,9],"Unrelated command replaced crew selection")
        renderer.source="assets-b";renderer.updateTrafficOccupantSeats()
        try check(renderer.trafficOccupantSeats.isEmpty,"Old-source catalog selected new-source actors")
        renderer.trafficOccupantCatalog=("assets-b",try catalog(6));renderer.receiveTrafficCrews(["t":"gangs","g":"invalid"])
        renderer.updateTrafficOccupantSeats()
        try check(renderer.trafficGangs.isEmpty && renderer.trafficOccupantSeats.map(\.skin)==[6],"Malformed newer crew update retained prior selected crew")
        renderer.presentedAmbientTraffic=[frame(generation:11,flags:0,count:3,dead:2)];renderer.updateTrafficOccupantSeats()
        try check(renderer.trafficOccupantSeats.map(\.skin)==[6,6,6] && renderer.trafficOccupantSeats.allSatisfy{$0.generation==11},"Reused traffic identity retained old generation/appearance")
        try check(renderer.trafficOccupantSeats.map(\.dead)==[false,true,false],"Reused lifetime inherited old seat death flags")
        renderer.presentedAmbientTraffic=[frame(flags:32,count:3)];renderer.updateTrafficOccupantSeats()
        try check(renderer.trafficOccupantSeats.isEmpty,"Traffic visibility flags lost at renderer bridge")
        renderer.presentedAmbientTraffic=[frame(count:0)];renderer.updateTrafficOccupantSeats()
        try check(renderer.trafficOccupantSeats.map(\.index)==[0],"Explicit zero crew count lost driver")
        renderer.presentedAmbientTraffic=[frame(distance:45)];renderer.updateTrafficOccupantSeats()
        try check(renderer.trafficOccupantSeats.isEmpty,"Renderer used stale frame distance")
        renderer.presentedAmbientTraffic=[frame(model:401)];renderer.updateTrafficOccupantSeats()
        try check(renderer.trafficOccupantSeats.isEmpty,"Unknown vehicle seat metadata substituted a layout")
        renderer.presentedAmbientTraffic=[frame()];renderer.riderDefinitions=nil;renderer.updateTrafficOccupantSeats()
        try check(renderer.trafficOccupantSeats.isEmpty,"Missing rider definitions reused old seat layout")
        renderer.riderDefinitions=definitions();renderer.updateTrafficOccupantSeats()
        try check(!renderer.trafficOccupantSeats.isEmpty,"Available metadata failed to restore seat intent")
        renderer.presentedAmbientTraffic=[];renderer.updateTrafficOccupantSeats()
        try check(renderer.trafficOccupantSeats.isEmpty,"Streamout retained selected occupants")
        renderer.presentedAmbientTraffic=(0..<7).map{frame(id:UInt16($0),model:$0<6 ? 401:400,distance:Double($0))}
        renderer.updateTrafficOccupantSeats()
        try check(renderer.trafficOccupantSeats.isEmpty,"Missing rider metadata reopened a nearer built vehicle rank")
    }
}
