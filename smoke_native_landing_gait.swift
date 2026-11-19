// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import simd
import Darwin

enum LandingFailure:Error {case failed(String)}
var checks=0,cases=0
func check(_ condition:Bool,_ message:String)throws{checks+=1;if !condition{throw LandingFailure.failed(message)}}
func near(_ a:Double,_ b:Double,_ message:String,_ tolerance:Double=1e-7)throws{try check(a.isFinite && b.isFinite && abs(a-b)<tolerance,message)}
func word(_ n:UInt32,_ data:inout Data){var n=n.littleEndian;withUnsafeBytes(of:&n){data.append(contentsOf:$0)}}
func number(_ n:Float,_ data:inout Data){word(n.bitPattern,&data)}
func string(_ s:String,_ data:inout Data){var n=UInt16(s.utf8.count).littleEndian;withUnsafeBytes(of:&n){data.append(contentsOf:$0)};data.append(contentsOf:s.utf8)}
func fixture(_ omitLanding:Bool=false)throws->NativeSkeletalAnimationLibrary{
    var clips:[(String,Float,Float)]=[("idle_stance",1.7,0),("walk_player",0.73,0.68),("run_player",0.55,1.63),("sprint_civi",0.48,2.17),
        ("walk_armed",0.63,0.7),("run_armed",0.51,1.72),("idle_armed",1.5,0),
        ("run_stop",0.42,0.2),("run_stopr",0.44,0.22),("gunmove_fwd",0.58,0.8),
        ("gunmove_bwd",0.61,0.7),("gunmove_l",0.57,0.6),("gunmove_r",0.59,0.65),
        ("weapon_crouch",0.8,0),("guncrouchfwd",0.67,0.55),("guncrouchbwd",0.68,0.55),
        ("crouch_roll_l",0.57,0.3),("crouch_roll_r",0.57,0.3),("ko_shot_front",0.79,0.25),
        ("ko_skid_front",0.7,0.3),("ko_skid_back",0.7,0.3),("getup",0.82,0.1),
        ("jump_launch",0.2,0),("jump_launch_r",0.2,0),("jump_glide",0.6,0),("fall_fall",0.6,0),("handsup",1.1,0)]
    if !omitLanding{clips += [("jump_land",0.62,0.17),("fall_land",0.71,0.13),("fall_collapse",0.87,0.22)]}
    var data=Data();[UInt32(0x31504c43),UInt32(clips.count),0,1].forEach{word($0,&data)}
    for (name,length,travel) in clips{
        string("ped/"+name,&data);number(length,&data);word(1,&data);word(0,&data);word(2,&data);word(1,&data)
        for (at,position) in [(Float(0),Float(0)),(length,travel)]{number(at,&data);[Float(0),0,0,1,0,position,0].forEach{number($0,&data)}}
    }
    guard let library=NativeSkeletalAnimationLibrary(data:data)else{throw LandingFailure.failed("authored CLP decoder")};return library
}
func engine(_ library:NativeSkeletalAnimationLibrary,_ style:NativeFootAnimationStyle=NativeFootAnimationStyle())->NativeFootAnimation{NativeFootAnimation(library:library,style:style,random:{0.193})}
func gait(_ frame:NativeFootAnimation.Frame,_ e:NativeFootAnimation,_ library:NativeSkeletalAnimationLibrary)throws->Double{
    let names=Set([e.style.walk,e.style.run,e.style.sprint])
    guard let b=frame.blends.first(where:{names.contains($0.clip) && $0.weight>0.001})else{throw LandingFailure.failed("missing active gait")}
    guard let length=library.duration(of:b.clip),length>0 else{throw LandingFailure.failed("invalid active gait duration")}
    return b.time/length
}
let kinds=[("land","ped/jump_land"),("fallLand","ped/fall_land"),("collapse","ped/fall_collapse")]
func ordinary(_ library:NativeSkeletalAnimationLibrary,_ kind:String,_ clip:String,_ ratio:Double,_ sprint:Bool,_ schedule:[Double],_ shared:Bool=false)throws{
    var style=NativeFootAnimationStyle();if shared{style.sprint=style.run}
    let e=engine(library,style);var input=NativeFootAnimation.Input();input.ratio=ratio;input.sprint=sprint
    for _ in 0..<29{_ = e.update(delta:1/60,input:input)}
    input.land=kind
    let first=e.update(delta:1/60,input:input);input.land=nil
    try check(first.blends.contains{$0.clip==clip},"landing did not acquire its animation")
    let frozen=try gait(first,e,library)
    for _ in 0..<5{
        let f=e.update(delta:0,input:input)
        try near(try gait(f,e,library),frozen,"zero-time landing moved gait")
        try near(f.travel.y,0,"zero-time landing moved root");try check(f.steps.isEmpty,"zero-time landing emitted step")
    }
    var last=first,finished=false
    for i in 0..<1000{
        let dt=schedule[i%schedule.count],f=e.update(delta:dt,input:input)
        try check(f.travel.x.isFinite && f.travel.y.isFinite,"nonfinite landing travel")
        try check(f.travel.y >= -1e-6 && f.travel.y <= dt*12+1e-5,"landing reset fabricated backwards/cycle root displacement")
        if !f.blends.contains(where:{$0.clip==clip}){
            // The retiring frame already integrated its old before/after
            // samples. Observe the new stored clock without adding time.
            let atBoundary=e.update(delta:0,input:input)
            try near(try gait(atBoundary,e,library),0,"completed landing retained gait phase")
            for b in atBoundary.blends where Set([e.style.walk,e.style.run,e.style.sprint]).contains(b.clip){try near(b.time,0,"only one gait association restarted")}
            try near(atBoundary.travel.y,0,"restart emitted motion without time")
            let resumed=e.update(delta:0.013,input:input)
            try check(try gait(resumed,e,library)>0,"completed landing kept resetting gait")
            try check(resumed.travel.y>=0 && resumed.travel.y<0.16,"restart produced a full root cycle")
            finished=true;break
        }
        last=f
    }
    _=last;try check(finished,"landing never completed");cases+=1
}
func exclusions(_ library:NativeSkeletalAnimationLibrary)throws{
    var input=NativeFootAnimation.Input();input.ratio=1
    for action in ["abort","replace","death"]{
        let e=engine(library);for _ in 0..<23{_ = e.update(delta:1/60,input:input)}
        input.land="fallLand";_ = e.update(delta:0.03,input:input);input.land=nil
        let before=try gait(e.update(delta:0,input:input),e,library)
        if action=="abort"{e.resetMovementTask()}else if action=="replace"{try check(e.roll(1),"roll replacement")}else{e.die()}
        let after=e.update(delta:0,input:input)
        try near(try gait(after,e,library),before,"interrupted landing acquired completion reset")
        if action=="replace"{
            var ended=false
            for _ in 0..<150{let f=e.update(delta:0.013,input:input);if !f.blends.contains(where:{$0.clip=="ped/crouch_roll_r"}){try check(try gait(e.update(delta:0,input:input),e,library)>0.0001,"replacement action inherited landing completion");ended=true;break}}
            try check(ended,"roll replacement never retired")
        }
    }
    let e=engine(try fixture(true));let l=try fixture(true)
    _ = e.update(delta:0.137,input:input);let before=try gait(e.update(delta:0,input:input),e,l)
    input.land="land";_ = e.update(delta:0,input:input);input.land=nil
    try near(try gait(e.update(delta:0,input:input),e,l),before,"missing landing clip reset gait")
    // The same physical knock path has its own get-up owner. It must not gain
    // the ordinary landing's restart just because clips share a name family.
    let knocked=engine(library);try check(knocked.knock("koSkidFront"),"knock action")
    for _ in 0..<180{_ = knocked.update(delta:0.013,input:input)}
    try check(try gait(knocked.update(delta:0,input:input),knocked,library)>0.0001,"knock/get-up acquired ordinary landing reset")
}
do{
    let library=try fixture()
    for (kind,clip) in kinds{for ratio in [0.7,1.4,2.0]{for sprint in [false,true]{for schedule in [[1.0/15],[1.0/30],[1.0/60],[1.0/120],[0.009,0.031,0.017,0.023]]{try ordinary(library,kind,clip,ratio,sprint,schedule)}}}}
    for (kind,clip) in kinds{try ordinary(library,kind,clip,2,true,[1.0/60],true)}
    try exclusions(library)
    var ownedCases=0
    if CommandLine.arguments.count>1{
        let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]));guard let original=NativeSkeletalAnimationLibrary(data:data)else{throw LandingFailure.failed("owned CLP decode")}
        for (kind,clip) in kinds where original.contains(clip){try ordinary(original,kind,clip,1.4,false,[1.0/60]);ownedCases+=1}
    }
    print("PASS landing gait: \(checks) checks, \(cases) completion cases, \(ownedCases) optional owned CPU cases; no rendered/retail claim")
}catch{print("FAIL landing gait after \(checks): \(error)");exit(2)}
