// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main enum TrafficMotionTests {
    typealias M=NativeAmbientTrafficMotion
    typealias P=NativeAmbientTrafficProtocol
    static var checks=0
    static func check(_ condition:Bool,_ label:String)throws {
        checks+=1;if !condition{throw NSError(domain:label,code:1)}
    }
    static func near(_ actual:Double,_ expected:Double,_ label:String)throws {
        try check(actual.isFinite && abs(actual-expected)<1e-8,"\(label): \(actual) expected \(expected)")
    }
    struct Graph:NativeAmbientTrafficGeometry {
        let original:NativeAmbientTrafficRoads?
        let kind:String,speeds:[String:Int]
        init(original:NativeAmbientTrafficRoads?=nil,kind:String="line",speeds:[String:Int]=[:]){self.original=original;self.kind=kind;self.speeds=speeds}
        var linkTo:[UInt16]{original?.linkTo ?? [1,2,3,4,5,6]}
        func lanePoint(_ link:UInt16,lane:UInt8)throws->(position:SIMD2<Double>,direction:SIMD2<Double>) {
            if let original{return try original.lanePoint(link,lane:lane)}
            guard link<6 else{throw M.Failure.invalidState}
            var direction=SIMD2<Double>(1,0)
            if link==2 && (kind=="dotExact" || kind=="dotAbove") {
                let x=kind=="dotExact" ? 0.95:0.9500001;direction=SIMD2(x,sqrt(1-x*x))
            }
            let spacing=kind=="shortLine" ? 10.0:100.0
            let p=SIMD2(Double(link)*spacing,0)+SIMD2(direction.y,-direction.x)*(Double(lane)*5.4)
            return(p,direction)
        }
        func speedClass(_ node:UInt16)throws->UInt8 {
            if let original{return try original.speedClass(node)};return UInt8(speeds[String(node)] ?? 0)
        }
        func height(from first:UInt16,to second:UInt16,progress:Double)throws->Double {
            if let original{return try original.height(from:first,to:second,progress:progress)};return 0
        }
    }
    static func road()->M.Road {
        .init(.init(identity:.init(id:17,model:411,first:1,second:2),first:.init(link:0,lane:0),second:.init(link:1,lane:0),next:nil,nextLane:0,
                    progress:0.2,speed:2,wanted:6,rate:2))
    }
    static func free(speed:Double=2,turn:Double=0.3)->M.Free {
        M.Free(.init(id:17,position:SIMD3(10,-20,3),headingWire:0,speed:speed,wanted:speed,rate:2,turn:turn))
    }
    static func main()throws {
        let graph=Graph()
        let expected:[(UInt8,Double)]=[(0,0.6),(4,0.15),(16,0.07),(20,0.07),(255,0.07)]
        for (flags,rate) in expected{try near(M.sideRate(flags),rate,"Side convergence bit priority")}
        var forward=free(),reverse=free(speed:-2)
        try M.advance(&forward,seconds:1);try M.advance(&reverse,seconds:1)
        try near(forward.heading,0.3,"Signed forward steering");try near(reverse.heading,-0.6,"Signed reverse steering")
        var one=free(speed:0),many=one;one.wanted=4;many.wanted=4
        try M.advance(&one,seconds:1)
        for _ in 0..<20{try M.advance(&many,seconds:0.05)}
        try near(simd_distance(one.position,many.position),0,"Equal fixed free substeps")
        let held=one;try M.advance(&one,seconds:-1);try M.advance(&one,seconds:0)
        try check(one.position==held.position && one.speed==held.speed && one.heading==held.heading,"Nonpositive free time mutated state")
        for (flags,rate) in expected {
            var value=road();value.flags=flags;value.aim=100
            try M.advance(&value,seconds:1,geometry:graph)
            try near(value.progress,0.23,"Analytic acceleration distance");try near(value.speed,4,"Road speed")
            try near(value.side,3*rate,"Side uses distance, not frame count")
        }
        var stopped=road();stopped.progress=0.99;stopped.speed=10;stopped.wanted=10
        try M.advance(&stopped,seconds:1,geometry:graph)
        try near(stopped.progress,1,"Route end clamp");try near(stopped.speed,10,"Route end retains velocity field")
        let p=SIMD2<Double>(0,0),u=SIMD2<Double>(1,0),q=SIMD2<Double>(10,10),v=SIMD2<Double>(0,1)
        try near(M.length(p,u,q,v),20,"Corner travel length")
        let corner=M.curve(p,u,q,v,progress:0.5)
        try near(corner.x,8.75,"Rounded corner X");try near(corner.y,1.25,"Rounded corner Y")
        var actor=NativeAmbientTraffic.Actor(identity:.init(id:17,model:411,first:1,second:2),generation:1,road:road(),baseAt:1_000_000,received:1)
        actor.free = .init(id:17,position:.zero,headingWire:0,speed:2,wanted:2,rate:1,turn:0.3);actor.freeAt=1_000_000
        let initialRoad=actor.road.progress
        let end=try M.select(actor,serverNow:1_001_000,wasFree:false,geometry:graph)!
        for ms in stride(from:100.0,through:1000.0,by:100){_=try M.select(actor,serverNow:1_000_000+ms,wasFree:true,geometry:graph)}
        let again=try M.select(actor,serverNow:1_001_000,wasFree:true,geometry:graph)!
        try check(end.pose.position==again.pose.position && actor.road.progress==initialRoad,"Render queries accumulated authoritative motion")
        try check(try M.select(actor,serverNow:1_006_500,wasFree:true,geometry:graph) != nil,"Exact stale threshold")
        try check(try M.select(actor,serverNow:1_006_501,wasFree:true,geometry:graph)==nil,"Stale threshold removal")
        actor.freeAt=999_999
        try check(try M.select(actor,serverNow:1_000_249,wasFree:true,geometry:graph)!.free,"Free hysteresis at249ms")
        try check(try !M.select(actor,serverNow:1_000_250,wasFree:true,geometry:graph)!.free,"Free hysteresis at250ms")
        if CommandLine.arguments.count==4{try ownedReference(CommandLine.arguments[1],graphPath:CommandLine.arguments[2],crc:CommandLine.arguments[3])}
        print("PASS native traffic motion: \(checks) checks. Horizontal geometry/prediction/history only; no terrain, renderer, AI, collision, live server or retail claim")
    }
}
