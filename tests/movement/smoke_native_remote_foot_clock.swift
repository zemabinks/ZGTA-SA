// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
import Darwin

enum ClockFailure:Error {case failed(String)}
var checks=0
func check(_ value:Bool,_ message:String)throws {
    checks+=1;if !value{throw ClockFailure.failed(message)}
}
func near(_ a:Double,_ b:Double,_ message:String,_ tolerance:Double=1e-8)throws {
    try check(a.isFinite && b.isFinite && abs(a-b)<tolerance,message)
}
func word(_ n:UInt32,_ data:inout Data){var n=n.littleEndian;withUnsafeBytes(of:&n){data.append(contentsOf:$0)}}
func number(_ n:Float,_ data:inout Data){word(n.bitPattern,&data)}
func string(_ s:String,_ data:inout Data){var n=UInt16(s.utf8.count).littleEndian;withUnsafeBytes(of:&n){data.append(contentsOf:$0)};data.append(contentsOf:s.utf8)}
func fixture()throws->NativeSkeletalAnimationLibrary {
    var names=["ped/idle_stance","ped/walk_player","ped/run_player","ped/sprint_civi",
        "ped/jump_launch","ped/jump_glide","ped/fall_fall","ped/fall_land","ped/jump_land",
        "ped/climb_jump","ped/climb_idle","ped/climb_pull","ped/climb_stand","ped/climb_jump_b",
        "ped/climb_stand_finish","ped/climb_jump2fall","ped/swim_tread","ped/ko_shot_front",
        "ped/idle_armed","ped/handsup","invented/fire","invented/reload",
        "parachute/para_open_o","parachute/para_float_o","parachute/para_land_o"]
    names += ["fall_skydive","fall_skydive_accel","fall_skydive_l","fall_skydive_r","para_open","para_float","para_decel","para_steerl","para_steerr"].map{"parachute/"+$0}
    for i in 0..<14 {names += ["invented/walk\(i)","invented/run\(i)","invented/sprint\(i)"]}
    names=Array(Set(names)).sorted()
    var data=Data();[UInt32(0x31504c43),UInt32(names.count),0,1].forEach{word($0,&data)}
    for (index,name) in names.enumerated() {
        let length=Float(0.43+Double(index%9)*0.071),travel=Float(0.31+Double(index%7)*0.19)
        string(name,&data);number(length,&data);word(1,&data);word(0,&data);word(2,&data);word(1,&data)
        for (at,position) in [(Float(0),Float(0)),(length,travel)] {
            number(at,&data);[Float(0),0,0,1,0,position,0].forEach{number($0,&data)}
        }
    }
    guard let library=NativeSkeletalAnimationLibrary(data:data)else{throw ClockFailure.failed("authored CLP decode")}
    return library
}
func engine(_ library:NativeSkeletalAnimationLibrary,_ style:NativeFootAnimationStyle=NativeFootAnimationStyle(),_ weapons:[Int:NativeFootWeaponAnimation]=[:])->NativeRemoteFootAnimation {
    NativeRemoteFootAnimation(library:library,style:style,weapons:weapons,random:{0.173})
}
final class CanopySpy {
    var calls:[Double]=[]
    func canopyPose(clip:String,time:Double,easing:Double,pitch:Double,roll:Double,library:NativeSkeletalAnimationLibrary,previous:Double?)->Double {
        calls.append(time)
        // Invented moving target exposes loss of intermediate targets. This
        // is a dispatch spy, not a substitute for actual skeletal rendering.
        let target=time*time+pitch
        return previous.map{$0+(target-$0)*easing} ?? target
    }
}
struct CanopyDispatch {
    var flightCanopyMesh:Int?=1
    var flightCanopyActor:CanopySpy?=CanopySpy()
    var skeletalLibrary:NativeSkeletalAnimationLibrary?
    var flightCanopyPoses:[String:Double]=["remote":3.75]
    var flightCanopyLanded:[String:Double]=[:]
    mutating func sample(_ flight:NativeFlightAnimation.Frame,_ canopySamples:[NativeFlightAnimation.Canopy?],transform:Double=7) {
        let identity="remote"
        // ACTUAL_CANOPY_DISPATCH
    }
}
func advance(_ owner:DrawOwner,_ state:NativeRemoteFootAnimation.Snapshot,_ schedule:[Double],_ total:Double=2)throws->(SIMD2<Double>,[String],NativeFootAnimation.Frame) {
    var time=10.0,index=0,travel=SIMD2<Double>.zero,steps:[String]=[]
    guard var final=owner.sample(time,true,state)else{throw ClockFailure.failed("first pose")}
    while time<10+total-1e-10 {
        let dt=min(schedule[index%schedule.count],10+total-time);time+=dt;index+=1
        guard let frame=owner.sample(time,true,state)else{throw ClockFailure.failed("active pose")}
        travel+=frame.travel;steps+=frame.steps;final=frame
    }
    return(travel,steps,final)
}
do {
    let library=try fixture()
    let historical=CommandLine.arguments[1]=="historical"
    var steady=NativeRemoteFootAnimation.Snapshot();steady.movement=1;steady.velocity=SIMD3(0,1,0)
    // Independent canonical one-sixtieth updates, without the display adapter.
    let baseline=engine(library);_ = baseline.update(delta:0,nowMilliseconds:10000,snapshot:steady)
    var reference=SIMD2<Double>.zero
    for i in 1...120{reference+=baseline.update(delta:1/60,nowMilliseconds:10000+Double(i)*1000/60,snapshot:steady).travel}
    let low=try advance(DrawOwner(engine(library)),steady,[0.2])
    try near(low.0.y,reference.y,"elapsed root travel lost")
    try check(!historical,"historical cap unexpectedly passed")
    let schedules=[[1.0/15],[1.0/30],[1.0/60],[1.0/120],[0.2],[0.45,0.05],[0.017,0.031,0.009,0.043]]
    for i in 0..<14 {
        let style=NativeFootAnimationStyle(walk:"invented/walk\(i)",run:"invented/run\(i)",sprint:"invented/sprint\(i)")
        for movement in [1.0,2,3] {
            var state=steady;state.movement=movement
            // Warm the sprint blend so this assertion measures elapsed gait
            // phase/travel, separately from variable-step blend integration.
            func warmed()->DrawOwner {let e=engine(library,style);for _ in 0..<60{_ = e.update(delta:1/60,nowMilliseconds:9000,snapshot:state)};return DrawOwner(e)}
            let expected=try advance(warmed(),state,[1.0/60])
            for schedule in schedules {
                let result=try advance(warmed(),state,schedule)
                try near(result.0.y,expected.0.y,"steady gait travel",2e-6)
                try near(result.0.x,expected.0.x,"steady side travel")
                try check(result.1==expected.1,"step events lost or duplicated")
                try check(result.2.blends.count==expected.2.blends.count,"final pose roles")
                for (a,b) in zip(result.2.blends,expected.2.blends) {
                    try check(a.clip==b.clip,"final gait clip");try near(a.time,b.time,"final gait phase",2e-6)
                }
            }
        }
    }
    let owner=DrawOwner(engine(library));let first=owner.sample(100,true,steady)!
    try near(first.travel.y,0,"new owner inherited interval")
    _ = owner.sample(100.2,true,steady)
    for (time,active) in [(Double.nan,true),(101,false),(108,true),(107,true),(109,true),(109,true),(Double.greatestFiniteMagnitude,true)] {
        let frame=owner.sample(time,active,steady)!
        try near(frame.travel.y,0,"rejected/suspended elapsed replayed")
        try check(frame.steps.isEmpty && frame.shots.isEmpty && !frame.shot,"held transient repeated")
    }
    owner.reset();try near(owner.sample(109.2,true,steady)!.travel.y,0,"visibility reentry inherited time")
    try check(owner.sample(109.4,true,steady)!.travel.y>0,"reentry failed to resume")
    let replacement=DrawOwner(engine(library));try near(replacement.sample(109.4,true,steady)!.travel.y,0,"model owner inherited time")
    // The final observed endpoint is sampled in bounded segments: jetpack
    // velocity must not become one large impulse followed by eleven zeros.
    var flying=steady;flying.action=62;flying.movement=0;flying.velocity=SIMD3(0,2,0)
    let flyer=DrawOwner(engine(library));_ = flyer.sample(10,true,flying)
    flying.position=SIMD3(0,0.4,0)
    let flight=flyer.sample(10.2,true,flying)!.flight!
    try near(flight.velocity.y,2,"flight endpoint subdivision velocity")
    try check(flight.bend.x.isFinite && flight.bend.y.isFinite,"flight finite")
    var canopy=steady;canopy.action=54;canopy.movement=0
    let parachute=DrawOwner(engine(library));_ = parachute.sample(10,true,canopy)
    let opening=parachute.sample(10.2,true,canopy)!
    try check(opening.canopySamples.count==12,"canopy target sequence lost")
    var dispatch=CanopyDispatch(skeletalLibrary:library)
    dispatch.sample(opening.flight!,opening.canopySamples)
    let samples=opening.canopySamples.compactMap{$0}
    try check(dispatch.flightCanopyActor!.calls==samples.map(\.time),"canopy targets reordered or duplicated")
    var expectedCanopy=3.75,remaining=1.0
    for c in samples {expectedCanopy+=(c.time*c.time+c.pitch-expectedCanopy)*c.easing;remaining*=1-c.easing}
    try near(dispatch.flightCanopyPoses["remote"]!,expectedCanopy,"moving canopy target dispatch")
    let last=samples.last!
    var distinguishedMovingTarget=false
    for time in [10.4,10.6] {
        let later=parachute.sample(time,true,canopy)!,before=expectedCanopy
        dispatch.sample(later.flight!,later.canopySamples)
        var remaining=1.0
        for c in later.canopySamples.compactMap({$0}) {expectedCanopy+=(c.time*c.time+c.pitch-expectedCanopy)*c.easing;remaining*=1-c.easing}
        try near(dispatch.flightCanopyPoses["remote"]!,expectedCanopy,"later canopy target dispatch")
        let target=later.flight!.canopy!,collapsed=before+(target.time*target.time+target.pitch-before)*(1-remaining)
        if abs(collapsed-expectedCanopy)>1e-5 {distinguishedMovingTarget=true}
    }
    try check(distinguishedMovingTarget,"moving canopy fixture failed to reject collapsed final target")
    var landed=last;landed.landed=true
    dispatch.flightCanopyLanded["remote"]=4
    dispatch.sample(.init(canopy:landed),[nil,landed])
    try near(dispatch.flightCanopyLanded["remote"]!,7,"nil target failed to retire landed anchor")
    let heldCanopy=parachute.sample(11,false,canopy)!
    try check(heldCanopy.canopySamples.isEmpty && heldCanopy.flight!.canopy!.easing==0,"held canopy sequence replayed")
    // A current task edge is latched once; repeated substeps cannot restart it.
    let actor=DrawOwner(engine(library));_ = actor.sample(10,true,steady)
    var script=steady;script.script="ped/handsup/l/1";script.movement=0
    let action=actor.sample(10.2,true,script)!
    try check(actor.engine.animator.tagged==script.script,"script edge lost")
    try check(action.blends.contains{$0.clip=="ped/handsup" && $0.time>0.19},"script restarted each step")
    let weaponData=Data("""
        {"weapons":[{"id":501,"twin":false,"arm":true,"reloads":false,"through":false,
        "loop":{"start":0,"end":0.07,"fire":0.01,"every":0.1},
        "clips":{"fire":"invented/fire","aim":"invented/fire"}}]}
        """.utf8)
    var weapons=try NativeFootWeaponAnimation.load(data:weaponData)
    var twin=weapons[501]!;twin.id=502;twin.twin=true;twin.reloads=true;twin.clips?["reload"]="invented/reload";weapons[502]=twin
    var stream=weapons[501]!;stream.id=503;stream.continuous=true;weapons[503]=stream
    var armed=steady;armed.weapon=501;armed.aim=0;armed.shots=100;armed.movement=0
    let shooter=DrawOwner(engine(library,NativeFootAnimationStyle(),weapons))
    let initial=shooter.sample(10,true,armed)!
    try check(!initial.shot && initial.shots.isEmpty,"new owner replayed old shot counter")
    armed.shots=103
    let shotFrame=shooter.sample(10.5,true,armed)!
    try check(shotFrame.shot && !shotFrame.shots.isEmpty,"substep shots were discarded")
    try check(shotFrame.shots.count<=3,"snapshot counter invented shots")
    let held=shooter.sample(11,false,armed)!
    try check(!held.shot && held.shots.isEmpty,"suspension repeated shots")
    let resumed=shooter.sample(15,true,armed)!
    try check(!resumed.shot && resumed.shots.isEmpty,"resume replayed shots")
    for id in [501,502,503] {
        let direct=engine(library,NativeFootAnimationStyle(),weapons)
        let display=DrawOwner(engine(library,NativeFootAnimationStyle(),weapons))
        var state=armed;state.weapon=id;state.shots=0
        _ = direct.update(delta:0,nowMilliseconds:10000,snapshot:state);_ = display.sample(10,true,state)
        for segment in 1...4 {
            if segment==1 {state.shots=3}
            if segment==2 && id==502 {
                try check(direct.animator.reload()>0 && display.engine.animator.reload()>0,"authored twin reload unavailable")
            }
            if segment==3 {state.weapon=0}
            if segment==4 {state.weapon=id;state.shots=4}
            var expectedShots:[Bool]=[],expectedSteps:[String]=[],expectedTravel=SIMD2<Double>.zero
            var shot=false,left=false
            for step in 1...12 {
                let frame=direct.update(delta:1/60,nowMilliseconds:(10+Double(segment-1)*0.2+Double(step)/60)*1000,snapshot:state)
                expectedShots+=frame.shots;expectedSteps+=frame.steps;expectedTravel+=frame.travel
                if frame.shot {shot=true;left=frame.shotLeft}
            }
            let result=display.sample(10+Double(segment)*0.2,true,state)!
            try check(result.shots==expectedShots && result.shot==shot,"single/twin/stream shot sequence")
            if shot {try check(result.shotLeft==left,"last emitted hand lost")}
            try check(result.steps==expectedSteps,"weapon transition steps")
            try near(result.travel.y,expectedTravel.y,"weapon transition travel")
            try check(display.engine.animator.reloading==direct.animator.reloading,"reload/switch state")
        }
    }
    if CommandLine.arguments.count>2 {
        let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))
        guard let owned=NativeSkeletalAnimationLibrary(data:data)else{throw ClockFailure.failed("owned CLP decode")}
        let result=try advance(DrawOwner(engine(owned)),steady,[0.2])
        let control=try advance(DrawOwner(engine(owned)),steady,[1.0/60])
        try near(result.0.y,control.0.y,"owned gait elapsed",1e-5)
        try check(result.1==control.1,"owned step events")
        if CommandLine.arguments.count>3 {
            let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[3]))
            let definitions=try NativeFootAnimationDefinitions(data:data)
            let json=try JSONSerialization.jsonObject(with:data) as! [String:Any]
            var groups=Set<String>()
            for row in json["peds"] as! [[Any]] where row.count>=5 {
                guard let group=row[2] as? String,let model=row[0] as? String,groups.insert(group).inserted else{continue}
                let style=definitions.style(model:model,library:owned)
                for movement in [1.0,2,3] {
                    var state=steady;state.movement=movement
                    func warmed()->DrawOwner {let e=engine(owned,style);for _ in 0..<60{_ = e.update(delta:1/60,nowMilliseconds:9000,snapshot:state)};return DrawOwner(e)}
                    let expected=try advance(warmed(),state,[1.0/60])
                    for schedule in [[0.2],[1.0/15],[1.0/120],[0.45,0.05]] {
                        let result=try advance(warmed(),state,schedule)
                        try near(result.0.y,expected.0.y,"owned multi-style gait elapsed",2e-5)
                        try check(result.1==expected.1,"owned multi-style step events")
                    }
                }
            }
            try check(!groups.isEmpty,"owned style coverage absent")
        }
    }
    print("PASS \(checks) actual remote-foot clock checks; no GPU/live-world/retail claim")
} catch {print("FAIL \(checks) \(error)");exit(2)}
