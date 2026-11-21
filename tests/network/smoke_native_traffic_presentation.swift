// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main enum TrafficPresentationTests {
    typealias P=NativeAmbientTrafficPresentation
    static var checks=0
    static func check(_ value:Bool,_ label:String)throws{checks+=1;if !value{throw NSError(domain:label,code:1)}}
    static func near(_ actual:Double,_ expected:Double,_ label:String)throws {
        try check(actual.isFinite && abs(actual-expected)<1e-8,"\(label):\(actual) expected\(expected)")
    }
    static func input(speed:Double=10,delta:Double=0.02,baseline:Double=0)->P.Input {
        .init(id:2,frame:1,position:.zero,direction:SIMD2(1,0),baseline:baseline,length:4,distance:10,delta:delta,
            free:false,freePosition:nil,freeStamp:nil,speed:speed,side:0,aim:0,flags:0,residual:.zero,yawResidual:0)
    }
    static func main()throws {
        var owner=P();owner.state.height=0;owner.state.yaw=0
        let frame=try owner.update(input(),ray:nil)
        try near(frame.heading,0.05,"Native heading conversion and angular rate bound")
        try near(frame.spin,-2.5,"Wheel caller yaw rate")
        try near(frame.steering,-atan(-0.6)*0.16,"Steering response")
        try near(frame.wheelPhase,-10*0.02/0.36,"Wheel phase units")
        var reverse=P();reverse.state.height=0;reverse.state.yaw=0
        let reversed=try reverse.update(input(speed:-10),ray:nil)
        try near(reversed.steering,0,"Reverse positive-speed steering gate")
        try near(reversed.wheelPhase,-frame.wheelPhase,"Reverse wheel phase")
        var initial=P();let zero=try initial.update(input(speed:0,delta:0,baseline:5),ray:{origin,_ in origin.z-5})
        try near(zero.position.z,5,"Initial ground snaps at zero delta")
        var probe=P();probe.state.ground=12;probe.state.slope=0.2;probe.state.unfelt=3
        var calls=0
        let found=probe.probe(input(),baseline:0,ray:{_,_ in calls+=1;return calls==1 ? 2:nil})
        try check(!found && calls==2 && probe.state.ground==12 && probe.state.slope==0.2 && probe.state.unfelt==3,"One ray miss replaced plane ownership")
        if CommandLine.arguments.count==2{try reference(CommandLine.arguments[1])}
        print("PASS native traffic presentation: \(checks) checks. Controlled terrain distances and scalar body/wheel caller; no actual collision, wheel mesh, occupants, renderer or retail claim")
    }
    // Observed rows stay owner-local. The adapter compares actual native
    // production state and query order, converting only coordinate systems.
    static func reference(_ path:String)throws {
        let root=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:path)))as! [String:Any]
        func n(_ row:[String:Any],_ key:String)->Double{(row[key]as! NSNumber).doubleValue}
        func optional(_ value:Any?)->Double?{(value as? NSNumber)?.doubleValue}
        var cases=0
        for test in root["cases"]as! [[String:Any]] {
            let name=test["name"]as! String,source=test["authoredInput"]as! [String:Any],resolved=test["resolvedInput"]as! [String:Any]
            let before=test["before"]as! [String:Any],after=test["expectedAfter"]as! [String:Any]
            let trajectory=resolved["trajectory"]as! [Double],scalar=resolved["scalar"]as! [String:Any]
            let eased=before["eased"]as! [String:Any],actor=source["actor"]as? [String:Any] ?? [:],loose=actor["loose"]as? [String:Any] ?? ["x":0,"y":0]
            let free=resolved["free"]as! Bool
            let input=P.Input(id:UInt16(optional(actor["id"]) ?? 2),frame:Int(n(resolved,"frame")),position:SIMD2(trajectory[0],trajectory[1]),direction:SIMD2(trajectory[2],trajectory[3]),
                baseline:n(resolved,"baseline"),length:n(resolved,"length"),distance:n(resolved,"far"),delta:n(resolved,"delta"),free:free,
                freePosition:free ? SIMD2(n(loose,"x"),n(loose,"y")):nil,freeStamp:free ? optional(actor["looseAt"]) ?? 1_000_000:nil,
                speed:n(scalar,"v"),side:n(scalar,"side"),aim:n(scalar,"aim"),flags:UInt8(n(scalar,"flags")),residual:SIMD2(n(eased,"x"),-n(eased,"z")),yawResidual:n(before,"turnEased"))
            var owner=P()
            owner.state = .init(height:optional(before["y"]),ground:n(before,"ground"),slope:n(before,"slope"),pitch:n(before,"pitch"),
                previous:SIMD2(n(before,"wasX"),n(before,"wasY")),unfelt:n(before,"unfelt"),feltAt:optional(before["feltAt"]).map(Int.init),groundStamp:optional(before["groundTold"]),
                yaw:optional(before["heading"]),facing:n(before,"facing"),steering:n(before,"steer"),spin:n(before,"spin"),wheelPhase:n(before,"rolled"))
            let rays=test["expectedRays"]as! [[String:Any]];var used=0,rayFailure:Error?
            let ray:P.DownRay={origin,maximum in
                do {
                    try check(used<rays.count,name+" unexpected ray")
                    let expected=rays[used],point=expected["origin"]as! [String:Any];used+=1
                    try near(origin.x,n(point,"x"),name+" ray X");try near(origin.y,-n(point,"z"),name+" ray Y")
                    try near(origin.z,n(point,"y"),name+" ray Z");try near(maximum,n(expected,"max"),name+" ray range")
                    return optional(expected["returned"])
                }catch{rayFailure=error;return nil}
            }
            if test["kind"]as! String=="probe" {
                let padding=source["padding"]as? [Double] ?? []
                let found=owner.probe(input,baseline:input.baseline,raise:padding.first ?? 0,lower:padding.count>1 ? padding[1]:nil,ray:ray)
                try check(found==test["expectedReturn"]as! Bool,name+" probe result")
            }else{
                let result=try owner.update(input,ray:resolved["physics"]as! Bool ? ray:nil)
                let position=after["position"]as! [String:Any]
                try near(result.position.x,n(position,"x"),name+" fitted X");try near(result.position.y,-n(position,"z"),name+" fitted Y")
                try near(result.position.z,n(position,"y"),name+" fitted Z")
                try near(result.heading,-n(after,"heading"),name+" native heading")
                try near(result.pitch,n(after,"pitch"),name+" native pitch")
                let euler=test["expectedEulerCalls"]as! [[String:Any]],wheels=test["expectedWheelCalls"]as! [[String:Any]]
                try check(euler.count==1 && wheels.count==1,name+" pose caller coverage")
                try check(euler[0]["order"]as? String=="YXZ",name+" source Euler boundary")
                try near(n(euler[0],"pitch"),result.pitch,name+" Euler pitch")
                try near(n(euler[0],"yaw"),-result.heading,name+" Euler yaw")
                try near(n(euler[0],"roll"),0,name+" Euler roll")
                // Wheel helper implementation/mesh output is a separate gate.
                try near(n(wheels[0],"steer"),result.steering,name+" wheel caller steering")
                try near(n(wheels[0],"frontRoll"),result.wheelPhase,name+" front wheel phase")
                try near(n(wheels[0],"rearRoll"),result.wheelPhase,name+" rear wheel phase")
            }
            if let rayFailure{throw rayFailure}
            try check(used==rays.count,name+" omitted ray")
            for (key,actual) in ["ground":owner.state.ground,"slope":owner.state.slope,"pitch":owner.state.pitch,"wasX":owner.state.previous.x,"wasY":owner.state.previous.y,
                "unfelt":owner.state.unfelt,"facing":owner.state.facing,"steer":owner.state.steering,"spin":owner.state.spin,"rolled":owner.state.wheelPhase]{try near(actual,n(after,key),name+" state "+key)}
            for (key,actual) in ["y":owner.state.height,"heading":owner.state.yaw,"groundTold":owner.state.groundStamp,"feltAt":owner.state.feltAt.map(Double.init)] {
                if let expected=optional(after[key]){try check(actual != nil,name+" missing "+key);try near(actual!,expected,name+" optional "+key)}
                else{try check(actual==nil,name+" absent "+key)}
            };cases+=1
        }
        try check(cases==root["caseCount"]as! Int,"Presentation reference coverage changed")
        print("PASS archived traffic presentation: \(cases) authored cases, actual scalar state/ray order; no physical collision or rendered acceptance")
    }
}
