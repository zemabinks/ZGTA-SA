import Foundation
import simd

// No asset/HTTP/Metal/physics fixture: only the pure task controllers and real
// camera run. UI, source admission and unused CLP/ledge geometry are explicit spies.
final class UIColor { static let black=UIColor();func withAlphaComponent(_ alpha:Double)->UIColor{self} }
final class Button {var backgroundColor:UIColor?;var isSelected=false}
final class HUD {
    var aiming=false,scoped=false,changes=0
    func setAiming(_ value:Bool,scoped:Bool){aiming=value;self.scoped=value && scoped;changes+=1}
}
struct Weapon {var selected=34}
struct Trigger {var isPressed=false}
struct Pad {var leftTrigger=Trigger()}
struct RawKey:Hashable {var rawValue:Int}
final class Network {var health=100,passive=false}
enum NativeCharacterController {struct Output {var feet=SIMD3<Float>.zero;var rising=0.0;var grounded=true}}
enum SwiftRapierWorld {static func gtaToRapier(_ v:SIMD3<Float>)->SIMD3<Float>{SIMD3(v.x,v.z,-v.y)}}
final class ClipLibrary {var available=true;func duration(of:String)->Double?{available ? 1:nil}}
final class Animator {var reloading=false,busy=false;var resets=0;func resetMovementTask(){resets+=1;reloading=false}}
final class Queries {
    var available=true
    func find(feet:SIMD3<Double>,heading:Double,extended:Bool)->NativeClimbController.Ledge? {
        available ? .init(hold:feet+SIMD3(0,1,0),into:SIMD3(0,0,1),heading:heading,high:false,vault:false):nil
    }
}
final class Renderer {
    struct Definition {var aims:Bool;var arm:Bool}
    let gameCamera:NativeGameCamera
    let personalFlight=NativePersonalFlightController(),swimController=NativeSwimController()
    var health=100,driving=false,equippedWeapon=34,aiming=false,crouching=false
    var footWeaponDefinitions=[22:Definition(aims:true,arm:true),23:Definition(aims:true,arm:false),34:Definition(aims:true,arm:false),0:Definition(aims:false,arm:false)]
    var climb:NativeClimbController?,climbPhase:NativeClimbController.Part?
    var onFootAimCancelled:(()->Void)?,onReloadTaskCancelled:(()->Void)?,onParachuteUsed:(()->Void)?
    var hasParachute=true,actorHeading:Float=0,heading:Float=0
    var lastFootVelocity=SIMD3<Double>.zero,footAirVelocity=SIMD2<Double>.zero
    var footAirTime=0.0,footAirFall=0.0,footAirFell=false,footJumped=false,footLaunchRemaining:Double?
    var pendingClimbPull=false,pendingClimbDrop=false,airGrabTicks=0,manualAnimation=false
    var skeletalLibrary:ClipLibrary?=ClipLibrary(),footAnimator:Animator?=Animator(),climbQueries:Queries?=Queries()
    var gameCameraFrame:NativeGameCamera.Frame?,camera=SIMD3<Float>.zero,cameraLookDirection:String?
    // Authored display-position boundary; the real fixed coordinator and
    // interpolation have separate motor/physics gates. Aim uses the actual
    // renderer camera call with this supplied presentation input.
    var footPresentationPosition=SIMD3<Float>.zero
    var currentFootVelocity=SIMD3<Double>.zero
    var meleeGuardHeld=false,meleeBlockHeld=false,vehicleLights=false,canNativeFootMeleeGuard=false
    var vehicleKind="car",hasLandingGear=false,hasJetNozzle=false,hasVehicleWorkingControls=false,vehicleWorkingIsTow=false,canUnhitchVehicle=false
    var wearingJetpack:Bool {personalFlight.worn}
    var motionScenario:(()->Void)?
    var swimming:Bool {swimController.on}
    var isClimbing:Bool {climb != nil}
    var isChuting:Bool {personalFlight.chuting}
    func clearAction(){}
    func cancelWeaponInput(){}
    // RENDERER_METHODS
    init()throws {
        let three=["car","bike","heli","plane"]
        let document:[String:Any]=[
            "vehicleProfiles":Dictionary(uniqueKeysWithValues:three.map{($0,Array(repeating:0.0,count:15))}),
            "vehicleDistances":Dictionary(uniqueKeysWithValues:three.map{($0,[2.0,3,4])}),
            "vehicleAngles":Dictionary(uniqueKeysWithValues:three.map{($0,[0.0,0,0])}),
            "cinematic":["ground":[0.0,0,0,0],"air":[0.0,0,0,0]],"footDistances":[1.0,1.5,2.0],
            "footSights":["scope":["first":40.0,"least":10,"most":70],"camera":["first":60.0,"least":10,"most":70],"rocket":["first":50.0,"least":10,"most":70]],
            "footWeaponFov":[[22.0,60.0],[34,40]],"weaponSights":["34":"scope"]]
        gameCamera=try NativeGameCamera(data:JSONSerialization.data(withJSONObject:document));gameCamera.setDirection(heading:0,pitch:0)
    }
    func enterSwim(depth:Double?=2,state:NativeCharacterController.Output = .init()) {
        // ACTUAL_SWIM_ENTRY
    }
    func enterChute(state:NativeCharacterController.Output = .init(rising:-12,grounded:false),height:Double?=30) {
        // ACTUAL_CHUTE_ENTRY
    }
    func enterClimb()->Bool {beginClimb(state:.init(),extended:false)}
    func startFlight() {
        personalFlight.wear(true);personalFlight.steer(up:true)
        // ACTUAL_TAKEOFF
        // ACTUAL_FLIGHT_AIM_GATE
    }
    func reconcileFlightAim() {
        // ACTUAL_FLIGHT_AIM_GATE
    }
    func leave(_ task:String) {
        if task=="swim" {_=swimController.step(delta:1.0/60,depth:nil)}
        else if task=="chute" {_=personalFlight.step(delta:0.2,grounded:true)}
        else {climb=nil}
    }
    func enter(_ task:String) {if task=="swim"{enterSwim()}else if task=="chute"{enterChute()}else{_=enterClimb()}}
    func render(step:Double)->NativeGameCamera.Frame {
        // ACTUAL_CAMERA_CALL
        return gameCameraFrame!
    }
    func move(forward:Float,sideways:Float,turn:Float,delta:Float,running:Bool,lookVertical:Float,lift:Float){motionScenario?()}
}
final class Owner {
    var renderer:Renderer?
    var aiming=false,usingPistol=true,usingMelee=false,currentVehicle:Int?,touchMeleeGuard=false,lastGamepadAim=false
    var acceptsHeldInput=true
    var heldKeys=Set<RawKey>()
    let network=Network()
    var weapons=Weapon()
    let gameHUD=HUD(),aimButton=Button()
    init(_ renderer:Renderer){self.renderer=renderer;bind()}
    func bind(){
        // ACTUAL_GVC_BINDING
    }
    // GVC_METHODS
    func poll(held:Bool,keyboardHeld:Bool=false,allowed:Bool=true,acceptsInput:Bool=true) {
        let controller:Pad?=Pad(leftTrigger:Trigger(isPressed:held)),controllerAllowed=allowed
        heldKeys=keyboardHeld ? [RawKey(rawValue:NativeGameBindings.Key.caps.rawValue)]:[]
        let context=bindingContext
        let keyboard=NativeGameBindings.keyboard(Set(heldKeys.map(\.rawValue)),context:context)
        let handbrakePressed=false,gamepadJumping=false,firePressed=false,gamepadAttacking=false
        // ACTUAL_POLL
    }
    func moveSlices(_ steps:[Double]) {
        let timing=NativeGameFrameClock.Frame(delta:steps.reduce(0,+),steps:steps,discontinuity:false)
        let forward:Float=0,sideways:Float=0,steering:Float=0,lookVertical:Float=0,lift:Float=0,running=false
        // ACTUAL_MOVES
    }
}
var checks=0
func check(_ value:Bool,_ reason:String){checks+=1;if !value {fputs("FAIL: \(reason)\n",stderr);exit(1)}}
let historical = // HISTORICAL_MODE
let historicalFlight = // HISTORICAL_FLIGHT_MODE
if historical {
    let r=try Renderer(),g=Owner(r);g.toggleAim();check(g.aiming,"Historical setup did not enter scope")
    r.enterSwim()
    if g.aiming && r.aiming && r.render(step:1.0/60).hidesPlayer {
        print("HISTORICAL_LATCH: accepted actual swim entry retained GVC scope, Renderer aim and hidden-body scoped camera; current contract rejected")
        exit(2)
    }
    fputs("Historical source did not reproduce diagnosed latch\n",stderr);exit(1)
}
if historicalFlight {
    let r=try Renderer(),g=Owner(r);r.equippedWeapon=23;g.weapons.selected=23;g.toggleAim();r.startFlight()
    if r.personalFlight.flying && g.aiming && r.aiming {
        print("HISTORICAL_FLIGHT_LATCH: actual accepted takeoff retained incompatible aim in Renderer and GVC; current contract rejected")
        exit(2)
    }
    fputs("Historical source did not reproduce incompatible flight aim\n",stderr);exit(1)
}
let presented=try Renderer(),samePresentation=try Renderer()
presented.camera=SIMD3(700,800,50);presented.footPresentationPosition=SIMD3(10,20,3)
samePresentation.camera=presented.footPresentationPosition;samePresentation.footPresentationPosition=presented.footPresentationPosition
presented.aiming=true;samePresentation.aiming=true
let presentedFrame=presented.render(step:1.0/60),sameFrame=samePresentation.render(step:1.0/60)
check(simd_distance(presentedFrame.source,sameFrame.source)<0.00001 && simd_distance(presentedFrame.target,sameFrame.target)<0.00001,
      "Actual aim camera call used committed physics feet instead of its supplied display target")
