// Receives current Renderer methods, real CLP animation and native Rapier.
// Water planes and pre-flight walking intent are controlled test fixtures.
import Foundation
import simd

final class FixedVelocityHarness {
    let character: NativeCharacterController?
    let personalFlight = NativePersonalFlightController(), swimController = NativeSwimController()
    let headingContinuity = NativeHeadingContinuity(), locomotion = NativeFootLocomotion()
    let sprintController = NativeSprintController()
    var stamina = NativeStamina(), footAnimator: NativeFootAnimation?
    var footWeaponDefinitions: [Int:NativeFootWeaponAnimation] = [:]
    var footAnimationFrame: NativeFootAnimation.Frame?
    var health=100,driving=false,crouching=false,hasParachute=false,aiming=false,weaponTriggerHeld=false,weaponReady=true
    var originalCoughing=false
    var onLocalDamage:((Double,Int)->Void)?
    var weaponReloading=false,climb:Int?
    var onReloadTaskCancelled:(()->Void)?,onFootAimCancelled:(()->Void)?
    var verticalSpeed:Float=0
    var swimming:Bool {swimController.on}
    var equippedWeapon=0,personalFlightDown=false,personalFlightBrake=false,pendingParachuteOpen=false
    var pendingSprintTap=false,pendingDive=false,pendingSwimJump=false
    var acceptedStreamShot=false,pendingNativeJump=0.0
    var pendingClimbPull=false,pendingClimbDrop=false,jumpHeld=false,walkHeld=false,sprintWasHeld=false,vehicleHop=false
    var vehicleWorkingControl:Float=0
    final class OtherVehicleInput {func cancelPendingInput(){}}
    var groundVehicle:OtherVehicleInput?
    var actorHeading:Float=3.13,heading:Float=3.13,cameraPitch:Float=0,swimHeadingTarget:Float=3.13
    var footAirTime=0.0,footAirFall=0.0,footAirFell=false,footJumped=false,footLaunchRemaining:Double?
    var footDeathKind:String?
    var footAirVelocity=SIMD2<Double>.zero,lastFootVelocity=SIMD3<Double>.zero
    var onLocalHealth:((Int)->Void)?,onParachuteUsed:(()->Void)?,onSplash:(()->Void)?
    var ticks=0,water=false,waterEdge:Float=1481,events:[[String:Any]]=[]
    var traces:[[Double]]=[],poses:[[String:Any]]=[],mode="",landed=false
    var samples:[Double]=[]
    var currentFootVelocity:SIMD3<Double> { character?.currentVelocity ?? lastFootVelocity }
    let startX:Float=1480
    func clearAction(){footAnimator?.rest()}
    func cancelWeaponInput(){weaponTriggerHeld=false;footAnimator?.cancelInput()}
    func cancelCameraInput(){} // Camera owner is covered by the controls gate.
    func emitFootWeaponEvents(_ frame:NativeFootAnimation.Frame,feet:SIMD3<Float>){precondition(frame.shots.isEmpty)}
    func waterSurface(at point:SIMD3<Float>)->(height:Float,normal:SIMD3<Float>)? {
        water && point.x>=waterEdge ? (102,SIMD3(0,0,1)):nil
    }
    func swimmingLedge(feet:SIMD3<Double>,heading:Double,surface:Double)->SIMD3<Double>? {nil}

    init(library:NativeSkeletalAnimationLibrary,mode:String) {
        self.mode=mode
        let world=SwiftRapierWorld()!
        if mode=="jetpack" || mode=="wall" {
            let floor=world.addBox(halfExtents:SIMD3(100,0.1,100),position:SIMD3(startX,-0.1,0))!
            world.setColliderGroups(floor,collision:0x0087ffff,solver:0xffffffff)
            world.setColliderQueryMetadata(floor,surface:2,material:0)
        }
        if mode=="wall" {
            let wall=world.addBox(halfExtents:SIMD3(0.1,5,10),position:SIMD3(startX+1.5,5,0))!
            world.setColliderGroups(wall,collision:0x0087ffff,solver:0xffffffff)
        }
        world.step()
        character=NativeCharacterController(world:world)!
        character!.reset(feet:SIMD3(startX,0,mode=="jetpack" || mode=="wall" ? 0:100),grounded:mode=="jetpack" || mode=="wall")
        footAnimator=NativeFootAnimation(library:library,random:{0.37})
        hasParachute=mode=="parachute";water=mode=="water"
        if mode=="jetpack" {personalFlight.wear(true)}
        locomotion.reset(heading:Double(actorHeading))
    }

