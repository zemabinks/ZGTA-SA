// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
import Darwin

/// Authored clock/door/capture fixtures on the actual native planner/playback
/// and CLP1 reader. All generated tracks/geometry are invented. An optional
/// generic duration fixture tests externally supplied metadata, not its poses.
@main enum RiderClockSmoke {
    struct Failure:Error {let message:String}
    static var checks=0
    static func check(_ value:Bool,_ message:String)throws {
        checks+=1;if !value{throw Failure(message:message)}
    }
    static func near(_ a:Double,_ b:Double,_ message:String,_ tolerance:Double=1e-9)throws {
        try check(a.isFinite && b.isFinite && abs(a-b)<=tolerance,message)
    }
    static func word(_ value:UInt32,_ data:inout Data) {
        var v=value.littleEndian;withUnsafeBytes(of:&v){data.append(contentsOf:$0)}
    }
    static func number(_ value:Float,_ data:inout Data){word(value.bitPattern,&data)}
    static func string(_ value:String,_ data:inout Data) {
        let bytes=Array(value.utf8);var count=UInt16(bytes.count).littleEndian
        withUnsafeBytes(of:&count){data.append(contentsOf:$0)};data.append(contentsOf:bytes)
    }
    static let authored:[String:Double] = ["open":0.713,"getIn":0.947,"closeIn":0.283,
        "getOut":0.617,"closeOut":0.389,"pullOut":0.137,"shuffle":0.193]
    static func fixture(_ roles:[String:Double])throws->(NativeRiderDefinitions.Definition,NativeSkeletalAnimationLibrary,[String:Double]) {
        var clips=roles.map{("invented/"+$0.key.lowercased(),Float($0.value))}
        clips += [("ped/idle_stance",Float(1)),("invented/sit",Float(1))]
        clips.sort{$0.0<$1.0}
        var data=Data();[UInt32(0x31504c43),UInt32(clips.count),0,1].forEach{word($0,&data)}
        for (name,length) in clips {
            try check(length.isFinite && length>=0 && length<3600,"duration fixture bound")
            string(name,&data);number(length,&data);word(1,&data)
            word(0,&data);word(2,&data);word(1,&data)
            for (time,offset) in [(Float(0),Float(0)),(length,Float(0.1))] {
                number(time,&data);[Float(0),0,0,1,offset,0,0].forEach{number($0,&data)}
            }
        }
        guard let library=NativeSkeletalAnimationLibrary(data:data)else{throw Failure(message:"actual CLP1 decoder rejected authored fixture")}
        func pair(_ role:String)->[String]{["invented:"+role.lowercased(),"invented:"+role.lowercased()]}
        let group=NativeRiderDefinitions.Group(open:pair("open"),openRear:pair("open"),
            getIn:pair("getIn"),getInRear:pair("getIn"),pullOut:pair("pullOut"),
            closeIn:pair("closeIn"),closeInRear:pair("closeIn"),getOut:pair("getOut"),getOutRear:pair("getOut"),
            closeOut:pair("closeOut"),closeOutRear:pair("closeOut"),getInTime:0.2,getOutTime:0.2,
            doorOpenOut:[0.1,0.3],doorCloseIn:[0.1,0.2],doorOpenIn:[0.05,0.2],doorCloseOut:[0.1,0.2],
            special:0,shuffle:"invented:shuffle")
        let seats=[NativeRiderDefinitions.Seat(at:[-0.4,0,0],side:-1,rear:false,opens:true,door:2,via:nil,shift:nil,turn:0),
                   NativeRiderDefinitions.Seat(at:[0.4,0,0],side:1,rear:false,opens:true,door:3,via:nil,shift:nil,turn:0)]
        let definition=NativeRiderDefinitions.Definition(model:"invented",astride:false,clips:["sit":"invented/sit","passenger":"invented/sit"],
            seats:seats,origin:0.8,bike:nil,afloat:false,group:group)
        return (definition,library,roles.mapValues{Double(Float($0))})
    }
    static func playback(_ fixture:(NativeRiderDefinitions.Definition,NativeSkeletalAnimationLibrary,[String:Double]))throws->NativeRiderPlayback {
        guard let value=NativeRiderPlayback(definition:fixture.0,library:fixture.1)else{throw Failure(message:"actual playback configuration")}
        return value
    }
    static let schedules:[[Double]] = [[1.0/15],[1.0/30],[1.0/60],[1.0/120],
                                       [1.0/120,1.0/20,1.0/75,1.0/30,1.0/144]]
    static func advance(_ value:NativeRiderPlayback,to total:Double,schedule:[Double])throws->NativeRiderPlayback.Frame {
        var wall=0.0,index=0,last=value.update(delta:0,input:.init())!
        while wall<total-1e-12 {
            let step=min(schedule[index%schedule.count],total-wall)
            guard step>0,index<100000 else{throw Failure(message:"authored schedule bound")}
            last=value.update(delta:step,input:.init())!;wall+=step;index+=1
        }
        return last
    }
    static func compare(_ a:NativeRiderPlayback.Frame,_ b:NativeRiderPlayback.Frame)throws {
        try check(a.state==b.state,"phase clock schedule dependence")
        try check(a.sample.pose.base==b.sample.pose.base,"phase sample schedule dependence")
        try near(a.sample.pose.time,b.sample.pose.time,"phase sample elapsed lost")
        try check(simd_distance(a.sample.anchor,b.sample.anchor)<1e-9,"phase anchor schedule dependence")
        try check(a.captureSerial==b.captureSerial,"phase serial schedule dependence")
        try check(a.doorPart==b.doorPart,"door owner schedule dependence")
        try near(a.doorOpen,b.doorOpen,"door elapsed schedule dependence")
        try near(a.transition,b.transition,"transition elapsed schedule dependence")
    }
    static func scheduleChecks(_ f:(NativeRiderDefinitions.Definition,NativeSkeletalAnimationLibrary,[String:Double]))throws {
        let roles=f.2
        let enter=(roles["open"] ?? 0)+(roles["getIn"] ?? 0)+(roles["closeIn"] ?? 0)
        let leave=(roles["getOut"] ?? 0)+(roles["closeOut"] ?? 0)
        for jack in [false,true] {
            let total=enter+(jack ? roles["pullOut"] ?? 0:0)
            let times=[0.031,total*0.2,total*0.7,total-1e-8,total+1e-8,total+0.07]
            for time in times where time>=0 {
                var baseline:NativeRiderPlayback.Frame?
                for schedule in schedules {
                    let value=try playback(f);value.enter(side:-1,jack:jack)
                    let frame=try advance(value,to:time,schedule:schedule)
                    if let baseline{try compare(baseline,frame)}else{baseline=frame}
                    if time>=total+1e-8{try check(frame.state == .inside,"entry not completed at actual clip sum")}
                    if time<total-1e-9{try check(frame.state == .entering,"entry completed before actual clip sum")}
                }
            }
        }
        for time in [0.031,leave*0.3,leave-1e-8,leave+1e-8,leave+0.07] where time>=0 {
            var baseline:NativeRiderPlayback.Frame?
            for schedule in schedules {
                let value=try playback(f);value.sit();value.leave(side:-1)
                let frame=try advance(value,to:time,schedule:schedule)
                if let baseline{try compare(baseline,frame)}else{baseline=frame}
                try check(frame.state == (time>=leave ? .stood:.leaving),"exit clip-sum boundary")
            }
        }
    }
    static func captureChecks()throws {
        let f=try fixture(["open":0.0625,"getIn":0.125,"closeIn":0.0625,"getOut":0.125,"closeOut":0.0625,"pullOut":0.0625])
        let value=try playback(f);value.enter(side:-1)
        let initial=value.update(delta:0,input:.init())!
        try check(initial.captureSerial==1 && initial.capture != nil,"initial capture absent")
        let before=value.update(delta:0.0625-1e-8,input:.init())!
        try check(before.captureSerial==1 && before.doorPart==2,"early phase transition")
        let boundary=value.update(delta:1e-8,input:.init())!
        try check(boundary.captureSerial==2,"exact representable boundary missing")
        if case .sample(let pose)?=boundary.capture {
            try check(pose.pose.base=="invented/open","capture is not outgoing phase")
            try near(pose.pose.time,0.0625,"capture is not exact phase end")
        }else{throw Failure(message:"exact outgoing capture absent")}
        let crossed=value.update(delta:0.25,input:.init())!
        try check(crossed.state == .inside && crossed.captureSerial==4,"multiple phase consumption")
        if case .sample(let pose)?=crossed.capture {
            try check(pose.pose.base=="invented/closein","latest crossed capture was lost")
            try near(pose.pose.time,0.0625,"last exact phase capture")
        }else{throw Failure(message:"latest crossed capture absent")}
        try check(crossed.doorPart==nil && crossed.releasedDoor?.0==2,"terminal door release absent")
        try near(crossed.releasedDoor!.1,0,"terminal door opening")
        try near(crossed.transition,0.15625,"transition consumed preceding phase time")
        let next=value.update(delta:0,input:.init())!
        try check(next.capture==nil && next.releasedDoor==nil && next.captureSerial==4,"capture/release replayed")
        value.leave(side:-1)
        let leaving=value.update(delta:0,input:.init())!
        if case .current?=leaving.capture{}else{throw Failure(message:"exit current-pose capture changed")}
        let exited=value.update(delta:0.1875,input:.init())!
        try check(exited.state == .stood && exited.doorPart==nil && exited.releasedDoor?.0==2,"exit release/clock completion")
    }
    static func interruptionChecks()throws {
        let f=try fixture(authored),value=try playback(f)
        value.enter(side:-1,jack:true);_=value.update(delta:0.13,input:.init())
        value.leave(side:-1);let leaving=value.update(delta:0,input:.init())!
        try check(leaving.state == .leaving,"leave did not cancel jack entry")
        if case .current?=leaving.capture{}else{throw Failure(message:"interrupted exit capture")}
        value.sit();let seated=value.update(delta:0.5,input:.init())!
        try check(seated.state == .inside && seated.capture==nil && seated.doorPart==nil,"sit retained old queue/door")
        value.enter(side:-1);_=value.update(delta:0.1,input:.init())
        value.leave(side:-1);_=value.update(delta:0.1,input:.init())
        value.enter(side:-1,jack:true)
        let reentered=try advance(value,to:f.2["open"]!+f.2["getIn"]!+f.2["closeIn"]!+f.2["pullOut"]!+0.01,schedule:[0.1])
        try check(reentered.state == .inside,"new entry resumed obsolete leave")
        let held=reentered
        for bad in [-0.01,Double.nan,Double.infinity,0.500001,2] {
            let frame=value.update(delta:bad,input:.init())!
            try compare(held,frame);try check(frame.capture==nil && frame.releasedDoor==nil,"discontinuity generated phase event")
        }
        value.leave(side:-1);_=value.update(delta:0.1,input:.init())
        let phase=value.update(delta:0,input:.init())!
        for bad in [-1,Double.nan,Double.infinity,0.500001,5] {
            let frame=value.update(delta:bad,input:.init())!
            try compare(phase,frame);try check(frame.capture==nil,"invalid clock crossed phase")
        }
        let final=try advance(value,to:f.2["getOut"]!+f.2["closeOut"]!,schedule:[0.1])
        try check(final.state == .stood,"discontinuity became queued backlog")
    }
    static func seatTurnBoundaryChecks()throws {
        var f=try fixture(["open":0.0625,"getIn":0.125,"closeIn":0.0625])
        f.0.seats[0].turn=0.6
        let value=try playback(f);value.enter(side:-1)
        let frame=value.update(delta:0.3125,input:.init())!
        try check(frame.state == .inside,"seat turn boundary did not finish entry")
        // Only .0625s belongs to the seated target; the preceding .25s was
        // spent boarding. Keep the existing linear seat-turn response curve.
        try near(frame.turn,0.3,"seat target consumed earlier boarding time")
        let seated=value.update(delta:0.0625,input:.init())!
        try near(seated.turn,0.45,"ordinary seated turn curve changed")
    }
    static func emptyChecks()throws {
        let zero=try fixture(["open":0,"getIn":0,"closeIn":0,"getOut":0,"closeOut":0,"pullOut":0])
        let value=try playback(zero);value.enter(side:-1,jack:true)
        let frame=value.update(delta:0,input:.init())!
        try check(frame.state == .inside && frame.captureSerial==5,"zero phases stalled or looped")
        try check(frame.doorPart==nil && frame.releasedDoor?.0==2,"zero-phase door release")
        value.leave(side:-1);let exit=value.update(delta:0,input:.init())!
        try check(exit.state == .stood && exit.captureSerial==8,"zero exit clock/serial")
        let missing=try playback(fixture([:]));missing.enter(side:-1)
        try check(missing.update(delta:0,input:.init())!.state == .inside,"missing entry clips stalled")
        missing.leave(side:-1);try check(missing.update(delta:0,input:.init())!.state == .stood,"missing exit clips stalled")
    }
    static func main() {
        do {
            try scheduleChecks(fixture(authored));try captureChecks();try interruptionChecks();try seatTurnBoundaryChecks();try emptyChecks()
            var metadata=false
            if CommandLine.arguments.count>1 {
                let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
                guard data.count<=16384,let doc=try JSONSerialization.jsonObject(with:data) as? [String:Any],
                      let roles=doc["roles"] as? [String:Double],roles.count<=16 else{throw Failure(message:"duration metadata fixture schema")}
                for role in ["open","getIn","closeIn","getOut","closeOut"]{try check(roles[role] != nil,"duration metadata role missing")}
                try scheduleChecks(fixture(roles));metadata=true
            }
            let result:[String:Any] = ["status":"PASS","checks":checks,"actualNativeClock":true,
                "actualCLP1Reader":true,"syntheticTracks":true,"externalDurationMetadata":metadata,
                "renderedOrRetailAcceptance":false]
            print(String(data:try JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),encoding:.utf8)!)
        } catch {
            let result:[String:Any] = ["status":"FAIL","checks":checks,"failure":(error as? Failure)?.message ?? String(describing:error)]
            print(String(data:try! JSONSerialization.data(withJSONObject:result,options:[.sortedKeys]),encoding:.utf8)!)
            exit(1)
        }
    }
}
