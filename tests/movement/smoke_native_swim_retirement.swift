// SPDX-License-Identifier: AGPL-3.0-only
// Authored water queries/input isolate the actual renderer's exit boundary.
final class SwimRetirementHarness {
    let swimController=NativeSwimController(),headingContinuity=NativeHeadingContinuity()
    let sprintController=NativeSprintController(),personalFlight=NativePersonalFlightController()
    var stamina=NativeStamina(),character:NativeCharacterController?=NativeCharacterController()
    var footAnimator:NativeFootAnimation?,footAnimationFrame:NativeFootAnimation.Frame?
    var health=100,crouching=false,hasParachute=false
    var lastFootVelocity=SIMD3<Double>.zero
    var actorHeading:Float=0.7,heading:Float=2.4,swimHeadingTarget:Float=2.4,cameraPitch:Float=0.4
    var pendingSprintTap=true,pendingDive=true,pendingSwimJump=true
    var footAirTime=0.0,footAirFall=0.0,footAirFell=false,footJumped=false,footLaunchRemaining:Double?
    var footAirVelocity=SIMD2<Double>.zero,footDeathKind:String?
    var onParachuteUsed:(()->Void)?,onSplash:(()->Void)?,onReloadTaskCancelled:(()->Void)?
    var onLocalDamage:((Double,Int)->Void)?,depth:Double?
    func cancelFootAimForTask(){} // No new swim admission in this gate.
    func clearAction(){} // No new swim admission in this gate.
    func waterSurface(at feet:SIMD3<Float>)->(height:Float,normal:SIMD3<Float>)? {
        depth.map{(feet.z+Float($0),SIMD3<Float>(0,0,1))}
    }
    func swimmingLedge(feet:SIMD3<Double>,heading:Double,surface:Double)->SIMD3<Double>? {nil}
    func run(_ delta:Double,_ state:NativeCharacterController.Output,_ intent:NativeCharacterController.Motion)->NativeCharacterController.Motion {
        swimmingMotion(delta:delta,state:state,intended:intent,push:1,running:true)
    }
    // ACTUAL_SWIMMING_MOTION
}

do {
    let library=try fixture(),state=NativeCharacterController.Output(feet:SIMD3(10,20,30),grounded:false,rising:-2,eased:0,propped:false,pressed:[])
    var intent=NativeCharacterController.Motion(displacement:SIMD3(0.02,0.03,0.04))
    intent.jump=6.07;intent.verticalOverride = -1.25
    for dt in [1.0/15,1.0/30,1.0/60,1.0/120,0.011,0.029,0.017,0.023] {
        for facing:Float in [0.7,3.13,-3.13] {
            for afloat in [false,true] {
                let h=SwimRetirementHarness();h.actorHeading=facing;h.character!.supportAfloat=afloat
                h.depth=afloat ? 2:nil
                h.swimController.enter(velocity:SIMD3(1,2,3),rising:-2,depth:2)
                h.headingContinuity.external(.swimming)
                _=h.stamina.take(150);let stamina=h.stamina.value,breath=h.swimController.breath
                h.footAnimator=NativeFootAnimation(library:library,random:{0.193})
                let before=h.footAnimator!.update(delta:0,input:.init())
                let value=h.run(dt,state,intent)
                try check(!h.swimController.on,"missing water failed to retire")
                try check(h.actorHeading==facing,"retired swim wrote facing before foot control")
                try near(h.stamina.value,stamina,"retired swim spent/recovered stamina")
                try check(h.sprintController.counter==0 && h.pendingSprintTap,"retired swim consumed the succeeding foot sprint tap")
                try check(!h.pendingDive && !h.pendingSwimJump,"retired water pulses escaped into the next owner")
                try check(h.swimController.breath==breath,"retirement invented an ashore oxygen tick")
                try check(value.displacement==intent.displacement && value.jump==intent.jump && value.verticalOverride==intent.verticalOverride && value.heldFeet==nil,"retirement changed the succeeding owner's motion")
                try check(h.footAnimationFrame==nil,"retiring swim advanced an animation frame")
                let after=h.footAnimator!.update(delta:0,input:.init())
                try check(zip(before.blends,after.blends).allSatisfy{$0.clip==$1.clip && $0.time==$1.time && $0.weight==$1.weight},"retiring swim changed animation clocks")
                // Current foot input can run immediately; no forced idle tick
                // or browser-derived input delay is introduced by retirement.
                let foot=NativeFootLocomotion()
                try check(h.headingContinuity.resumeFoot(facing:Double(h.actorHeading),locomotion:foot),"final swim facing did not hand off")
                var input=NativeFootLocomotion.Input();input.stick=SIMD2(0,1);input.cameraHeading=Double(h.heading)
                let moved=foot.update(delta:dt,input:input)
                try check(moved.ratio>0,"fresh foot movement was delayed")
                _=h.sprintController.control(.forMode(.foot),ticks:50*dt,tapped:h.pendingSprintTap,held:true,staminaLeft:h.stamina.left,take:{h.stamina.take($0)})
                try check(h.sprintController.counter==4,"fresh foot sprint did not receive its tap")
                cases+=1
            }
        }
    }
    // The new early boundary cannot cut across an animation-owned haul.
    for dt in [1.0/15,1.0/30,1.0/60,1.0/120] {
        let c=NativeSwimController();c.enter(velocity:.zero,rising:0,depth:2)
        _=c.step(delta:dt,depth:2,feet:SIMD3(10,29,20),jump:true,ledge:{SIMD3(10,32,20)})
        let held=c.hauled;try check(held != nil,"haul fixture did not acquire root")
        try check(!c.completeIfWaterMissing(delta:dt,depth:nil) && c.on && c.hauled==held,"missing query canceled a held haul")
        let value=c.step(delta:dt,depth:nil)
        try check(value != nil && c.on && c.hauled != held,"held haul clock did not continue without water query")
        cases+=1
    }
    let c=NativeSwimController();c.enter(velocity:.zero,rising:0,depth:2)
    for dt in [0.0,-1,Double.nan,Double.infinity] {
        try check(!c.completeIfWaterMissing(delta:dt,depth:nil) && c.on,"invalid clock retired movement owner")
    }
    for depth in [2.0,1.0,-0.1,Double.nan] {
        try check(!c.completeIfWaterMissing(delta:1/60,depth:depth) && c.on,"nonmissing query acquired early completion")
    }
    try check(c.completeIfWaterMissing(delta:1/60,depth:nil) && !c.on,"certain completion missing")
    try check(!c.completeIfWaterMissing(delta:1/60,depth:nil),"retirement fired twice")
    print("PASS swim retirement: \(checks) checks, \(cases) boundary/haul cases; authored environment and actual renderer/controller; no retail/GPU claim")
} catch {print("FAIL swim retirement after \(checks): \(error)");exit(2)}