    func publish(start:SIMD3<Float>,camera:SIMD3<Float>,delta:Float) {
        // ACTUAL_PUBLISH
    }
    func motion(delta step:Double,state:NativeCharacterController.Output,intended:NativeCharacterController.Motion)->NativeCharacterController.Motion {
        let character=self.character!
        // ACTUAL_MOTION_BOUNDARY
        ticks += 1
        let running=mode=="jetpack" && ticks<80
        if mode=="jetpack" && ticks==100 {heading = -3.12}
        if mode=="parachute" && ticks==45 {pendingParachuteOpen=true}
        let wasSwimming=swimController.on,wasFlight=personalFlight.on
        if water,!wasSwimming,swimController.enters(waterSurface(at:state.feet).map{Double($0.height-state.feet.z)}) {
            events.append(["kind":"water","tick":ticks,"inheritedX":lastFootVelocity.x])
        }
        if hasParachute,!personalFlight.on,personalFlight.dives(rising:state.rising,height:nil) {
            events.append(["kind":"parachute","tick":ticks,"inheritedX":lastFootVelocity.x])
        }
        let wet=swimmingMotion(delta:step,state:state,intended:intended,push:0,running:false)
        var result=wet
        if !swimController.on {
            if let flying=personalFlightMotion(delta:step,state:state,intended:wet,forward:0,sideways:0,running:running) {result=flying}
            else {
                headingContinuity.resumeFoot(facing:Double(actorHeading),locomotion:locomotion)
                actorHeading=Float(locomotion.update(delta:step,input:.init()).heading)
                result.displacement=SIMD3(Float(2*step),0,0)
                footAnimationFrame=footAnimator!.update(delta:step,input:.init(ratio:1))
            }
        }
        if wasFlight && !personalFlight.on {
            events.append(["kind":"land","tick":ticks,"heading":Double(actorHeading)]);landed=true
        }
        let pose=footAnimationFrame!.blends
        poses.append(["clips":pose.map(\.clip),"values":pose.flatMap{[$0.time,$0.weight]}])
        traces.append([Double(state.feet.x),Double(state.feet.y),Double(state.feet.z),state.rising,
                       Double(actorHeading),Double(personalFlight.state),Double(swimController.state.rawValue),
                       result.displacement.x.double,result.displacement.y.double,result.displacement.z.double])
        return result
    }
    // ACTUAL_HANDOFFS
}

private extension Float {var double:Double {Double(self)}}

