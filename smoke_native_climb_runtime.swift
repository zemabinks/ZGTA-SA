// This CPU harness receives the actual current Renderer foot/climb methods
// at test time. It links the real CharacterController and native Rapier world.
// Metal/VC/camera are outside this gate; animation tracks are the local CLP1.
import Foundation
import simd

final class ClimbRuntimeHarness {
    static var sharedLibrary:NativeSkeletalAnimationLibrary?
    static var sharedDefinitions:[Int:NativeFootWeaponAnimation]?
    let world:SwiftRapierWorld
    let character:NativeCharacterController?
    let skeletalLibrary:NativeSkeletalAnimationLibrary?
    var footAnimator:NativeFootAnimation?
    let footLocomotion=NativeFootLocomotion(),headingContinuity=NativeHeadingContinuity()
    var climb:NativeClimbController?,climbPhase:NativeClimbController.Part?
    var pendingClimbPull=false,pendingClimbDrop=false,airGrabTicks=0,jumpHeld=false,walkHeld=false
    lazy var climbQueries=character.map{NativeRapierClimbQueries(world:$0.world,excluded:[$0.queries.walker,$0.queries.probe])}
    var health=100,driving=false,crouching=false,manualAnimation=false,aiming=false
    var originalCoughing=false
    var onLocalDamage:((Double,Int)->Void)?
    var onLocalHealth:((Int)->Void)?
    struct InactiveSwim {var on=false}
    var swimController=InactiveSwim()
    let personalFlight=NativePersonalFlightController()
    final class VehicleInputOwner {var cancellations=0;func cancelPendingInput(){cancellations += 1}}
    let groundVehicle:VehicleInputOwner?=VehicleInputOwner()
    var vehicleHop=false
    var vehicleWorkingControl:Float=0
    var actorHeading:Float=0,heading:Float=0
    var footAirTime=0.0,footAirFall=0.0,footJumpMinimum=0.0,footAirFell=false,footJumped=false
    var footLaunchRemaining:Double?,footAirVelocity=SIMD2<Double>.zero,footSprintPace=0.0
    var footDeathKind:String?,pendingFootHit:SIMD3<Double>?
    var footReloadWasActive=false,footReloadRequested=false,weaponReloading=false,weaponReady=true
    var footWeaponDefinitions:[Int:NativeFootWeaponAnimation]=[:],equippedWeapon=22,weaponTriggerHeld=false
    var meleeDefinitions:NativeMeleeDefinitions?
    let meleeInput=NativeMeleeInput()
    var meleeClock:Double=0,meleeGuardHeld=false,meleeBlockHeld=false
    var swimming:Bool {swimController.on}
    var onMeleeGroundTarget:((NativeMeleeProbe)->Bool)?,onMeleeSwing:((Int)->Void)?,onFootMeleeHit:((NativeMeleeEvent)->Bool)?
    var footAnimationFrame:NativeFootAnimation.Frame?,ownClip="",ownClipTime=0.0
    var cameraPitch:Float=0
    var camera=SIMD3<Float>.zero
    let sprintController=NativeSprintController()
    var stamina=NativeStamina(),pendingSprintTap=false
    var verticalSpeed:Float=0
    var onFootWeaponShot:((Int,Bool)->Bool)?
    var onReloadTaskCancelled:(()->Void)?
    var acceptedStreamShot=false,pendingNativeJump=0.0,pendingSwimJump=false,pendingDive=false
    var acceptedStreamRay:(weapon:Int,origin:SIMD3<Float>,direction:SIMD3<Float>)?
    var pendingParachuteOpen=false,sprintWasHeld=false,personalFlightDown=false,personalFlightBrake=false
    var personalFlightAnimationInput:NativeFlightAnimation.Input? {nil}
    var fixedSteps=0,heldSteps=0,footCalls=0,firstTickCount=0,checks=0,displayFrames=0
    var expectedHeld:SIMD3<Float>?
    var completedFeet:SIMD3<Float>?,completedPart:NativeClimbController.Part?
    var lastPosePart:NativeClimbController.Part?,lastPoseTime=0.0
    var seen=Set<Int>()
    var carrierBody:UInt64?
    func prepareFootAnimation() {} // real library/animator is preloaded below
    func cancelCameraInput() {} // camera is outside this motor/pose gate

