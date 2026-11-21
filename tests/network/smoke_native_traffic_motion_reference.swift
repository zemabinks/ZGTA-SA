// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

// Optional private observations from the owner's archived client. This adapter
// contains no original implementation, map bytes or measured coordinate rows.
extension TrafficMotionTests {
    static func number(_ row:[String:Any],_ key:String)->Double{(row[key]as! NSNumber).doubleValue}
    static func loose(_ row:[String:Any])->P.Free {
        .init(id:17,position:SIMD3(number(row,"x"),number(row,"y"),number(row,"z")),headingWire:number(row,"heading"),
              speed:number(row,"v"),wanted:number(row,"want"),rate:number(row,"rate"),turn:number(row,"turn"))
    }
    static func road(_ row:[String:Any])->M.Road {
        let first=P.Leg(link:UInt16(number(row,"a")),lane:UInt8(number(row,"laneA")))
        let second=P.Leg(link:UInt16(number(row,"b")),lane:UInt8(number(row,"laneB")))
        let next=number(row,"c")<0 ? nil:P.Leg(link:UInt16(number(row,"c")),lane:UInt8(number(row,"laneC")))
        var result=M.Road(.init(identity:.init(id:17,model:411,first:1,second:2),first:first,second:second,next:next,
            nextLane:UInt8(number(row,"laneC")),progress:number(row,"t"),speed:number(row,"v"),wanted:number(row,"want"),rate:number(row,"rate")))
        result.side=number(row,"side");result.aim=number(row,"aim");result.flags=UInt8(number(row,"flags"))
        let ahead=(row["ahead"]as! [NSNumber]).map(\.intValue)
        result.ahead=stride(from:0,to:ahead.count,by:2).map{.init(link:UInt16(ahead[$0]),lane:UInt8(ahead[$0+1]))}
        result.taken=Int(number(row,"taken"));return result
    }
    static func compare(_ value:M.Free,_ expected:[String:Any],_ label:String)throws {
        for (key,actual) in ["x":value.position.x,"y":value.position.y,"z":value.position.z,"heading":value.heading,
            "v":value.speed,"want":value.wanted,"rate":value.rate,"turn":value.turn]{try near(actual,number(expected,key),label+" "+key)}
    }
    static func compare(_ value:M.Road,_ expected:[String:Any],_ label:String)throws {
        let fields:[String:Double]=["a":Double(value.first.link),"b":Double(value.second.link),"c":value.next.map{Double($0.link)} ?? -1,
            "laneA":Double(value.first.lane),"laneB":Double(value.second.lane),"laneC":Double(value.nextLane),"t":value.progress,
            "v":value.speed,"want":value.wanted,"rate":value.rate,"side":value.side,"aim":value.aim,"flags":Double(value.flags),"taken":Double(value.taken)]
        for (key,actual) in fields{try near(actual,number(expected,key),label+" "+key)}
        try check(value.ahead.flatMap{[Int($0.link),Int($0.lane)]}==(expected["ahead"]as! [NSNumber]).map(\.intValue),label+" route window")
    }
    static func compare(_ pose:M.Pose,_ expected:[Double],_ label:String)throws {
        for (index,actual) in [pose.position.x,pose.position.y,pose.direction.x,pose.direction.y].enumerated(){try near(actual,expected[index],label+" sample\(index)")}
    }
    static func ownedReference(_ path:String,graphPath:String,crc:String)throws {
        let root=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:path)))as! [String:Any]
        let groups=root["groups"]as! [String:[[String:Any]]]
        let original=try NativeAmbientTrafficRoads(data:Data(contentsOf:URL(fileURLWithPath:graphPath)),expectedCRC:crc)
        var cases=0,rows=0
        for test in groups["sideRateFixtures"]! {
            try near(M.sideRate(UInt8(number(test,"flags"))),number(test,"expectedRate"),test["name"]as! String);cases+=1;rows+=1
        }
        for test in groups["freeFixtures"]! {
            let name=test["name"]as! String;var state=M.Free(loose(test["initial"]as! [String:Any]))
            for step in test["steps"]as! [[String:Any]] {
                try M.advance(&state,seconds:number(step,"delta"));try compare(state,step["expectedState"]as! [String:Any],name);rows+=1
            };cases+=1
        }
        for test in groups["curveFixtures"]! {
            let name=test["name"]as! String,g=test["geometry"]as! [String:Any]
            let a=g["a"]as! [Double],b=g["b"]as! [Double],p=SIMD2(a[0],a[1]),u=SIMD2(a[2],a[3]),q=SIMD2(b[0],b[1]),v=SIMD2(b[2],b[3])
            try near(M.intersection(p,u,q,v),number(g,"r"),name+" first intersection")
            try near(M.intersection(q,-v,p,u),number(g,"n"),name+" second intersection")
            try near(M.curveFactor(p,u,q,v),number(g,"fallback"),name+" curve factor")
            try near(M.length(p,u,q,v),number(g,"length"),name+" travel length")
            for step in test["samples"]as! [[String:Any]] {
                let value=M.curve(p,u,q,v,progress:number(step,"progress")),expected=step["expectedXY"]as! [Double]
                try near(value.x,expected[0],name+" X");try near(value.y,expected[1],name+" Y");rows+=1
            };cases+=1
        }
        for test in groups["roadFixtures"]! {
            let name=test["name"]as! String,isOriginal=test["graphKind"]as? String=="ownerLocalOriginal"
            let speeds=(test["speedClasses"]as! [String:NSNumber]).mapValues(\.intValue)
            let graph=Graph(original:isOriginal ? original:nil,kind:test["syntheticGraph"]as? String ?? "line",speeds:speeds)
            let initial=road(test["initial"]as! [String:Any]);var state=initial
            for step in test["steps"]as! [[String:Any]] {
                if test["resetBeforeEach"]as! Bool{state=initial}
                try M.advance(&state,seconds:number(step,"delta"),geometry:graph)
                try compare(state,step["expectedState"]as! [String:Any],name)
                let pose=try M.position(state,geometry:graph),expected=step["expectedPose"]as! [String:Any]
                try compare(pose,expected["xyTangent"]as! [Double],name)
                try near(pose.position.z,number(expected,"height"),name+" height");rows+=1
            };cases+=1
        }
        for test in groups["frameFixtures"]! {
            let name=test["name"]as! String,initial=test["initial"]as! [String:Any]
            let graph=Graph(kind:test["syntheticGraph"]as! String)
            var actor=NativeAmbientTraffic.Actor(identity:.init(id:17,model:411,first:1,second:2),generation:1,
                road:road(initial["told"]as! [String:Any]),baseAt:number(initial,"toldAt"),received:1)
            actor.fresh=initial["fresh"]as! Bool
            actor.free=(initial["loose"]as? [String:Any]).map{loose($0)}
            actor.freeAt=(initial["looseAt"]as? NSNumber)?.doubleValue
            actor.freeBefore=(initial["looseBefore"]as? [String:Any]).map{loose($0)}
            actor.freeBeforeAt=(initial["looseBeforeAt"]as? NSNumber)?.doubleValue
            actor.before=(initial["before"]as? [String:Any]).map{road($0)}
            actor.beforeAt=(initial["beforeAt"]as? NSNumber)?.doubleValue
            let old=initial["groupPosition"]as! [Double],offset=initial["eased"]as! [Double]
            var history=M.History(shown:initial["shown"]as! Bool,wasFree:initial["wasLoose"]as! Bool,
                lastFreeCorrection:(initial["looseEased"]as? NSNumber)?.doubleValue,offset:SIMD2(offset[0],-offset[2]),
                yawOffset:number(initial,"turnEased"),position:SIMD3(old[0],-old[2],old[1]))
            for step in test["steps"]as! [[String:Any]] {
                if let fresh=(step["inputPatch"]as! [String:Any])["fresh"]as? Bool{actor.fresh=fresh}
                let expected=step["expectedSelected"]as! [String:Any],after=step["expectedAfter"]as! [String:Any]
                let result=try M.present(&actor,history:&history,serverNow:number(step,"siteNow"),renderDelta:number(step,"delta"),geometry:graph)
                if expected["stale"]as? Bool==true {try check(result==nil,name+" stale")}
                else {
                    guard let result else{throw NSError(domain:name+" missing frame",code:1)}
                    try check(result.sample.free==expected["free"]as! Bool,name+" selected mode")
                    try near(result.sample.ageMilliseconds,number(expected,"ageMS"),name+" age")
                    try compare(result.sample.pose,expected["xy"]as! [Double],name+" raw sample")
                    try near(result.sample.pose.position.z,number(expected,"vertical"),name+" vertical")
                    if let road=result.sample.road{try compare(road,expected["work"]as! [String:Any],name+" road work")}
                    if let loose=result.sample.loose{try compare(loose,expected["work"]as! [String:Any],name+" free work")}
                }
                try check(actor.fresh==after["fresh"]as! Bool && history.wasFree==after["wasLoose"]as! Bool,name+" state owners")
                if let stamp=(after["looseEased"]as? NSNumber)?.doubleValue{try check(history.lastFreeCorrection==stamp,name+" once per snapshot")}
                else{try check(history.lastFreeCorrection==nil,name+" absent correction stamp")}
                let eased=after["eased"]as! [String:Any],position=after["position"]as! [String:Any]
                try near(history.offset.x,number(eased,"x"),name+" residual X");try near(history.offset.y,-number(eased,"z"),name+" residual Y")
                try near(history.yawOffset,number(after,"turnEased"),name+" yaw residual")
                try near(history.position.x,number(position,"x"),name+" displayed X");try near(history.position.y,-number(position,"z"),name+" displayed Y")
                try near(history.position.z,number(position,"y"),name+" displayed Z")
                try compare(actor.road,after["told"]as! [String:Any],name+" authoritative road held")
                if let value=actor.free{try compare(M.Free(value),after["loose"]as! [String:Any],name+" authoritative free held")};rows+=1
            };cases+=1
        }
        try check(cases==root["caseCount"]as! Int && rows==root["resultRows"]as! Int,"Reference coverage changed")
        print("PASS archived scalar traffic motion: \(cases) cases, \(rows) rows. Original graph measurements remain local; terrain/body fitting and render/physics/AI excluded")
    }
}