for hz in [15,30,60,120] {for task in ["swim","chute","climb"] {for owner in ["touch","controller","keyboard"] {for weapon in [22,34] {
    let r=try Renderer(),g=Owner(r);r.equippedWeapon=weapon;g.weapons.selected=weapon
    if owner=="touch"{g.toggleAim()}else{g.poll(held:owner=="controller",keyboardHeld:owner=="keyboard")}
    check(g.aiming && r.aiming && g.gameHUD.aiming && g.aimButton.isSelected,"Fresh legitimate aim failed")
    for _ in 0..<hz{_=r.render(step:1.0/Double(hz))}
    check(r.gameCameraFrame!.hidesPlayer==(weapon==34),"Authored camera setup did not select expected scope")
    var cancellations=0
    let callback=r.onFootAimCancelled
    r.onFootAimCancelled={cancellations+=1;callback?()}
    r.enter(task)
    check(!g.aiming && !r.aiming && !g.gameHUD.aiming && !g.gameHUD.scoped && !g.aimButton.isSelected,"Accepted \(task) failed to retire existing \(owner) aim")
    check(cancellations==1,"Task cancellation must deliver exactly once")
    check(!r.render(step:1.0/Double(hz)).hidesPlayer,"Task kept scoped render camera")
    r.enter(task);check(cancellations==1,"Repeat task/no-latch emitted duplicate cancellation")
    g.poll(held:owner=="controller",keyboardHeld:owner=="keyboard")
    check(!g.aiming,"Held input fabricated a post-cancellation press")
    // Keyboard bindings already mask held aim in these contexts. A key still
    // physically held on shore may create their established new context edge.
    // Release it here to test absence of an unrelated stale touch/controller
    // latch; a separate positive below preserves the held-key context edge.
    if owner=="keyboard" {g.poll(held:false,keyboardHeld:false)}
    r.leave(task);check(!r.swimming && !r.isChuting && !r.isClimbing,"Task did not actually release its pure owner")
    for _ in 0..<hz {
        g.poll(held:owner=="controller")
        _=r.render(step:1.0/Double(hz))
        check(!g.aiming && !r.aiming,"Return to foot resurrected canceled aim")
    }
    let neutral=try Renderer();neutral.equippedWeapon=weapon
    let expected=neutral.render(step:1)
    check(simd_distance(r.gameCameraFrame!.source,expected.source)<0.0001 && abs(r.gameCameraFrame!.verticalFov-expected.verticalFov)<0.0001,"Camera did not converge through existing fade without reset")
    if owner=="touch" {g.toggleAim()}else {g.poll(held:false);g.poll(held:owner=="controller",keyboardHeld:owner=="keyboard")}
    check(g.aiming && r.aiming,"Real release/repress or touch request failed after task")
}}}}
for task in ["swim","chute","climb"] {
    let r=try Renderer(),g=Owner(r);g.poll(held:false,keyboardHeld:true);r.enter(task)
    g.poll(held:false,keyboardHeld:true);check(!g.aiming && !g.lastGamepadAim,"Keyboard task context failed to mask held aim")
    r.leave(task);g.poll(held:false,keyboardHeld:true)
    check(g.aiming,"Existing held-key context re-entry was changed")
}
// Rejected transitions do not retire a legitimate aim or manufacture a callback.
for task in ["shallow","no-canopy","missing-climb"] {
    let r=try Renderer(),g=Owner(r);g.toggleAim();var callbacks=0;r.onFootAimCancelled={callbacks+=1}
    if task=="shallow"{r.enterSwim(depth:0.8)}else if task=="no-canopy"{r.hasParachute=false;r.enterChute()}else{r.climbQueries?.available=false;check(!r.enterClimb(),"Missing ledge was accepted")}
    check(g.aiming && r.aiming && callbacks==0,"Rejected task canceled valid aim")
}
// Enter+exit is inside ONE outer move, not one state sampled per display slice.
for task in ["swim","chute","climb"] {
    let r=try Renderer(),g=Owner(r);g.toggleAim();var moved=0
    r.motionScenario={r.enter(task);check(!g.aiming,"Internal handoff missed its synchronous owner callback");r.leave(task);moved+=1}
    g.moveSlices([1.0/60])
    check(moved==1 && !g.aiming && !r.swimming && !r.isChuting && !r.isClimbing,"Transient task within one outer movement revived aim")
}
// Direct rendering guards prevent a stale caller from keeping scope while the
// input owner has not polled. The next actual poll retires the latch/HUD too.
for blocked in ["swim","chute","climb","dead","driving","unsupported"] {
    let r=try Renderer(),g=Owner(r);g.toggleAim()
    if blocked=="swim"{r.swimController.enter(velocity:.zero,rising:0,depth:2)}
    else if blocked=="chute"{r.personalFlight.dive(velocity:.zero,rising:-12,heading:0)}
    else if blocked=="climb"{r.climb=NativeClimbController(ledge:.init(hold:.zero,into:SIMD3(0,0,1),heading:0,high:false,vault:false),feet:.zero,durations:.init(jump:1,pull:1,stand:1,vault:1))}
    else if blocked=="dead"{r.health=0}else if blocked=="driving"{r.driving=true}else{r.equippedWeapon=0}
    check(!r.canMaintainFootAim && !r.render(step:1.0/60).hidesPlayer,"Direct owner change kept scope: \(blocked)")
    g.poll(held:false);check(!g.aiming && !g.gameHUD.aiming,"Polling failed to retire direct-owner stale aim")
}
// Valid jetpack guns, neutral touch ownership and input-only resets keep their
// established semantics; this is not a broad airborne/combat policy rewrite.
for airborne in [false,true] {
    let r=try Renderer(),g=Owner(r);r.equippedWeapon=22;g.weapons.selected=22;r.personalFlight.wear(true)
    if airborne{r.personalFlight.takeOff(heading:1)}
    g.toggleAim();g.poll(held:false)
    check(r.canMaintainFootAim && g.aiming && r.render(step:1.0/60).aimSource != nil,"Eligible pack gun aim was suppressed")
}
// Arm metadata owns camera aim while actually flying, not merely wearing a
// pack. Use the literal accepted takeoff/flight gate and genuine landing step.
for weapon in [22,23,34] {for owner in ["touch","controller"] {
    let r=try Renderer(),g=Owner(r);r.equippedWeapon=weapon;g.weapons.selected=weapon
    if owner=="touch"{g.toggleAim()}else{g.poll(held:true)}
    var cancellations=0;let callback=r.onFootAimCancelled
    r.onFootAimCancelled={cancellations+=1;callback?()}
    r.startFlight();check(r.personalFlight.flying,"Real accepted takeoff did not start")
    let compatible=r.footWeaponDefinitions[weapon]!.arm
    check(r.canMaintainFootAim==compatible && g.aiming==compatible && r.aiming==compatible,"Incompatible flying weapon retained aim or valid arm gun lost it")
    check(cancellations==(compatible ? 0:1),"Flight aim cancellation not bound to actual arm ownership")
    if !compatible {let frame=r.render(step:1.0/60);check(!frame.hidesPlayer && frame.aimSource==nil,"Incompatible flight kept scoped or shoulder camera")}
    r.reconcileFlightAim();check(cancellations==(compatible ? 0:1),"Repeated flight tick duplicated cancellation")
    r.personalFlight.steer(down:true);_=r.personalFlight.step(delta:1.0/60,grounded:true)
    check(!r.personalFlight.flying,"Real touchdown did not finish the flight task")
    g.poll(held:owner=="controller")
    check(g.aiming==compatible,"Touchdown revived incompatible canceled aim")
}}
do {
    let r=try Renderer(),g=Owner(r);g.toggleAim();r.footAnimator?.busy=true;r.startFlight()
    check(!r.personalFlight.flying && g.aiming,"Rejected busy takeoff canceled grounded aim")
}
do {
    let r=try Renderer(),g=Owner(r);r.equippedWeapon=22;g.weapons.selected=22;g.poll(held:true);r.startFlight()
    r.equippedWeapon=23
    let frame=r.render(step:1.0/60)
    check(!r.canMaintainFootAim && !frame.hidesPlayer && frame.aimSource==nil,"Switched incompatible flight kept aim camera")
    r.reconcileFlightAim();check(!g.aiming && !r.aiming,"Changed arm owner retained held aim")
    r.equippedWeapon=22;g.poll(held:true);check(!g.aiming,"Restoring a compatible gun synthesized a trigger edge")
    g.poll(held:false);g.poll(held:true);check(g.aiming,"Fresh compatible flight aim press failed")
}
do {
    let r=try Renderer(),g=Owner(r);g.toggleAim();g.poll(held:false)
    check(g.aiming,"Neutral hardware canceled a legitimate touch toggle")
    var gate=NativeControllerInputGate()
    check(!gate.accepts(active:true,left:.zero,right:.zero,triggers:SIMD2(1,0),pressed:false),"Reset controller accepted held trigger")
    g.poll(held:true,allowed:false);check(g.aiming,"Unarmed controller unexpectedly took touch ownership")
    check(gate.accepts(active:true,left:.zero,right:.zero,triggers:.zero,pressed:false),"Neutral controller did not rearm")
    g.poll(held:false);g.poll(held:true)
    check(g.aiming,"Rearmed controller could not make a genuine aim press")
    g.poll(held:false);check(!g.aiming,"Physical release did not clear hardware aim")
}
print("PASS aim ownership: \(checks) actual-source task/input/camera checks at15/30/60/120Hz; authored metadata and UI/CLP/geometry spies, no hardware")