    init(root:URL,top:Float,depth:Float,angle:Double=0,carrier:SwiftRapierWorld.BodyKind?=nil) throws {
        world=SwiftRapierWorld()!;character=NativeCharacterController(world:world)!
        if Self.sharedLibrary==nil {
            Self.sharedLibrary=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/models/animations.clips.bin")))!
            Self.sharedDefinitions=try NativeFootWeaponAnimation.load(data:Data(contentsOf:root.appendingPathComponent("local-only/site/game/native/foot-animation.json")))
        }
        let library=Self.sharedLibrary!
        skeletalLibrary=library;footAnimator=NativeFootAnimation(library:library,random:{0.37})
        footWeaponDefinitions=Self.sharedDefinitions!
        footAnimator!.arm(footWeaponDefinitions[22])
        func box(_ half:SIMD3<Float>,_ position:SIMD3<Float>,_ rotation:simd_quatf=simd_quatf(ix:0,iy:0,iz:0,r:1),kind:SwiftRapierWorld.BodyKind?=nil) {
            let body=kind.flatMap{world.addBody(kind:$0,position:position,rotation:rotation)}
            if kind != nil{carrierBody=body}
            let id=world.addBox(halfExtents:half,body:body,position:body == nil ? position:.zero,rotation:body == nil ? rotation:simd_quatf(ix:0,iy:0,iz:0,r:1))!
            world.setColliderGroups(id,collision:0x0087ffff,solver:0xffffffff)
            world.setColliderQueryMetadata(id,surface:2,material:0)
        }
        box(SIMD3(100,0.1,100),SIMD3(0,-0.1,0))
        let z=Double(-0.8-depth/2)
        box(SIMD3(1,top/2,depth/2),SIMD3(Float(sin(angle)*z),top/2,Float(cos(angle)*z)),
            simd_quatf(ix:0,iy:Float(sin(angle/2)),iz:0,r:Float(cos(angle/2))),kind:carrier)
        world.step()
        actorHeading = -Float(angle);heading=actorHeading;footLocomotion.reset(heading:Double(actorHeading))
        character!.reset(feet:.zero,active:true,grounded:true)
        footLaunchRemaining=0
        world.beforeStep={[unowned self] _ in
            fixedSteps += 1
            if let expectedHeld {
                let actual=world.colliderInfo(character!.queries.walker)!.translation
                let expected=SwiftRapierWorld.gtaToRapier(expectedHeld)+SIMD3<Float>(0,0.9,0)
                precondition(simd_distance(actual,expected)<0.000002,"Walker capsule was not placed before shared world.step")
                precondition(!character!.motor.grounded && character!.motor.rising==0,"Suspended foot motor retained grounded/rising state")
                heldSteps += 1;checks += 2
            }
        }
    }

    func emitFootWeaponEventsForTest(_ frame:NativeFootAnimation.Frame,feet:SIMD3<Float>) {emitFootWeaponEvents(frame,feet:feet)}
    func attemptClimbForTest()->Bool {beginClimb(state:character!.state,extended:true)}
    // ACTUAL_RENDERER_METHODS

