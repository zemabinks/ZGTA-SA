// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main enum TrafficProtocolTests {
    typealias P=NativeAmbientTrafficProtocol
    static var checks=0
    static func check(_ value:Bool,_ message:String)throws{checks+=1;if !value{throw NSError(domain:message,code:1)}}
    static func reject(_ message:String,_ block:()throws->Void)throws{var caught=false;do{try block()}catch{caught=true};try check(caught,message)}
    /// Semantic invented packing examples. No captured original packet data.
    static func word(_ value:Int64,_ width:Int)->Data {
        let bits=UInt64(bitPattern:value);return Data((0..<width).map{UInt8(truncatingIfNeeded:bits>>UInt64(8*(width-1-$0)))})
    }
    static func framed(_ tag:UInt8,_ payload:Data)->Data {
        var header=Data([tag]);let length=payload.count
        if length<128{header.append(UInt8(length))}else{header.append(UInt8(length&127)|128);header.append(UInt8(length>>7))}
        return header+payload
    }
    static func main()throws {
        let now=4_294_967_300.0
        let stamp=word(0xfffffffa,4)
        let base=stamp+word(42,2)+word(420,2)+Data([6,13])+word(17,2)+word(34,2)+word(65535,2)+word(0xabcd,2)+word(32768,2)+Data([6,8,16])
        guard case .base(let at,let rows)=try P.decode(tag:4,payload:base,nowServerMilliseconds:now)else{fatalError("Base record missing")}
        try check(at==4_294_967_290 && rows.count==1,"Traffic epoch wrap/row count")
        let first=rows[0]
        try check(first.identity == .init(id:42,model:420,first:6,second:13),"Traffic model/palette/identity")
        try check(first.first == .init(link:17,lane:13) && first.second == .init(link:34,lane:12) && first.next==nil && first.nextLane==11,"Lane nibble/sentinel packing")
        try check(first.progress==Double(32768)/65535 && first.speed==1.5 && first.wanted==2 && first.rate==1,"Traffic base units")
        let more=word(42,2)+word(-8,1)+word(4,1)+Data([250,129])
        try check(try P.decode(tag:9,payload:more,nowServerMilliseconds:now) == .more([.init(id:42,side:-0.5,aim:0.25,health:1000,flags:129)]),"Traffic supplemental fields")
        let free=stamp+word(42,2)+word(1250,4)+word(-2500,4)+word(25,2)+word(16384,2)+word(-32,2)+word(-64,2)+word(16,1)+word(-16,1)
        guard case .free(let freeAt,let loose)=try P.decode(tag:36,payload:free,nowServerMilliseconds:now)else{fatalError("Free record missing")}
        try check(freeAt==at && loose.count==1,"Free clock/row count")
        try check(loose[0].position==SIMD3(1.25,-2.5,3.125) && loose[0].headingWire == .pi/2,"Free coordinate/angle convention")
        try check(loose[0].speed == -0.5 && loose[0].wanted == -1 && loose[0].rate==1 && loose[0].turn == -0.25,"Signed reverse/turn units")
        let fast=word(42,2)+word(1000,2)+word(2000,2)
        try check(try P.decode(tag:37,payload:fast,nowServerMilliseconds:now) == .fast([.init(id:42,speed:15.625,wanted:31.25)]),"Fast speed scale")
        let crew=word(42,2)+Data([0,5])
        try check(try P.decode(tag:33,payload:crew,nowServerMilliseconds:now) == .crew([.init(id:42,count:0,deadSeats:5)]),"Crew count/seat mask changed meaning")
        let plate=word(42,2)+Data([4,65,233,161,0])
        guard case .plates(let plates)=try P.decode(tag:6,payload:plate,nowServerMilliseconds:now)else{fatalError("Plate missing")}
        try check(plates[0].text.unicodeScalars.map(\.value)==[65,233,161,0],"Plate bytes incorrectly decoded as UTF8")
        let ahead=word(42,2)+Data([3])+word(17,2)+Data([0])+word(65535,2)+Data([255])+word(34,2)+Data([2])
        try check(try P.decode(tag:34,payload:ahead,nowServerMilliseconds:now) == .ahead([.init(id:42,legs:[.init(link:17,lane:0),.init(link:65535,lane:255),.init(link:34,lane:2)])]),"Ahead graph validation leaked into binary parsing")
        let shot=word(42,2)+Data([24])+word(1250,4)+word(-2500,4)+word(3125,4)+Data([2,170,85])
        try check(try P.decode(tag:31,payload:shot,nowServerMilliseconds:now) == .shots([.init(id:42,weapon:24,target:SIMD3(1.25,-2.5,3.125),kind:2)]),"Traffic shot coordinate mapping")
        var otherTail=shot;otherTail[16]=0;otherTail[17]=255
        try check(try P.decode(tag:31,payload:otherTail,nowServerMilliseconds:now)==P.decode(tag:31,payload:shot,nowServerMilliseconds:now),"Unread shot tail assigned semantics")
        try check(try P.decode(tag:5,payload:word(42,2)+word(43,2),nowServerMilliseconds:now) == .gone([42,43]),"Traffic removal IDs")
        for (tag,payload,width) in [(UInt8(4),base,19),(36,free,20),(9,more,6),(31,shot,18),(33,crew,4),(37,fast,6)] {
            let expected=try P.decode(tag:tag,payload:payload,nowServerMilliseconds:now)
            for tail in 0..<width {
                try check(try P.decode(tag:tag,payload:payload+Data(count:tail),nowServerMilliseconds:now)==expected,"Fixed-width complete-prefix policy changed")
            }
        }
        let partialPlate=plate+word(43,2)+Data([5,65])
        try check(try P.decode(tag:6,payload:partialPlate,nowServerMilliseconds:now) == .plates(plates),"Partial plate discarded valid prefix")
        try check(try P.decode(tag:34,payload:ahead+word(43,2)+Data([2,0]),nowServerMilliseconds:now)==P.decode(tag:34,payload:ahead,nowServerMilliseconds:now),"Partial ahead discarded valid prefix")
        let message=framed(4,base)+framed(203,Data([0,1,2]))+framed(9,more)
        let decoded=try P.decodeMessage(message,nowServerMilliseconds:now)
        try check(decoded.count==2,"Traffic dispatcher did not skip complete unknown tag")
        try check(try P.decodeMessage(message+Data([6,128]),nowServerMilliseconds:now)==decoded,"Incomplete outer header discarded valid prefix")
        try check(try P.decodeMessage(message+Data([6,4,0]),nowServerMilliseconds:now)==decoded,"Incomplete outer body discarded valid prefix")
        let slice=(Data([99])+message).dropFirst();try check(try P.decodeMessage(slice,nowServerMilliseconds:now)==decoded,"Data slice broke traffic framing")
        let long=Data(repeating:0,count:130)
        try check(try P.decodeMessage(framed(203,long)+framed(9,more),nowServerMilliseconds:now)==[.more([.init(id:42,side:-0.5,aim:0.25,health:1000,flags:129)])],"Two-byte outer length changed")
        try reject("Traffic oversized payload accepted"){_=try P.decode(tag:4,payload:Data(count:32768),nowServerMilliseconds:now)}
        try reject("Traffic record budget ignored"){_=try P.decode(tag:5,payload:Data(count:8194),nowServerMilliseconds:now)}
        try reject("Traffic nonfinite clock accepted"){_=try P.decode(tag:4,payload:base,nowServerMilliseconds:.nan)}
        print("PASS typed traffic protocol: \(checks) authored checks; no live traffic, ownership, rendering, AI or retail claim")
    }
}
