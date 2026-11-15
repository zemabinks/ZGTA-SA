import Foundation
import simd

@main enum HeadingTransitionSmoke {
    static func degrees(_ radians:Double)->Double{radians*180/Double.pi}
    static func distance(_ a:Double,_ b:Double)->Double{abs(NativeHeadingContinuity.difference(a,from:b))}
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        var report:[[String:Any]]=[],checks=0,largestBefore=0.0,largestAfter=0.0,frames=0
        for hz in [30,60,120] {
            for start in [0.0,Double.pi/2,359*Double.pi/180,-179*Double.pi/180] {
                let foot=NativeFootLocomotion(),flight=NativePersonalFlightController(),handoff=NativeHeadingContinuity()
                foot.reset(heading:start);flight.wear(true);flight.takeOff(heading:-start)
                handoff.external(.jetpack)
                let target=start+Double.pi
                var actor=start,accumulator=0.0,ticks=0
                for _ in 0..<hz*3 {
                    accumulator += 1/Double(hz)
                    while accumulator+1e-12>=1/60 {
                        accumulator -= 1/60;ticks += 1
                        flight.steer()
                        let result=flight.step(delta:1/60,grounded:false,heading:-target,height:30)
                        precondition(result != nil);actor = -flight.heading;frames += 1
                    }
                }
                precondition(ticks==180)
                let beforeTouchdown=actor,cached=foot.heading
                flight.steer(down:true)
                let touchdown=flight.step(delta:1/60,grounded:true,heading:-target,height:0)
                precondition(touchdown==nil && !flight.flying)
                // Baseline75 returns before copying the final controller
                // facing, then lets this suspended cache become authoritative.
                let baseline=foot.update(delta:1/60,input:.init()).heading
                let before=distance(baseline,beforeTouchdown)
                largestBefore=max(largestBefore,before);precondition(before>3.13)
                // Proposed integration publishes the final physical heading
                // even when motion is nil, then performs the explicit handoff.
                actor = -flight.heading
                precondition(handoff.resumeFoot(facing:actor,locomotion:foot))
                let resumed=foot.update(delta:1/60,input:.init())
                let after=distance(resumed.heading,actor)
                largestAfter=max(largestAfter,after)
                precondition(after<1e-12 && resumed.ratio==0)
                precondition(!handoff.resumeFoot(facing:actor+1,locomotion:foot))
                report.append(["case":"jetpack-touchdown","hz":hz,"startDegrees":degrees(start),"cachedDegrees":degrees(cached),"beforeLandingDegrees":degrees(beforeTouchdown),"baselineSnapDegrees":degrees(before),"fixedSnapDegrees":degrees(after),"physicsTicks":ticks])
                checks += 7
            }
        }
        // Other movement owners and explicit camera/input cases use the same
        // handoff. A new command may turn the player; an old cache may not.
        for hz in [30,60,120] {for owner in [NativeHeadingContinuity.Owner.jetpack,.parachute,.swimming] {
            for angle in [-Double.pi,-0.001,0,0.001,Double.pi,359*Double.pi/180] {
                for stick in [SIMD2<Double>.zero,SIMD2(0,1),SIMD2(0,-1)] {
                    for aiming in [false,true] {
                        let foot=NativeFootLocomotion(),handoff=NativeHeadingContinuity()
                        foot.reset(heading:angle+Double.pi)
                        var old=NativeFootLocomotion.Input();old.stick=SIMD2(1,0);old.cameraHeading=angle+Double.pi
                        for _ in 0..<60{_ = foot.update(delta:1/60,input:old)}
                        handoff.external(owner)
                        precondition(handoff.resumeFoot(facing:angle,locomotion:foot))
                        precondition(distance(foot.heading,angle)<1e-12 && foot.requestedMovementRatio==0)
                        var input=NativeFootLocomotion.Input();input.stick=stick;input.cameraHeading=angle
                        input.aiming=aiming;input.gunUp=aiming
                        let first=foot.update(delta:1/Double(hz),input:input)
                        if stick == .zero{precondition(distance(first.heading,angle)<1e-12 && first.ratio==0)}
                        else if aiming{precondition(distance(first.heading,angle)<1e-12)}
                        else{precondition(distance(first.heading,angle)<=input.turningRate/Double(hz)+1e-12)}
                        checks += 3;frames += 1
                    }
                }
            }
        }}
        // Canonical wrap must describe the same facing, including large and
        // negative multiples, and external->external ownership must not flip it.
        for i in -720...720 {
            let angle=Double(i)*Double.pi/180,wrapped=NativeHeadingContinuity.canonical(angle)
            precondition(distance(angle,wrapped)<1e-12)
            precondition(abs(NativeHeadingContinuity.difference(angle+0.01,from:angle))<0.010000000001)
            checks += 2
        }
        for camera in [0.0,Double.pi/2,-Double.pi,359*Double.pi/180] {
            for stick in [SIMD2<Double>(0,1),SIMD2(1,0),SIMD2(0,-1),SIMD2(-1,0),SIMD2(1,1),SIMD2(-1,-1)] {
                let facing=NativeHeadingContinuity.inputFacing(camera:camera,sideways:stick.x,forward:stick.y)
                let travel=NativeFootLocomotion.worldTravel(stick,heading:camera)
                let direction=atan2(Double(travel.x),Double(travel.y))
                precondition(distance(facing,direction)<1e-6);checks += 1
            }
        }
        var floatBoundary=0.0
        for a in [-180.0,-179.99,-1,0,1,179.99,180,359,360,720] {
            let value=Double(Float(a*Double.pi/180)),foot=NativeFootLocomotion(),handoff=NativeHeadingContinuity()
            handoff.external(.swimming);_ = handoff.resumeFoot(facing:value,locomotion:foot)
            let error=distance(Double(Float(foot.heading)),value);floatBoundary=max(floatBoundary,error)
            precondition(error<0.000001);checks += 1
        }
        for (actor,camera,expected) in [(179.0,-179.0,-2.0),(-179,179,2),(359,1,-2),(1,359,2)] {
            let yaw=NativeHeadingContinuity.difference(actor*Double.pi/180,from:camera*Double.pi/180)
            precondition(abs(degrees(yaw)-expected)<1e-10);checks += 1
        }
        let output:[String:Any] = ["maximumFloatBoundaryDegrees":degrees(floatBoundary),"baseline":"75/482af7d","scenarios":report,"checks":checks,"frames":frames,"baselineMaximumSnapDegrees":degrees(largestBefore),"fixedMaximumSnapDegrees":degrees(largestAfter),"reference":"Current native baseline reproduction; continuity invariants, not a verified retail capture"]
        let destination=root.appendingPathComponent("local-only/research/heading-transitions.json")
        try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
        try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]).write(to:destination)
        print("PASS: stale-flight heading reproduced at",degrees(largestBefore),"degrees; fixed",degrees(largestAfter),"degrees;",checks,"checks across30/60/120Hz")
    }
}
