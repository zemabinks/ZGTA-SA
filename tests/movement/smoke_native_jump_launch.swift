// SPDX-License-Identifier: AGPL-3.0-only
// The driver includes the authored CLP helpers from the landing gate, then
// compiles this against the actual animation implementation.

func seeded(_ library:NativeSkeletalAnimationLibrary,_ phase:Double,_ style:NativeFootAnimationStyle=NativeFootAnimationStyle())->NativeFootAnimation{
    NativeFootAnimation(library:library,style:style,random:{phase})
}
func selected(_ e:NativeFootAnimation,_ input:NativeFootAnimation.Input)throws->String{
    try near(e.launch(),0.2,"launch delay changed",1e-6)
    let f=e.update(delta:0.01,input:input)
    let names=Set(["ped/jump_launch","ped/jump_launch_r"])
    guard let blend=f.blends.first(where:{names.contains($0.clip) && $0.weight>0})else{throw LandingFailure.failed("missing launch pose")}
    return blend.clip
}
do{
    let l=try fixture()
    // With no active gait association, a randomized initialization phase does
    // not supply a foot choice. Include both a cold owner and evaluated idle.
    for phase in [0.8,0.501,0.999,0.193,0.0]{
        for cold in [true,false]{
            let e=seeded(l,phase);let input=NativeFootAnimation.Input()
            if !cold{_ = e.update(delta:0,input:input)}
            try check(try selected(e,input)=="ped/jump_launch","idle launch used a randomized gait phase")
            cases+=1
        }
    }
    let phases:[(Double,Bool)]=[(0,false),(0.132,false),(0.1329999,false),(0.133,true),
        (0.193,true),(0.49,true),(0.5,true),(0.6329,true),(0.633,true),(0.6331,false),(0.8,false),(0.999,false)]
    for (phase,right) in phases{
        for ratio in [0.7,1.6,2.0]{
            let e=seeded(l,phase);var input=NativeFootAnimation.Input();input.ratio=ratio
            _ = e.update(delta:0,input:input)
            try check(try selected(e,input)==(right ? "ped/jump_launch_r":"ped/jump_launch"),"active gait launch phase/strict wrap")
            cases+=1
        }
    }
    // Float association thresholds have distinct selection and acceptance
    // comparisons. Exactly-threshold priority does not fall through to a
    // lower-priority gait with a larger weight.
    for (ratio,right) in [(0.3,false),(0.30001,true),(1.3,false),(1.29999,true),(1.30001,true)]{
        let e=seeded(l,0.193);var input=NativeFootAnimation.Input();input.ratio=ratio
        _ = e.update(delta:0,input:input)
        try check(try selected(e,input)==(right ? "ped/jump_launch_r":"ped/jump_launch"),"walk/run blend threshold")
        cases+=1
    }
    for (warm,right) in [(0.05998,true),(0.06,false),(0.06002,true)]{
        let e=seeded(l,0.193);var input=NativeFootAnimation.Input();input.ratio=2;input.sprint=true
        let f=e.update(delta:warm,input:input)
        try check(try gait(f,e,l)>0.133 && gait(f,e,l)<0.633,"authored threshold phase control")
        try check(try selected(e,input)==(right ? "ped/jump_launch_r":"ped/jump_launch"),"sprint priority blend threshold")
        cases+=1
    }
    var sharedStyle=NativeFootAnimationStyle();sharedStyle.sprint=sharedStyle.run
    for (warm,right) in [(0.05998,true),(0.06,false),(0.06002,true)]{
        let e=seeded(l,0.193,sharedStyle);var input=NativeFootAnimation.Input();input.ratio=2;input.sprint=true
        _ = e.update(delta:warm,input:input)
        try check(try selected(e,input)==(right ? "ped/jump_launch_r":"ped/jump_launch"),"shared clip collapsed distinct gait association weights")
        cases+=1
    }
    var missing=NativeFootAnimationStyle();missing.walk="invented/missing-walk";missing.run="invented/missing-run";missing.sprint="invented/missing-sprint"
    let absent=seeded(l,0.8,missing);var moving=NativeFootAnimation.Input();moving.ratio=2
    _ = absent.update(delta:0,input:moving)
    try check(try selected(absent,moving)=="ped/jump_launch","missing gait manufactured active association")
    let stale=seeded(l,0.193);var active=NativeFootAnimation.Input();active.ratio=0.7
    _ = stale.update(delta:0,input:active)
    try check(try selected(stale,active)=="ped/jump_launch_r","active association setup")
    stale.cancelQueuedLaunch();active.ratio=0
    _ = stale.update(delta:0,input:active)
    try check(try selected(stale,active)=="ped/jump_launch","idle retained obsolete gait association weight")
    let changed=seeded(l,0.193);active.ratio=0.7
    _ = changed.update(delta:0,input:active)
    changed.setModelStyle(missing)
    _ = changed.update(delta:0,input:active)
    try check(try selected(changed,active)=="ped/jump_launch","skin replacement retained unavailable gait associations")
    cases+=2
    for schedule in [[1.0/15],[1.0/30],[1.0/60],[1.0/120],[0.011,0.029,0.017,0.023]]{
        let e=seeded(l,0.193);var input=NativeFootAnimation.Input();input.ratio=0.7
        var time=0.0,index=0
        while time<0.2-1e-10{let dt=min(schedule[index%schedule.count],0.2-time);_ = e.update(delta:dt,input:input);time+=dt;index+=1}
        try check(try selected(e,input)=="ped/jump_launch_r","matching elapsed gait changed launch foot across frame rates")
        cases+=1
    }
    // Replacing a landing with a jump removes the old landing owner. Finishing
    // that launch must not inherit its gait-restart capability.
    let interrupted=seeded(l,0.193);var input=NativeFootAnimation.Input();input.ratio=0.7;input.land="fallLand"
    _ = interrupted.update(delta:0.013,input:input);input.land=nil
    _ = try selected(interrupted,input)
    var completed=false
    for _ in 0..<100{
        _ = interrupted.update(delta:0.013,input:input)
        if !interrupted.gateHasMovementAction{
            try check(try gait(interrupted.update(delta:0,input:input),interrupted,l)>0.0001,"launch inherited interrupted landing restart")
            completed=true;break
        }
    }
    try check(completed,"interrupted landing launch never completed")
    print("PASS jump launch: \(checks) checks, \(cases) authored cases; no rendered/retail claim")
}catch{print("FAIL jump launch after \(checks): \(error)");exit(2)}