    @discardableResult func frame(_ delta:Double,forward:Float=0,sideways:Float=0)->NativeCharacterController.Output {
        displayFrames += 1
        let output=character!.update(delta:delta,displacement:.zero,geometryReady:true,motion:{[self] step,state,intended in
            let taskBefore=climb
            let partBefore=taskBefore?.part
            let motion:NativeCharacterController.Motion
            if let held=climbingMotion(delta:step,state:state,intended:intended) {motion=held}
            else {footCalls += 1;motion=footMotion(delta:step,state:state,intended:intended,forward:forward,sideways:sideways,running:false)}
            if taskBefore==nil,let task=climb {
                precondition(task.feet==SIMD3<Double>(SwiftRapierWorld.gtaToRapier(state.feet)),"Constructor tick incorrectly advanced the new task")
                precondition(task.part == .jump || task.part == .edge)
                firstTickCount += 1;checks += 2
            }
            if let task=climb {
                seen.insert(task.part.rawValue)
                let clip:[NativeClimbController.Part:String]=[.jump:"climb_jump",.hang:"climb_idle",.pull:"climb_pull",.edge:"climb_stand",.stand:"climb_stand",.vault:"climb_jump_b"]
                let matches=footAnimationFrame!.blends.filter{$0.clip=="ped/"+clip[task.part]! && $0.weight>0}
                precondition(matches.count==1 && matches[0].rooted,"Active climb lost its authored rooted pose")
                if task.part == .edge {precondition(matches[0].time==0,"EDGE must pause the stand pose")}
                if taskBefore==nil,task.part == .jump {precondition(abs(matches[0].time-step)<1e-12,"Constructor pose did not consume its initial animation tick")}
                if task.part == lastPosePart && task.part != .edge && task.part != .hang {
                    let expected=min(lastPoseTime+step,skeletalLibrary!.duration(of:matches[0].clip)!)
                    precondition(abs(matches[0].time-expected)<1e-10,"Climb pose clock restarted while its physical phase continued")
                    checks += 1
                }
                lastPosePart=task.part;lastPoseTime=matches[0].time
                precondition(footAnimationFrame!.shots.isEmpty)
                checks += 3
            }
            if taskBefore != nil,climb==nil {
                precondition(motion.heldFeet != nil,"Completion tick lost final held feet")
                let final=SwiftRapierWorld.rapierToGTA(SIMD3<Float>(taskBefore!.feet))
                precondition(simd_distance(motion.heldFeet!,final)<0.000002,"Completion tick did not publish final controller feet")
                if taskBefore!.part == .stand || taskBefore!.part == .vault {
                    let finish=taskBefore!.part == .stand ? "ped/climb_stand_finish":"ped/climb_jump2fall"
                    precondition(footAnimationFrame!.blends.contains{$0.clip==finish && $0.weight>0},"Completion lost the authored exit clip")
                    checks += 1
                }
                completedFeet=motion.heldFeet;completedPart=partBefore;checks += 1
            }
            expectedHeld=motion.heldFeet
            return motion
        })
        if let expectedHeld {precondition(simd_distance(output.feet,expectedHeld)<0.000002);checks += 1}
        camera=output.feet
        return output
    }
}