@main enum Gate {
    static func main() throws {
        let root=URL(fileURLWithPath:CommandLine.arguments[1])
        let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/models/animations.clips.bin")))!
        var checks=0,records:[[String:Any]]=[]
        func check(_ value:Bool,_ message:String){checks += 1;precondition(value,message)}
        for mode in ["parachute","water","jetpack","wall"] {
            var reference:FixedVelocityHarness?
            for rate in [30,60,120,0] {
                let harness=FixedVelocityHarness(library:library,mode:mode)
                var clock=NativeGameFrameClock(),now=0.0,frames=0
                let target=mode=="jetpack" ? 600:240
                while harness.ticks<target {
                    let frame=clock.advance(timestamp:now,active:true)
                    for step in frame.steps {
                        let delta=Float(step),start=harness.character!.state.feet
                        let state=harness.character!.update(delta:Double(delta),displacement:.zero,geometryReady:true,motion:harness.motion)
                        harness.publish(start:start,camera:state.feet,delta:delta)
                        if harness.ticks>2 && harness.events.isEmpty && mode != "jetpack" {harness.samples.append(harness.lastFootVelocity.x)}
                    }
                    now += rate>0 ? 1/Double(rate):[1.0/144,1.0/90,1.0/42,1.0/120,1.0/30][frames%5]
                    frames += 1
                    check(frames<5000,"Cadence fixture stalled")
                }
                if let reference {
                    for tick in 0..<target {
                        for (a,b) in zip(harness.traces[tick],reference.traces[tick]) {check(abs(a-b)<1e-9,"\(mode)/\(rate)/tick\(tick) changed a fixed task/body trace")}
                        check((harness.poses[tick]["clips"] as! [String]) == (reference.poses[tick]["clips"] as! [String]),"Cadence changed an original animation clip")
                        for (a,b) in zip(harness.poses[tick]["values"] as! [Double],reference.poses[tick]["values"] as! [Double]) {check(abs(a-b)<1e-9,"Cadence changed an original animation time/weight")}
                    }
                } else {reference=harness}
                if mode=="water" || mode=="parachute" {
                    let entry=harness.events.first!
                    check(abs((entry["inheritedX"] as! Double)-2)<Double(harness.startX.ulp)*60+0.00001,"\(mode) lost/multiplied inherited horizontal velocity")
                    check(harness.samples.allSatisfy{abs($0-2)<Double(harness.startX.ulp)*60+0.00001},"No-tick display frame erased or doubled committed velocity")
                }
                if mode=="jetpack" {check(harness.landed,"Jetpack did not complete a real native-floor touchdown")}
                if mode=="wall" {
                    check(harness.character!.state.feet.x<harness.startX+1.5,"Controlled wall failed to block the motor")
                    check(abs(harness.lastFootVelocity.x)<Double(harness.startX.ulp)*120+0.00001,
                          "Blocked motor exported intended rather than committed movement: \(harness.lastFootVelocity.x)")
                }
                records.append(["mode":mode,"displayHz":rate==0 ? "uneven":String(rate),"displayFrames":frames,
                                "ticks":harness.ticks,"events":harness.events])
            }
        }
        let test=FixedVelocityHarness(library:library,mode:"wall"),character=test.character!
        _=character.update(delta:1/60,displacement:SIMD3(0.02,0,0),geometryReady:true)
        let feet=character.state.feet,velocity=character.stepVelocity
        _=character.update(delta:1/120,displacement:.zero,geometryReady:true)
        check(character.state.feet==feet && character.stepVelocity==velocity,"Half tick changed the committed velocity")
        _=character.update(delta:1/60,displacement:SIMD3(3,0,0),geometryReady:false)
        check(character.state.feet==feet && character.stepVelocity==velocity,"Streaming pause fabricated a new physical velocity")
        character.reset(feet:SIMD3(2000,0,20))
        check(character.stepVelocity == .zero,"Teleport inherited a velocity from an unrelated position")
        _=character.update(delta:1/60,displacement:SIMD3(0.02,0,0),geometryReady:true)
        character.setActive(false)
        check(character.stepVelocity == .zero,"Vehicle ownership handoff retained foot velocity")
        // A fallback jump can be queued in a display half-tick before the
        // physical motor runs. Exercise the actual Renderer cancellation.
        let queued=FixedVelocityHarness(library:library,mode:"wall"),walker=queued.character!
        queued.footAnimator=nil // Original animation metadata unavailable path.
        for _ in 0..<30 {_=walker.update(delta:1/60,displacement:.zero,geometryReady:true)}
        let queuedFeet=walker.state.feet
        _=walker.update(delta:1/120,displacement:SIMD3(0.1,0,0),jump:6.07,geometryReady:true)
        check(walker.state.grounded && walker.state.rising==0,"Queue fixture unexpectedly advanced physics")
        queued.cancelGameplayInput()
        let neutral=walker.update(delta:1/120,displacement:.zero,geometryReady:true)
        check(neutral.grounded && neutral.rising==0 && simd_distance(neutral.feet,queuedFeet)<0.001,
              "Modal/network input cancellation replayed a queued jump or displacement")
        _=walker.update(delta:1/120,displacement:.zero,jump:6.07,geometryReady:true)
        let fresh=walker.update(delta:1/120,displacement:.zero,geometryReady:true)
        check(fresh.rising==6.07 && fresh.feet.z>queuedFeet.z+0.09,"A fresh jump after cancellation was suppressed")
        let beforeCancel=walker.state,committed=walker.stepVelocity
        queued.personalFlight.wear(true)
        queued.personalFlight.takeOff(heading:1.23,velocity:SIMD3(2,3,4))
        queued.personalFlight.steer(x:1,y:1,open:true,up:true)
        queued.vehicleWorkingControl=1
        queued.cancelGameplayInput()
        check(queued.vehicleWorkingControl==0,"Input cancellation retained a working-vehicle command")
        check(walker.state.feet==beforeCancel.feet && walker.state.rising==beforeCancel.rising && walker.stepVelocity==committed,
              "Cancelling queued intent reset committed airborne momentum")
        check(queued.personalFlight.on && queued.personalFlight.worn && queued.personalFlight.heading==1.23 &&
              queued.personalFlight.linearVelocity==SIMD3(2,3,4),"Cancelling input stopped the existing flight task")
        let falling=walker.update(delta:1/60,displacement:.zero,geometryReady:true)
        check(falling.rising>0 && falling.rising<fresh.rising && falling.feet.z>fresh.feet.z,"Airborne task failed to continue after cancellation")
        let held=FixedVelocityHarness(library:library,mode:"wall"),holder=held.character!
        _=holder.update(delta:1/120,displacement:.zero,jump:6.07,geometryReady:true)
        held.cancelGameplayInput()
        let anchor=SIMD3<Float>(held.startX,0,3)
        let heldResult=holder.update(delta:1/120,displacement:.zero,geometryReady:true,motion:{_,_,input in
            var value=input;value.heldFeet=anchor;return value
        })
        check(heldResult.feet==anchor && heldResult.rising==0,"Cancellation broke animation-owned root placement")
        held.cancelGameplayInput()
        let continuedHold=holder.update(delta:1/60,displacement:.zero,geometryReady:true,motion:{_,_,input in
            var value=input;value.heldFeet=anchor;return value
        })
        check(continuedHold.feet==anchor && continuedHold.rising==0,"Input loss interrupted an ongoing held root")
        let released=holder.update(delta:1/60,displacement:.zero,geometryReady:true)
        check(released.rising<0 && released.feet.z<anchor.z,"Held-root release inherited a cancelled jump")
        let walking=FixedVelocityHarness(library:library,mode:"wall"),groundedWalker=walking.character!
        for _ in 0..<30 {_=groundedWalker.update(delta:1/60,displacement:.zero,geometryReady:true)}
        _=groundedWalker.update(delta:1/60,displacement:SIMD3(0.02,0,0),geometryReady:true)
        let groundVelocity=groundedWalker.stepVelocity,groundFeet=groundedWalker.state.feet
        walking.cancelGameplayInput()
        check(groundedWalker.stepVelocity==groundVelocity && groundedWalker.state.feet==groundFeet,
              "Input loss erased committed grounded velocity or changed feet")
        let report:[String:Any]=["authority":"Actual Renderer swimming/personal-flight methods and velocity boundaries + real native motor/Rapier/original CLP animation; not retail runtime",
                               "checks":checks,"cases":records,"limitations":["Controlled water plane and walking intent","No UIKit, display interpolation, camera or physical controller capture"]]
        let output=root.appendingPathComponent("local-only/research/fixed-velocity/report.json")
        try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:output)
        print("PASS fixed velocity: \(checks) checks across 16 actual motor/animation/water/parachute/jetpack/collision cadence cases; report \(output.path)")
    }
}
