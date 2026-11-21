// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

// Optional owner-local observations. Only receiver fields are compared;
// mocked scene/model/effect callbacks in that capture are not rendering proof.
extension TrafficStateTests {
    static func runOwnedReference(_ path:String)throws {
        let root=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:path)))as! [String:Any]
        func number(_ value:Any?)->Double?{(value as?NSNumber)?.doubleValue}
        func numeric(_ actual:Double?,_ expected:Any?,_ label:String)throws {
            if let value=number(expected){try check(actual != nil && abs(actual!-value)<1e-8,label)}
            else{try check(actual==nil,label+" optional")}
        }
        func road(_ actual:NativeAmbientTraffic.RoadState?,_ raw:Any?,_ label:String)throws {
            guard let expected=raw as? [String:Any]else{try check(actual==nil,label+" absent");return}
            guard let actual else{throw NSError(domain:label+" missing",code:1)}
            let fields:[String:Double]=["a":Double(actual.first.link),"b":Double(actual.second.link),"c":actual.next.map{Double($0.link)} ?? -1,
                "laneA":Double(actual.first.lane),"laneB":Double(actual.second.lane),"laneC":Double(actual.nextLane),
                "t":actual.progress,"v":actual.speed,"want":actual.wanted,"rate":actual.rate,"side":actual.side,"aim":actual.aim,"flags":Double(actual.flags),"taken":Double(actual.taken)]
            for (key,value) in fields{try numeric(value,expected[key],label+" "+key)}
            let ahead=actual.ahead.flatMap{[Int($0.link),Int($0.lane)]}
            try check(ahead==(expected["ahead"]as! [NSNumber]).map(\.intValue),label+" route window")
        }
        func loose(_ actual:P.Free?,_ raw:Any?,_ label:String)throws {
            guard let expected=raw as? [String:Any]else{try check(actual==nil,label+" absent");return}
            guard let actual else{throw NSError(domain:label+" missing",code:1)}
            for (key,value) in ["x":actual.position.x,"y":actual.position.y,"z":actual.position.z,"heading":actual.headingWire,
                "v":actual.speed,"want":actual.wanted,"rate":actual.rate,"turn":actual.turn]{try numeric(value,expected[key],label+" "+key)}
        }
        func hex(_ value:String)->Data {
            let chars=Array(value);return Data(stride(from:0,to:chars.count,by:2).map{UInt8(String(chars[$0...$0+1]),radix:16)!})
        }
        var cases=0,steps=0,excluded:[String]=[]
        for test in root["cases"]as! [[String:Any]] {
            let name=test["name"]as! String,initial=test["initial"]as! [String:Any]
            if name=="callback_exception_continues" || name=="encoder_over_limit_preserved"{excluded.append(name);continue}
            let owner=NativeAmbientTraffic();var level=number(initial["level"]) ?? 1
            let geometry=try graph(links:Int(number(initial["roadLinks"]) ?? 16))
            _=owner.configure(level:level,roads:geometry.crc32)
            if !(initial["roadLinks"]is NSNull){_=owner.install(geometry)}
            for step in test["steps"]as! [[String:Any]] {
                let kind=step["kind"]as! String,now=number(step["siteNow"])!,time=(number(step["performanceMS"]) ?? 0)/1000
                let input=step["authoredInput"]as! [String:Any]
                switch kind {
                case "frame":
                    var packet=hex(step["encodedFrameHex"]as! String)
                    if name=="DataView_nonzero_offset"{packet=(Data([99])+packet).dropFirst()}
                    for event in try P.decodeMessage(packet,nowServerMilliseconds:now){owner.receive(event,serverNow:now,received:time)}
                case "consumeFresh":owner.markPresented([UInt16(number(input["id"])!)])
                case "stale":_=owner.snapshots(serverNow:now)
                case "context":
                    if let value=number(input["level"]){level=value;_=owner.configure(level:level,roads:nil)}
                    if let count=number(input["roadLinks"]){let geometry=try graph(links:Int(count));_=owner.configure(level:level,roads:geometry.crc32);_=owner.install(geometry)}
                case "display":break // Scene/seat/muzzle callbacks are outside this receiver gate.
                default:throw NSError(domain:"Unsupported reference action "+kind,code:1)
                }
                let expected=step["expectedActors"]as! [[String:Any]]
                try check(owner.actors.count==expected.count,name+" actor count")
                for row in expected {
                    let id=UInt16(number(row["id"])!)
                    guard let actor=owner.actors[id]else{throw NSError(domain:name+" missing actor",code:1)}
                    for (key,value) in ["model":Double(actor.identity.model),"first":Double(actor.identity.first),"second":Double(actor.identity.second),
                        "toldAt":actor.baseAt,"health":actor.health,"flags":Double(actor.flags)]{try numeric(value,row[key],name+" "+key)}
                    try numeric(actor.beforeAt,row["beforeAt"],name+" beforeAt")
                    try numeric(actor.freeAt,row["looseAt"],name+" looseAt")
                    try numeric(actor.freeBeforeAt,row["looseBeforeAt"],name+" looseBeforeAt")
                    try numeric(actor.crewCount.map{Double($0)},row["aboard"],name+" crew count")
                    // A missing deadSeats and0 both mean the unchanged empty mask.
                    try check(actor.deadSeats==UInt8(number(row["deadSeats"]) ?? 0),name+" dead seat mask")
                    try check(actor.fresh==row["fresh"]as! Bool,name+" fresh sample")
                    try road(actor.road,row["told"],name+" road");try road(actor.before,row["before"],name+" history")
                    try loose(actor.free,row["loose"],name+" free");try loose(actor.freeBefore,row["looseBefore"],name+" previous free")
                }
                let plates=step["expectedPlates"]as! [[String:Any]]
                try check(owner.plates.count==plates.count,name+" plate count")
                for plate in plates{try check(owner.plates[UInt16(number(plate["id"])!)]==plate["text"]as? String,name+" plate text")}
                steps+=1
            };cases+=1
        }
        print("PASS archived traffic receiver fields: \(cases) cases, \(steps) steps; excluded \(excluded). Scene, mesh, effects, route prediction and real server/retail behavior remain outside scope")
    }
}
