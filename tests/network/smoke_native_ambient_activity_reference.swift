// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

// This separate carrier compares literal selection/transition code with a
// completed offline archived dispatch capture. It does not execute animation
// or pretend that a resident native library has browser block-load latency.
@main enum NPCActivityReference {
    static var checks=0
    static func check(_ value:Bool,_ message:String){checks+=1;if !value{FileHandle.standardError.write(Data(("FAIL: "+message+"\n").utf8));exit(1)}}
    static func number(_ row:[String:Any],_ key:String)->Double{(row[key] as! NSNumber).doubleValue}
    static func main()throws {
        func json(_ path:String)throws->Any{try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:path)))}
        let reference=try json(CommandLine.arguments[1])as! [String:Any]
        let definitions=try json(CommandLine.arguments[2])as! [[String:Any]]
        let durationEnvelope=try json(CommandLine.arguments[3])as! [String:Any]
        let durations=durationEnvelope["clips"]as! [String:[String:Any]]
        var accepted=0,steps=0,excluded:[String]=[]
        for test in reference["cases"]as! [[String:Any]] {
            let name=test["name"]as! String,rows=test["steps"]as! [[String:Any]]
            if rows.contains(where:{$0["action"]as! String != "dispatch"}) || !(test["deferredBlocks"]as! [String]).isEmpty {
                excluded.append(name);continue
            }
            let definition=definitions.first{$0["name"]as? String==name}!
            var planner=NativeAmbientPedestrianActivity()
            planner.firstMood=UInt8(number(rows[0]["inputs"]as! [String:Any],"moodFirst"))
            let missing=Set(test["missingClips"]as! [String])
            for row in rows {
                let now=number(row,"timestampMS"),input=row["inputs"]as! [String:Any]
                var data=NativeAmbientPedestrianActivity.Input(id:17,seed:9,mood:UInt8(number(input,"mood")),
                    down:input["down"]as! Bool,female:input["woman"]as! Bool,foe:number(input,"foe") != 0)
                data.waving=definition["wave"]as? Bool ?? false;data.talking=definition["talk"]as? Bool ?? false
                if now<number(input,"sayUntil"){data.chat=input["saidAct"]as? String}
                let commands=planner.update(now:now,input:data,duration:{clip in
                    guard !missing.contains(clip)else{return nil}
                    return durations[clip].map{number($0,"duration")}
                })
                var scripts:[[String:Any]]=[],rests=0
                for command in commands {
                    switch command {
                    case .rest:rests+=1
                    case .play(let clip,let loop,let rooted,let once):scripts.append(["clip":clip,"loop":loop,"rooted":rooted,"once":once,"cut":false])
                    }
                }
                let expected=(row["expectedScripts"]as! [[String:Any]]).map{entry in entry.filter{$0.key != "argumentType"}}
                check(NSArray(array:scripts).isEqual(to:expected),name+" scripts \(scripts) != \(expected)")
                check(rests==Int(number(row,"expectedRestCalls")),name+" rest count")
                check(planner.selected==row["expectedSelectedAct"]as? String,name+" selected activity")
                if let next=row["expectedNextAct"]as? [String:Any] {
                    check(planner.pending?.clip==next["name"]as? String,name+" pending loop")
                    check(planner.pending?.rooted==next["rooted"]as? Bool,name+" pending root policy")
                    check(abs((planner.pending?.at ?? -.infinity)-number(next,"at"))<1e-7,name+" admitted duration deadline")
                }else{check(planner.pending==nil,name+" unexpected pending loop")}
                steps+=1
            }
            accepted+=1
        }
        let report:[String:Any]=["status":"PASS","checks":checks,"cases":accepted,"steps":steps,"excluded":excluded,
            "scope":"Literal independent activity planner with test-writable historical first mood; actual captured archived script/selection/deadline observations and supplied resource durations. Excludes browser async load/identity cancellation, controller gait/animation/rendering, retail and live event wiring. Wave/talk/chat are explicit planner inputs only."]
        print(String(data:try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
    }
}
