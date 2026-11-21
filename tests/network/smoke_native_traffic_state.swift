// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

@main enum TrafficStateTests {
    typealias P=NativeAmbientTrafficProtocol
    static var checks=0
    static func check(_ value:Bool,_ message:String)throws{checks+=1;if !value{throw NSError(domain:message,code:1)}}
    static func bytes<T:FixedWidthInteger>(_ values:[T])->Data {
        var result=Data();for value in values{var little=value.littleEndian;withUnsafeBytes(of:&little){result.append(contentsOf:$0)}};return result
    }
    /// Invented bounded geometry for record admission, not an original map.
    static func graph(links:Int=16)throws->NativeAmbientTrafficRoads {
        var result=bytes([UInt32(0x44524453),1,2,UInt32(links),1,0,0,0])
        let parts:[Data]=[bytes([Int16(0),0,0,80,0,0]),bytes([UInt32(0),UInt32(links),UInt32(links)]),
            bytes([UInt32(0),0]),Data([0,0]),bytes(Array(repeating:UInt32(1),count:links)),bytes(Array(repeating:UInt32(0),count:links)),
            bytes([Int16(40),0]),bytes([UInt32(1)]),Data([100,0]),bytes([UInt32(1<<8|1<<11)])]
        for part in parts{result.append(part);result.append(Data(count:(4-part.count%4)%4))}
        return try .init(data:result,expectedCRC:NativeAmbientPedestrianPaths.crc32(result))
    }
    static func base(model:UInt16=411,first:UInt8=7)->P.Base {
        .init(identity:.init(id:17,model:model,first:first,second:9),first:.init(link:1,lane:1),second:.init(link:2,lane:2),
            next:nil,nextLane:3,progress:0.5,speed:10,wanted:12,rate:1.5)
    }
    static func main()throws {
        let geometry=try graph(),owner=NativeAmbientTraffic()
        let row=base()
        owner.receive(.base(atServerMilliseconds:1_000_000,[row]),serverNow:1_000_000,received:100)
        try check(owner.actors.isEmpty,"Traffic born before geometry/level admission")
        try check(owner.configure(level:1,roads:geometry.crc32),"Traffic did not request missing matching geometry")
        try check(owner.install(geometry),"Traffic rejected matching geometry")
        owner.receive(.base(atServerMilliseconds:1_000_000,[row]),serverNow:1_000_000,received:100)
        let first=owner.actors[17]!
        try check(first.targetID=="t17" && first.occupantTargetID(seat:0)=="c17.0" && first.occupantTargetID(seat:3)==nil,"Traffic identity entered another namespace")
        owner.receive(.more([.init(id:17,side:-2,aim:1,health:384,flags:128)]),serverNow:1_000_001,received:100.001)
        owner.receive(.crew([.init(id:17,count:0,deadSeats:5)]),serverNow:1_000_001,received:100.001)
        owner.markPresented([17])
        owner.receive(.fast([.init(id:17,speed:1,wanted:2)]),serverNow:1_000_002,received:100.002)
        let history=owner.actors[17]!
        try check(history.before?.speed==10 && history.before?.side == -2 && history.beforeAt==1_000_000,"Traffic previous base sample lost")
        try check(history.generation==first.generation && history.crewCount==0 && history.deadSeats==5,"Ordinary metadata replaced traffic lifetime/crew")
        owner.receive(.ahead([.init(id:17,legs:[.init(link:3,lane:2),.init(link:65535,lane:255),.init(link:4,lane:1)])]),serverNow:1_000_003,received:100.003)
        try check(owner.actors[17]!.road.ahead==[.init(link:3,lane:2)],"Invalid ahead edge did not retain valid prefix")
        owner.receive(.base(atServerMilliseconds:999_500,[row]),serverNow:1_000_003,received:100.003)
        let refreshed=owner.actors[17]!
        try check(refreshed.baseAt==999_500 && refreshed.road.ahead.isEmpty,"Traffic base timestamp/route-window semantics changed")
        try check(refreshed.health==384 && refreshed.road.side == -2 && refreshed.road.flags==128 && refreshed.crewCount==0,"Traffic base wiped retained metadata")
        owner.receive(.plates([.init(id:17,text:"AUTHORED")]),serverNow:1_000_004,received:100.004)
        owner.receive(.gone([17]),serverNow:1_000_004,received:100.004)
        owner.receive(.base(atServerMilliseconds:1_000_005,[row]),serverNow:1_000_005,received:100.005)
        try check(owner.actors[17]!.generation != first.generation && owner.actors[17]!.crewCount==nil,"Traffic ID reuse inherited old crew/presentation lifetime")
        try check(owner.plates[17]=="AUTHORED","Traffic entity streamout incorrectly erased independent plate cache")
        let replacementGeneration=owner.actors[17]!.generation
        owner.receive(.base(atServerMilliseconds:1_000_006,[base(first:8)]),serverNow:1_000_006,received:100.006)
        try check(owner.actors[17]!.generation != replacementGeneration && owner.actors[17]!.health==1000,"Traffic palette identity replacement retained old body state")
        let free=P.Free(id:17,position:.zero,headingWire:0,speed:1,wanted:2,rate:1,turn:0)
        owner.receive(.free(atServerMilliseconds:1_006_505,[free]),serverNow:1_006_505,received:106.505)
        try check(owner.snapshots(serverNow:1_006_506).count==1,"Traffic expired at exact6500ms")
        try check(owner.snapshots(serverNow:1_006_507).isEmpty,"Free update incorrectly refreshed base lifetime")
        owner.receive(.free(atServerMilliseconds:1_006_508,[free]),serverNow:1_006_508,received:106.508)
        try check(owner.actors.isEmpty,"Free update invented an unknown traffic car")
        for id in UInt16(0)...UInt16(600){owner.receive(.plates([.init(id:id,text:"TEST\(id)")]),serverNow:1_006_509,received:106.509)}
        try check(owner.plates.count==600 && owner.plates[0]==nil && owner.plates[600]=="TEST600","Traffic plate LRU budget changed")
        _=owner.configure(level:0,roads:nil);try check(owner.graph != nil && owner.plates.count==600,"Disable discarded reusable same-connection resources")
        owner.reset();try check(owner.graph==nil && owner.roadsHash==nil && owner.plates.isEmpty,"Disconnect retained foreign traffic metadata")
        if CommandLine.arguments.count==2{try runOwnedReference(CommandLine.arguments[1])}
        print("PASS native traffic state: \(checks) checks; receiver/geometry admission only, no traffic rendering/AI/damage or retail claim")
    }
}
