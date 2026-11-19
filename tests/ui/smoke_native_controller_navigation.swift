import Foundation
// Authored platform spies around actual extracted GVC polling/dispatch owners.
// No UIKit, real controller, network, engine or audio output is used.
final class FakeView {var window:Int?=1}
class UIViewController {
    let view=FakeView();var viewIfLoaded:FakeView? {view};var presentedViewController:UIViewController?
    func present(_ vc:UIViewController,animated:Bool,completion:(()->Void)?=nil){presentedViewController=vc;completion?()}
}
final class ButtonInput {var isPressed=false;var value:Float {isPressed ? 1:0}}
final class Axis {var value:Float=0}
final class StickInput {let xAxis=Axis(),yAxis=Axis()}
final class DPad {let up=ButtonInput(),down=ButtonInput(),left=ButtonInput(),right=ButtonInput()}
final class GCExtendedGamepad {
    let buttonA=ButtonInput(),buttonB=ButtonInput(),buttonX=ButtonInput(),buttonY=ButtonInput()
    let leftShoulder=ButtonInput(),rightShoulder=ButtonInput(),leftTrigger=ButtonInput(),rightTrigger=ButtonInput()
    let buttonMenu=ButtonInput();var buttonOptions:ButtonInput?=ButtonInput()
    var leftThumbstickButton:ButtonInput?=ButtonInput(),rightThumbstickButton:ButtonInput?=ButtonInput()
    let leftThumbstick=StickInput(),rightThumbstick=StickInput(),dpad=DPad()
    func neutral(){for b in [buttonA,buttonB,buttonX,buttonY,leftShoulder,rightShoulder,leftTrigger,rightTrigger,buttonMenu,dpad.up,dpad.down,dpad.left,dpad.right]{b.isPressed=false}
        buttonOptions?.isPressed=false;leftThumbstickButton?.isPressed=false;rightThumbstickButton?.isPressed=false
        leftThumbstick.xAxis.value=0;leftThumbstick.yAxis.value=0;rightThumbstick.xAxis.value=0;rightThumbstick.yAxis.value=0}
}
final class GCController {
    static var attached:[GCController]=[];let extendedGamepad:GCExtendedGamepad?
    init(_ pad:GCExtendedGamepad){extendedGamepad=pad};static func controllers()->[GCController]{attached}
}
struct HID:Hashable {let rawValue:Int}
final class TouchStick {var value=CGPoint.zero;func reset(){value = .zero}}
final class UIColor {static var white:UIColor {UIColor()};var cgColor:Int {0};func withAlphaComponent(_ a:Double)->UIColor {self}}
final class Layer {var borderWidth:Double=0,borderColor:Int=0}
final class Button {let layer=Layer()}
final class Text {var text=""}
final class Weapons {var selected=22}
struct Vehicle {let id:String,code:String}
final class Network {var isReady=true,originalInputBlocked=false,health=100,passive=false}
final class Renderer {
    var originalCoughing=false,vehicleLights=false,isClimbing=false,swimming=false,isChuting=false,wearingJetpack=false
    var hasLandingGear=false,hasJetNozzle=false,hasVehicleWorkingControls=false,vehicleWorkingIsTow=false,canUnhitchVehicle=false
    var hasNativeFootWeaponTiming=true,hasNativeFootMeleeTiming=false,hasVehicleHorn=true,vehicleKind="car"
    var walkHeld=false,vehicleHop=false,weaponTriggerHeld=false,vehicleHandbrake=false,vehicleHorn=false,vehicleSiren=false
    var vehicleJetControl:Float=0,vehicleWorkingControl:Float=0
    var personalFlightDown=false,personalFlightBrake=false,meleeGuardHeld=false,meleeBlockHeld=false
    var cameraLookDirection:String?,jumps=0
    func jump(){jumps+=1};func releaseVehicleCoupling(){}
    func requestFootMeleeAttack(alternate:Bool=false)->Bool {false}
    func cancelCameraInput(){};func cancelGameplayInput(){};func cancelWeaponInput(){}
    func streamWeapon(_ weapon:Int?,delta:Float){}
}
final class Audio {
    let hornController=NativeVehicleHornController();let sirenModels:Set<Int>=[596]
    // ACTUAL_AUDIO_METHODS
    func stream(weapon:Int,active:Bool){}
}
final class Radio {func previous(){}}
struct Link {let timestamp:Double}
struct PollFrame {let allowed:Bool,forward:Float,sideways:Float,running:Bool,firing:Bool,horn:Bool,siren:Bool}
final class Harness:UIViewController {
    var applicationActive=true,legacySelection=false;let network=Network();var renderer:Renderer?=Renderer()
    let stick=TouchStick(),lookStick=TouchStick(),audio=Audio(),radio=Radio(),weapons=Weapons(),status=Text(),runButton=Button()
    var currentVehicle:Vehicle?,context=NativeGameBindings.Context(),usingMelee=false
    var bindingContext:NativeGameBindings.Context {context}
    var controllerGate=NativeControllerInputGate(),previousPad=NativeGameBindings.Pad()
    weak var menuControllerPad:GCExtendedGamepad?;var controllerMenuEdge=NativeReleaseEdge(pressed:true)
    let weaponCycle=NativeWeaponCycleQueue();var inputWasAvailable=false
    var heldKeys:Set<HID>=[],legacyKeys=0,legacyAxes=SIMD2<Float>.zero,legacySpecialKeys=0,legacyCrouchUntil:Double=0
    var touchMeleeGuard=false,run=false,gasPressed=false,brakePressed=false,handbrakePressed=false,flightBrakePressed=false
    var hornPressed=false,bunnyHopPressed=false,nozzleUpPressed=false,nozzleDownPressed=false,firePressed=false,autoReloadWeapon:Int?
    var lastVehicleButton=false,lastJobsButton=false,lastGearButton=false,lastLightsButton=false,lastJumpButton=false,lastAttackButton=false
    var lastWeaponButton=false,lastReloadButton=false,lastCrouchButton=false,lastGamepadAim=false,lastCameraButton=false
    var vehicleTuck:Double=0,aiming=false;var events:[NativeGameBindings.Action]=[]
    func setAiming(_ value:Bool){aiming=value}
    func openPause(){events.append(.pause);present(UIViewController(),animated:false)}
    func attack(){events.append(.attack)};func toggleCrouch(){events.append(.crouch)};func toggleVehicle(){events.append(.enter)}
    func reload(){events.append(.reload)};func performNearbyMissionAction(){events.append(.action)};func openGameplay(){events.append(.jobs)}
    func openChat(){events.append(.chat)};func openMap(){events.append(.map)};func openAnimations(){events.append(.animations)}
    func cycleCameraPreference(){events.append(.camera)};func toggleGear(){events.append(.gear)}
    func cycleWeapon(_ direction:Int){events.append(direction>0 ? .weaponNext:.weaponPrevious)}
    func updateRadioControl(){events.append(.radioPrevious)};func nextRadioStation(){events.append(.radioNext)}
    // ACTUAL_OWNER_METHODS
    // ACTUAL_POLL_OWNER
}
var checks=0
func check(_ value:Bool,_ label:String){checks+=1;precondition(value,label)}
// EXPECTED_HISTORICAL
func setup()->(Harness,GCExtendedGamepad){let p=GCExtendedGamepad();GCController.attached=[GCController(p)];let h=Harness();h.resetControls();_ = h.poll();return(h,p)}
func close(_ h:Harness){h.presentedViewController=nil}
if expectedHistorical {
    let (h,p)=setup();h.network.isReady=false;_ = h.poll();p.buttonMenu.isPressed=true;_ = h.poll()
    check(h.events.isEmpty,"historical real polling drops offline Menu")
    h.performBinding(.pause);check(h.events==[.pause],"historical direct-dispatch test hides the polling defect")
    print("Historical controller navigation negative PASS \(checks)")
}else{
    for state in ["ready","connecting","reconnecting","stopped","freeze","selection"] {
        let (h,p)=setup();h.network.isReady = !["connecting","reconnecting","stopped"].contains(state)
        h.network.originalInputBlocked=state=="freeze";h.legacySelection=state=="selection";_ = h.poll()
        p.buttonMenu.isPressed=true;let frame=h.poll()
        check(h.events==[.pause],"fresh Menu navigates independent of gameplay state: \(state)")
        check(!frame.allowed && !frame.firing && !frame.horn,"same-frame normal modal suppresses gameplay")
        _ = h.poll();check(h.events.count==1,"held Menu never repeats")
        close(h);_ = h.poll();check(h.events.count==1,"held closing Menu never reopens")
        p.buttonMenu.isPressed=false;_ = h.poll();p.buttonMenu.isPressed=true;_ = h.poll()
        check(h.events==[.pause,.pause],"release and fresh Menu works")
    }
    for blocked in ["background","no window","modal"] {
        let (h,p)=setup();if blocked=="background"{h.applicationActive=false};if blocked=="no window"{h.view.window=nil};if blocked=="modal"{h.presentedViewController=UIViewController()}
        p.buttonMenu.isPressed=true;_ = h.poll();check(h.events.isEmpty,"covered navigation does not act")
        h.applicationActive=true;h.view.window=1;h.presentedViewController=nil;h.resetControls();_ = h.poll()
        check(h.events.isEmpty,"held boundary Menu is consumed")
        p.buttonMenu.isPressed=false;_ = h.poll();p.buttonMenu.isPressed=true;_ = h.poll();check(h.events==[.pause],"fresh boundary Menu opens")
    }
    do {let (h,p)=setup();h.resetControls();p.buttonMenu.isPressed=true;_ = h.poll();check(h.events==[.pause],"up-at-reset does not lose next fresh press")}
    do {let (h,p)=setup();GCController.attached=[];_ = h.poll();let next=GCExtendedGamepad();next.buttonMenu.isPressed=true;GCController.attached=[GCController(next)]
        _ = h.poll();check(h.events.isEmpty,"new held controller cannot seed fresh Menu")
        next.buttonMenu.isPressed=false;_ = h.poll();next.buttonMenu.isPressed=true;_ = h.poll();check(h.events==[.pause],"new owner release rearms")
        _ = p}
    do {let (h,p)=setup();let next=GCExtendedGamepad();next.buttonMenu.isPressed=true;GCController.attached=[GCController(next)];_ = h.poll()
        check(h.events.isEmpty,"identity switch without missing poll consumes held Menu");next.buttonMenu.isPressed=false;_ = h.poll();next.buttonMenu.isPressed=true;_ = h.poll();check(h.events==[.pause],"switched owner fresh edge")
        _ = p}
    do {let (h,p)=setup();p.buttonMenu.isPressed=true;p.buttonX.isPressed=true;p.rightTrigger.isPressed=true;p.leftThumbstickButton?.isPressed=true;p.leftThumbstick.yAxis.value=0.8
        let f=h.poll();check(h.events==[.pause]&&h.renderer?.jumps==0 && !f.firing && !f.horn,"Menu owns simultaneous gameplay controls in its opening frame")
        close(h);p.buttonMenu.isPressed=false;let held=h.poll();check(!held.allowed && !held.firing,"Menu release alone cannot rearm held gameplay controls")
        p.buttonMenu.isPressed=true;_ = h.poll();check(h.events==[.pause,.pause],"fresh navigation remains available while gameplay axes are held")}
    do {let (h,p)=setup();let next=GCExtendedGamepad();GCController.attached=[GCController(next)];_ = h.poll();next.buttonMenu.isPressed=true;_ = h.poll()
        check(h.events==[.pause],"new already-up owner preserves first fresh Menu");_ = p}
    for mode in [NativeGameBindings.Mode.foot,.vehicle("car"),.swim,.jetpack,.parachute,.climb] {
        let (h,p)=setup();h.context.mode=mode;h.network.isReady=false;_ = h.poll();p.buttonMenu.isPressed=true;_ = h.poll()
        check(h.events==[.pause],"offline navigation is independent of movement context")
    }
    // Gameplay release-to-rearm remains strict after source/connection replacement.
    for mode in [NativeGameBindings.Mode.foot,.vehicle("car"),.swim,.jetpack,.parachute,.climb] {
        let (h,p)=setup();h.context.mode=mode
        if case .vehicle=mode{h.currentVehicle=Vehicle(id:"new-owner",code:"596");h.renderer?.vehicleKind="car"}
        p.buttonX.isPressed=true;p.rightTrigger.isPressed=true;p.leftThumbstickButton?.isPressed=true;p.leftThumbstick.yAxis.value=0.7
        h.network.isReady=false;h.resetControls();_ = h.poll();h.network.isReady=true;h.resetControls()
        for i in 0..<3 {let f=h.poll(milliseconds:Double(i*100));check(!f.allowed && !f.firing && !f.horn && !f.siren,"held gameplay stays unarmed after reconnect")}
        check(h.renderer?.jumps==0 && !h.events.contains(.attack),"no stale jump/fire dispatch")
        p.neutral();_ = h.poll(milliseconds:350);let neutral=h.poll(milliseconds:360);check(neutral.allowed,"genuine full neutral rearms")
    }
    do {let (h,p)=setup();h.currentVehicle=Vehicle(id:"emergency",code:"596");h.context.mode = .vehicle("car")
        p.leftThumbstickButton?.isPressed=true;_ = h.poll(milliseconds:0);h.network.isReady=false;h.resetControls();_ = h.poll(milliseconds:50)
        h.network.isReady=true;h.resetControls();_ = h.poll(milliseconds:100);p.neutral();let f=h.poll(milliseconds:150)
        check(!f.siren,"canceled held horn cannot become a stale short-tap siren edge")
        p.leftThumbstickButton?.isPressed=true;_ = h.poll(milliseconds:200);p.leftThumbstickButton?.isPressed=false;let tapped=h.poll(milliseconds:250)
        check(tapped.siren,"fresh real horn tap retains siren mapping")}
    do {let (h,p)=setup();p.buttonX.isPressed=true;_ = h.poll();check(h.renderer?.jumps==1,"fresh X still jumps")
        p.neutral();_ = h.poll();p.rightTrigger.isPressed=true;_ = h.poll();_ = h.poll();check(h.events.filter{$0 == .attack}.count==1,"fresh RT preserves native edge ownership")
        p.neutral();_ = h.poll();p.buttonY.isPressed=true;_ = h.poll();check(h.events.contains(.enter),"fresh Y still enters")}
    print("Controller navigation PASS \(checks) literal-owner checks")
}