@main enum ClimbRuntimeSmoke {
 static func main() throws {
    let root=URL(fileURLWithPath:CommandLine.arguments[1])
    var checks=0,frames=0,physicsTicks=0,reports:[[String:Any]]=[]
    for hz in [30,60,120] {for kind in ["stand","vault","pull","drop","death"] {
        let high=["pull","drop","death"].contains(kind)
        let angle=hz==30 ? 359*Double.pi/180:hz==60 ? -179*Double.pi/180:0
        let harness=try ClimbRuntimeHarness(root:root,top:high ? 2.7:1.8,depth:kind=="vault" ? 0.08:2,angle:angle)
        let dt=Double(Float(1/Double(hz)))
        var firstDisplay=true,waited=0.0,finished=false
        for _ in 0..<hz*8 {
            if harness.climb?.part == .hang {
                waited += dt
                if waited>0.3 {
                    if kind=="pull" {harness.jumpHeld=true}
                    if kind=="drop" {harness.letGoOfLedge()}
                    if kind=="death" {harness.health=0}
                }
            }
            let previousSteps=harness.fixedSteps
            _ = harness.frame(dt)
            if harness.fixedSteps>previousSteps {
                if firstDisplay {precondition(harness.firstTickCount==1);firstDisplay=false}
                if harness.climb==nil,let final=harness.completedFeet {
                    // A30Hz display frame can contain completion followed by
                    // the legitimate first resumed foot fixed tick.
                    precondition(harness.headingContinuity.owner == .climbing || harness.headingContinuity.owner == .foot)
                    let facing=Double(harness.actorHeading)
                    precondition(abs(NativeHeadingContinuity.difference(facing,from:-angle))<0.000002)
                    if kind=="vault" {precondition(harness.footAirTime>=0.35 && harness.footAirTime<0.4 && simd_length(harness.footAirVelocity)>0.99,"Vault velocity/air task handoff was discarded")}
                    let heldAtEnd=harness.heldSteps
                    let stepAtEnd=harness.fixedSteps
                    var output=harness.character!.state
                    // A120Hz frame can contain no fixed physics tick.
                    for _ in 0..<3 where harness.fixedSteps==stepAtEnd {output=harness.frame(dt)}
                    precondition(harness.heldSteps==heldAtEnd,"Completion was held for an extra task tick")
                    precondition(harness.fixedSteps>stepAtEnd && harness.headingContinuity.owner == .foot && harness.headingContinuity.handoffs==1,"No unique fixed-tick foot handoff: \(kind),\(hz)Hz")
                    precondition(abs(NativeHeadingContinuity.difference(harness.footLocomotion.heading,from:facing))<0.000002,"Resumed locomotion changed facing")
                    if kind=="drop" {precondition(output.feet.z<final.z,"Drop did not resume gravity")}
                    if kind=="death" {precondition(harness.footAnimator!.dead)}
                    reports.append(["kind":kind,"hz":hz,"steps":harness.fixedSteps,"held":harness.heldSteps,"parts":harness.seen.sorted(),"footCalls":harness.footCalls])
                    checks += harness.checks+7;frames += harness.displayFrames;physicsTicks += harness.fixedSteps;finished=true;break
                }
            }
        }
        precondition(finished,"Climb failed to complete: \(kind),\(hz)Hz")
    }}
    // Input loss clears pending pull/drop without inventing a fall.
    let neutral=try ClimbRuntimeHarness(root:root,top:2.7,depth:2)
    for _ in 0..<90 {_ = neutral.frame(1/60)}
    precondition(neutral.climb?.part == .hang)
    neutral.pendingClimbPull=true;neutral.pendingClimbDrop=true;neutral.jumpHeld=true;neutral.walkHeld=true;neutral.vehicleHop=true;neutral.vehicleWorkingControl=1
    neutral.cancelGameplayInput();_ = neutral.frame(1/60)
    precondition(neutral.climb?.part == .hang && !neutral.jumpHeld && !neutral.walkHeld && !neutral.vehicleHop && !neutral.pendingClimbPull && !neutral.pendingClimbDrop)
    precondition(neutral.groundVehicle?.cancellations==1,"Focus cancellation must discard an unlaunched vehicle action");checks += 4
    precondition(neutral.vehicleWorkingControl==0,"Focus cancellation retained a working-vehicle command");checks += 1
    frames += neutral.displayFrames;physicsTicks += neutral.fixedSteps
    // Actual Renderer emission must expose event-time physics position during
    // every catch-up marker, then restore the ordinary display-pose fallback.
    neutral.climb=nil;neutral.climbPhase=nil;neutral.footAnimator!.resetMovementTask()
    precondition(neutral.hasNativeFootWeaponTiming && neutral.canEmitFootWeaponShot,"Marker-position fixture must use real eligible weapon state")
    neutral.camera=SIMD3(100,200,300)
    let eventFeet=SIMD3<Float>(101,202,303)
    var observed:[SIMD3<Float>]=[]
    neutral.onFootWeaponShot={_,_ in observed.append(neutral.shotFeet);return true}
    var eventFrame=neutral.footAnimationFrame!;eventFrame.shots=[false,true,false]
    neutral.emitFootWeaponEventsForTest(eventFrame,feet:eventFeet)
    precondition(observed==Array(repeating:eventFeet,count:3),"Catch-up shot used stale display coordinates")
    precondition(neutral.shotFeet==neutral.camera,"Event snapshot leaked past synchronous emission");checks += 2
    // The actual airborne path probes every second qualifying fixed tick and
    // uses its1.1m stretch threshold rather than grounded1.4m.
    let airborne=try ClimbRuntimeHarness(root:root,top:3.2,depth:2)
    airborne.footLaunchRemaining=nil;airborne.footAirTime=0.2;airborne.footJumped=true;airborne.footAirVelocity=SIMD2(0,3)
    airborne.character!.reset(feet:SIMD3(0,0,1),active:true,grounded:false)
    _ = airborne.frame(1/60);precondition(airborne.climb==nil && airborne.airGrabTicks==1)
    _ = airborne.frame(1/60);precondition(airborne.climb?.part == .jump && airborne.firstTickCount==1,"Airborne every-second-tick grab or stretch threshold failed");checks += airborne.checks+2
    frames += airborne.displayFrames;physicsTicks += airborne.fixedSteps
    let entries=try JSONSerialization.jsonObject(with:Data(contentsOf:root.appendingPathComponent("local-only/research/climbing/entry-reference.json"))) as! [String:Any]
    for row in entries["cases"] as! [[String:Any]] {
        let vehicle=row["vehicle"] as! Bool,mode=row["mode"] as! String
        let carrier=try ClimbRuntimeHarness(root:root,top:1.8,depth:2,carrier:vehicle ? .kinematicPosition:nil)
        if mode=="worn" {carrier.personalFlight.wear(true)}
        if mode=="flying" {carrier.personalFlight.wear(true);carrier.personalFlight.takeOff(heading:0)}
        if mode=="dead" {carrier.health=0}
        if mode=="missing-animation" {carrier.footAnimator=nil}
        _ = carrier.frame(1/60)
        precondition((carrier.climb != nil)==(row["accepted"] as! Bool),"Actual archived climb admission differs: vehicle\(vehicle) \(mode)")
        checks += carrier.checks+1;frames += carrier.displayFrames;physicsTicks += carrier.fixedSteps
    }
    for kind in [SwiftRapierWorld.BodyKind.dynamic,.kinematicPosition,.kinematicVelocity] {
        for speed in [0.0,0.49,0.5,0.51] {
            let carrier=try ClimbRuntimeHarness(root:root,top:1.8,depth:2,carrier:kind)
            let body=carrier.carrierBody!;var state=carrier.world.bodyState(body)!;state.linearVelocity=SIMD3(Float(speed),0,0)
            precondition(carrier.world.setBodyState(state,for:body))
            if kind == .kinematicPosition {
                precondition(carrier.world.setNextKinematicPose(body,position:state.position+SIMD3(Float(speed/60),0,0)))
                carrier.world.step()
            }
            let measured=simd_length(SIMD3<Double>(carrier.world.bodyState(body)!.linearVelocity))
            precondition(abs(measured-speed)<0.00001,"Carrier fixture did not establish requested velocity")
            _ = carrier.frame(1/60)
            precondition((carrier.climb != nil)==(measured<0.5),"Vehicle speed admission differs: \(kind) \(speed) actual\(measured)")
            if measured<0.5 {
                precondition(carrier.climb?.part == .edge && carrier.firstTickCount==1,"Vehicle ledge did not enter original EDGE phase")
                precondition(carrier.climbQueries!.find(feet:.zero,heading:0)?.vault==false,"Vehicle incorrectly gained a fixed-wall vault")
            }
            checks += carrier.checks+3;frames += carrier.displayFrames;physicsTicks += carrier.fixedSteps
        }
    }
    // Complete vehicle tasks with the real animation/motor path. The
    // archived controller captures the ledge in world coordinates.
    for kind in [SwiftRapierWorld.BodyKind.dynamic,.kinematicPosition,.kinematicVelocity] {
        for hz in [30,60,120] {for top:Float in [1.8,2.7] {
            let carrier=try ClimbRuntimeHarness(root:root,top:top,depth:2,carrier:kind)
            carrier.jumpHeld=true
            var completed=false
            for _ in 0..<(hz*8) {
                _ = carrier.frame(1/Double(hz))
                if carrier.completedFeet != nil {
                    precondition(carrier.climb==nil && carrier.completedPart == .stand,"Vehicle climb did not finish STAND")
                    precondition(!carrier.seen.contains(NativeClimbController.Part.vault.rawValue),"Vehicle climb incorrectly vaulted")
                    completed=true;break
                }
            }
            precondition(completed,"Vehicle climb completion timed out")
            checks += carrier.checks+3;frames += carrier.displayFrames;physicsTicks += carrier.fixedSteps
            reports.append(["kind":"vehicle-stand","bodyKind":kind.rawValue,"height":top,"hz":hz,"steps":carrier.fixedSteps,"parts":carrier.seen.sorted()])
        }}
    }
    // ACTUAL_RELOAD_AUDIO_TESTS
    let report:[String:Any]=["authority":"Actual current Renderer methods + real local animation/native character/core; actual archived entry predicate; not retail GTA replay","checks":checks,"displayFrames":frames,"physicsTicks":physicsTicks,"cases":reports,"additionalScenarios":["cancel-pending-input","air-grab-every-second-tick","slow-vehicle-admission","strict-half-unit-speed-boundary","nonfixed-vault-rejection","entry-mode-guards","vehicle-climb-completion","accepted-climb-reload-audio-owner"],"limitations":["No UIKit, camera or Metal pose verification","Metadata load is precompleted","Physics scenes are controlled fixtures","Vehicle climb captures the admission ledge in world space like the archived controller; no entity-relative moving handhold or retail executable coverage","Actual audio/GVC cancellation methods run with inert one-shot/sample/scheduler adapters, no speaker or retail sound timing"]]
    try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]).write(to:root.appendingPathComponent("local-only/research/climbing/runtime-report.json"))
    print("PASS current Renderer climb runtime:",checks,"checks,",frames,"display frames,",physicsTicks,"native physics ticks; real local clips",neutral.skeletalLibrary!.clipCount)
 }
}
