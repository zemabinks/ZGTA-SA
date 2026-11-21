// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main enum TrafficRoadTests {
    static var checks=0
    static func check(_ value:Bool,_ message:String)throws{checks+=1;if !value{throw NSError(domain:message,code:1)}}
    static func reject(_ message:String,_ block:()throws->Void)throws {var rejected=false;do{try block()}catch{rejected=true};try check(rejected,message)}
    static func bytes<T:FixedWidthInteger>(_ values:[T])->Data {
        var result=Data();for value in values{var little=value.littleEndian;withUnsafeBytes(of:&little){result.append(contentsOf:$0)}};return result
    }
    /// Deliberately invented two-node graph. No original game bytes/samples.
    static func fixture(a:UInt32=1,b:UInt32=1,width:UInt32=16,dx:Int8=100,dy:Int8=0)->Data {
        var result=bytes([UInt32(0x44524453),1,2,2,1,0,0,0])
        let parts:[Data]=[bytes([Int16(8),16,24,80,160,240]),bytes([UInt32(0),1,2]),
            bytes([UInt32(2<<12),1<<12]),Data([0,0]),bytes([UInt32(1),0]),bytes([UInt32(0),0]),
            bytes([Int16(40),80]),bytes([UInt32(1)]),Data([UInt8(bitPattern:dx),UInt8(bitPattern:dy)]),bytes([width|a<<8|b<<11])]
        for part in parts{result.append(part);result.append(Data(count:(4-part.count%4)%4))};return result
    }
    static func graph(_ data:Data)throws->NativeAmbientTrafficRoads{try .init(data:data,expectedCRC:NativeAmbientPedestrianPaths.crc32(data))}
    struct Reference:Decodable {
        struct Record:Decodable {
            struct Row:Decodable {
                struct Height:Decodable {let next:UInt16,progress:Double,z:Double}
                let id:UInt16,lane:UInt8,from:UInt16,to:UInt16,point:[Double],direction:[Double],against:Bool,speed:UInt8,heights:[Height]
            }
            let label:String,rows:[Row]
        }
        let records:[Record]
    }
    static func main()throws {
        let data=fixture(),roads=try graph(data)
        try check(roads.nodeCount==2 && roads.linkCount==2 && roads.naviCount==1,"Compact road counts")
        try check(try roads.point(0)==SIMD3(1,2,3) && roads.point(1)==SIMD3(10,20,30),"Original eighth-unit coordinates")
        try check(roads.linkFrom==[0,1] && roads.linkTo==[1,0],"Directed-link/node identity joined incorrectly")
        try check(try roads.links(from:0)==0..<1 && roads.links(from:1)==1..<2,"Node adjacency lost")
        try check(try roads.speedClass(0)==2 && roads.speedClass(1)==1,"Original speed-class bits")
        let forward=try roads.lanePoint(0,lane:0),reverse=try roads.lanePoint(1,lane:0)
        try check(simd_distance(forward.position,SIMD2(5,6.3))<1e-12 && forward.direction==SIMD2(1,0),"Forward lane geometry")
        try check(simd_distance(reverse.position,SIMD2(5,13.7))<1e-12 && reverse.direction==SIMD2(-1,0),"Reverse lane geometry")
        try check(abs(try roads.height(from:0,to:1,progress:0)-16.5)<1e-12,"Start half-edge height")
        try check(try roads.height(from:0,to:1,progress:0.5)==30,"Junction height")
        try check(abs(try roads.height(from:0,to:1,progress:1)-16.5)<1e-12,"End half-edge height")
        let directions:[(UInt32,UInt32)]=[(0,2),(2,0),(0,0),(1,1)]
        for (a,b) in directions {
            let value=try graph(fixture(a:a,b:b));try check(try value.against(0)==(a==0 && b>0),"Forward lane direction flags")
            try check(try value.against(1)==(b==0 && a>0),"Reverse lane direction flags")
        }
        let slice=(Data([99])+data).dropFirst();try check(try graph(slice).linkCount==2,"Data slice changed section offsets")
        for length in 0..<data.count {try reject("Truncated road graph accepted"){_=try graph(Data(data.prefix(length)))}}
        try reject("CRC mismatch accepted"){_=try NativeAmbientTrafficRoads(data:data,expectedCRC:"00000000")}
        for at in [4,8,12,16,44,48,52,68,76,88] {
            var corrupt=data;for i in 0..<4{corrupt[at+i]=255}
            try reject("Invalid road section/reference admitted at\(at)"){_=try graph(corrupt)}
        }
        try reject("Unknown road link accepted"){_=try roads.lanePoint(2,lane:0)}
        try reject("Nonfinite progress accepted"){_=try roads.height(from:0,to:1,progress:.nan)}
        try reject("Out-of-segment height accepted"){_=try roads.height(from:0,to:1,progress:1.1)}
        if CommandLine.arguments.count>=3 {
            let original=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
            let owned=try NativeAmbientTrafficRoads(data:original,expectedCRC:CommandLine.arguments[2])
            for link in 0..<owned.linkCount {
                let point=try owned.lanePoint(UInt16(link),lane:0)
                try check(point.position.x.isFinite && point.position.y.isFinite && point.direction.x.isFinite && point.direction.y.isFinite,"Original road link failed its bounded query")
            }
            if CommandLine.arguments.count==4 {
                let reference=try JSONDecoder().decode(Reference.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[3])))
                for record in reference.records {
                    let value:NativeAmbientTrafficRoads
                    if record.label=="owner-local-original"{value=owned}
                    else {
                        let parts=record.label.split(separator:"-");value=try graph(fixture(a:UInt32(parts[1])!,b:UInt32(parts[2])!,width:UInt32(parts[3])!,dx:Int8(parts[4])!,dy:Int8(parts[5])!))
                    }
                    for row in record.rows {
                        let point=try value.lanePoint(row.id,lane:row.lane)
                        try check(value.linkFrom[Int(row.id)]==row.from && value.linkTo[Int(row.id)]==row.to,"Archived graph directed identity")
                        try check(simd_distance(point.position,SIMD2(row.point[0],row.point[1]))<1e-8,"Archived lane position")
                        try check(simd_distance(point.direction,SIMD2(row.direction[0],row.direction[1]))<1e-12,"Archived lane tangent")
                        try check(try value.against(row.id)==row.against && value.speedClass(row.to)==row.speed,"Archived graph flags")
                        for height in row.heights{try check(abs(try value.height(from:row.id,to:height.next,progress:height.progress)-height.z)<1e-8,"Archived segment height")}
                    }
                }
            }
        }
        print("PASS compact native roads: \(checks) checks; optional original data/query comparison only, no traffic motion, rendering, AI or retail claim")
    }
}
