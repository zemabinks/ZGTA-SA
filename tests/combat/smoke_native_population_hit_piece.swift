// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd

@main enum PopulationHitPieceTests {
    static var checks=0
    static func check(_ value:Bool,_ message:String){
        checks+=1
        if !value{FileHandle.standardError.write(Data(("FAIL: "+message+"\n").utf8));exit(1)}
    }
    static func snapshot(_ row:[String:Any])throws->NativeAmbientPedestrianAnimation.Snapshot {
        let message=Data(base64Encoded:row["free"]as! String)! + Data(base64Encoded:row["packet"]as! String)!
        let events=try NativeAmbientPedestrianProtocol.decodeMessage(message,nowServerMilliseconds:(row["time"]as! NSNumber).doubleValue)
        guard events.count==2,case .free(_,let feet)=events[0],case .state(let states)=events[1],
              feet.count==1,states.count==1,feet[0].identity.id==states[0].id else{fatalError("Backend pair failed actual typed admission")}
        let state=states[0],foot=feet[0]
        if let expected=row["expected"]as? Int {
            check(Int(state.hitPiece)==expected,"Native packet decoder lost admitted body piece")
            check(Int(state.hitCounter)==row["counter"]as! Int,"Native counter differs from actual task")
        }
        return .init(position:foot.feet,heading:0,speed:foot.speed,flags:foot.identity.flags,state:state,
                     id:foot.identity.id,seed:foot.identity.seed)
    }
    static func main()throws {
        let document=try JSONSerialization.jsonObject(with:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))as! [String:Any]
        let baseline=document["baseline"]as! [String:Any],rows=document["evidence"]as! [[String:Any]]
        let epoch=(baseline["time"]as! NSNumber).doubleValue
        let library=NPCAnimationCandidateTests.fixture()
        for hz in [20,30,60,120] {
            let npc=NativeAmbientPedestrianAnimation(library:library,style:.init(),weapons:[:],random:{0.25})
            var current=try snapshot(baseline),time=10.0
            _=npc.update(at:time,active:true,snapshot:current)
            check(!npc.animator.dead && !npc.animator.lostHead,"Baseline invented a death/reaction")
            for row in rows {
                let target=10+((row["time"]as! NSNumber).doubleValue-epoch)/1000
                while time+1.0/Double(hz)<target-1e-9 {
                    time+=1.0/Double(hz);_=npc.update(at:time,active:true,snapshot:current)
                }
                time=target;current=try snapshot(row)
                let frame=npc.update(at:time,active:true,snapshot:current)
                check(frame != nil && !(frame?.blends.isEmpty ?? true),"Actual common pose owner produced no authored pose")
                if row["label"]as! String=="terminal-head" {
                    check(npc.animator.dead && npc.animator.lostHead,"Accepted terminal head metadata did not reach native death/head owner")
                    check(frame!.hiddenBones.contains(5),"Actual native frame did not carry its existing head visibility result")
                }else{
                    check(!npc.animator.dead && !npc.animator.lostHead,"Nonterminal metadata fabricated a death/head loss")
                }
            }
        }
        print("PASS native NPC shot-piece pipeline: \(checks) checks, actual backend bytes/typed decoder/common animation at20/30/60/120Hz; authored clips/geometry, no rendered rig or retail claim")
    }
}
