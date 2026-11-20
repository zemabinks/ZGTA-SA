// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

@main enum NPCWaitingTests {
    static var checks=0
    static func check(_ value:Bool,_ message:String){checks+=1;if !value{FileHandle.standardError.write(Data(("FAIL: "+message+"\n").utf8));exit(1)}}
    static func number(_ row:[String:Any],_ key:String)->Double{(row[key] as! NSNumber).doubleValue}
    static func main()throws {
        typealias W=NativeAmbientPedestrianWaiting
        let names:[(String,Bool,String)]=[("ped/walk_old_fat",true,"old"),("ped/walk_fat_gang",true,"fat"),
            ("ped/walk_gang",true,"gang"),("ped/walk_sexy",false,"woman"),("ped/walk_pro",false,"woman"),
            ("ped/walk_player",false,""),("ped/walk_player",true,"woman")]
        for (walk,female,expected) in names{check(W.style(walk:walk,female:female)==expected,"Original style precedence")}
        var owner=W(),input=W.Input(id:17,seed:9,mood:0,flags:2,linkKind:0)
        check(owner.update(now:0,input:input).isEmpty,"Delayed wait crossed immediately")
        check(owner.update(now:3500,input:input).isEmpty,"Strict3.5s boundary changed")
        check(owner.update(now:3500.001,input:input)==[.play("ped/idle_tired",loop:false,rooted:false,once:true)],"Delayed original idle missing")
        check(owner.update(now:9000,input:input).isEmpty,"Waiting one-shot replayed")
        input.flags=0;check(owner.update(now:9001,input:input)==[.rest],"Clear did not fade script")
        check(owner.update(now:9002,input:input).isEmpty,"Repeated clear rested again")
        input.flags=2;input.linkKind=nil
        check(owner.update(now:9003,input:input)==[.play("ped/roadcross",loop:false,rooted:false,once:true)],"Free wait invented a delayed graph edge")
        input.flags=3;check(owner.update(now:9004,input:input)==[.rest],"Down failed to cancel waiting")
        check(owner.update(now:.nan,input:input).isEmpty,"Nonfinite clock changed state")
        var cases=0,steps=0
        if CommandLine.arguments.count==2 {
            let root=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))as! [String:Any]
            for test in root["cases"]as! [[String:Any]] {
                let name=test["name"]as! String;var policy=W()
                for row in test["steps"]as! [[String:Any]] {
                    let raw=row["input"]as! [String:Any],after=row["expectedAfter"]as! [String:Any]
                    let input=W.Input(id:UInt16(number(raw,"id")),seed:UInt8(number(raw,"seed")),
                        mood:UInt8(number(raw,"mood")),flags:UInt8(number(raw,"flags")),
                        linkKind:number(raw,"toNode")<0 ? nil:UInt8(number(raw,"linkKind")),style:raw["sort"]as? String ?? "")
                    let commands=policy.update(now:number(row,"timestampMS"),input:input)
                    var scripts:[[String:Any]]=[],rests=0
                    for command in commands {
                        switch command {
                        case .rest:rests+=1
                        case .play(let clip,let loop,let rooted,let once):scripts.append(["clip":String(clip.dropFirst(4)),"loop":loop,"rooted":rooted,"once":once])
                        }
                    }
                    let expected=(row["expectedScripts"]as! [[String:Any]]).map{entry->[String:Any] in
                        ["clip":entry["clip"]!,"loop":entry["loop"]!,"rooted":false,"once":(entry["options"]as! [String:Any])["once"]!]
                    }
                    check(NSArray(array:scripts).isEqual(to:expected),name+" script call policy")
                    check(rests==Int(number(row,"expectedRestCalls")),name+" rest policy")
                    check(policy.waited==after["waited"]as! Bool,name+" waited state")
                    check(policy.idled==after["idled"]as! Bool,name+" one-shot state")
                    if let at=after["waitedFromMS"]as? NSNumber{check(abs((policy.waitedFrom ?? -.infinity)-at.doubleValue)<1e-8,name+" retained deadline")}
                    else{check(policy.waitedFrom==nil,name+" unexpected deadline")}
                    steps+=1
                };cases+=1
            }
        }
        print("PASS NPC waiting policy: \(checks) checks, \(cases) archived cases, \(steps) steps; excludes common controller/rendering/retail, async loading and visibility scheduling")
    }
}
