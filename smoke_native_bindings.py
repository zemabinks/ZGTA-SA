#!/usr/bin/env python3
"""Pure controls plus the actual extracted native dispatch/equip methods."""
import hashlib,json,pathlib,shutil,subprocess,tempfile
ROOT=pathlib.Path(__file__).resolve().parent
OUT=ROOT/'local-only/native-physics/tests/bindings'
OUT.mkdir(parents=True,exist_ok=True)
FILES=['ios/App/NativeGameBindings.swift','ios/App/NativeRadioSelection.swift','ios/App/NativeGameInput.swift',
       'ios/App/NativeGameViewController.swift','ios/App/NativePausePanel.swift','ios/App/NativeVehicleRadio.swift',
       'smoke_native_bindings.swift','smoke_native_bindings.py']
inputs={p:(ROOT/p).read_bytes() for p in FILES}
vc=inputs['ios/App/NativeGameViewController.swift'].decode()
pause=inputs['ios/App/NativePausePanel.swift'].decode()
def extract(marker,source=vc):
    start=source.index(marker);brace=source.index('{',start);depth=1;end=brace+1
    while depth:
        depth += (source[end]=='{')-(source[end]=='}');end += 1
    return source[start:end].replace('private ','').replace('@objc ','')
methods='\n'.join(extract(x) for x in ['private var canNavigateMenus:','private var acceptsHeldInput:','private var bindingContext:','private func performBinding(','private func cycleWeapon(','private func sendWeaponSelection(','@objc private func jump()','override func pressesBegan(','override func pressesEnded('])
attack_start=vc.index('        if NativeGameBindings.shouldRequestAttack(')
attack_end=vc.index('\n',vc.index('        lastAttackButton = gamepadAttacking',attack_start))
attack_block=vc[attack_start:attack_end]
raw_trigger=next(line.strip() for line in vc.splitlines() if line.strip().startswith('renderer?.weaponTriggerHeld = canFight'))
touch_held=next(line.strip() for line in vc.splitlines() if line.strip().startswith('if acceptsInput && firePressed &&'))
attack_methods='''
    func pollAttack(_ held:Bool) {
        let gamepadAttacking=held,canFight=true,firePressed=false
'''+attack_block+'\n'+raw_trigger+'''
    }
    func pollTouchHeld(_ held:Bool) {
        let acceptsInput=true,firePressed=held
'''+touch_held+'''
    }
'''
fight_start=vc.index('        let canFight = acceptsInput')
fight_end=vc.index('\n        if !canFight',fight_start)
fight_method='''
    func fightAllowed(_ acceptsInput:Bool=true)->Bool {
'''+vc[fight_start:fight_end]+'''
        return canFight
    }
'''
pause_harness='''
class PauseHarness:FakeResponder {
    let escapeHandoff:NativeModalKeyHandoff
    var dismissed=0
    init(_ state:NativeModalKeyHandoff){escapeHandoff=state;super.init()}
    func dismiss(animated:Bool){dismissed += 1}
'''+extract('override func pressesBegan(',pause)+'\n'+extract('override func pressesEnded(',pause)+'\n}\n'
assert 'escapeHandoff=' not in extract('override func viewDidAppear(',pause),'modal appearance must never reseed copied key state'
pad_lines='\n'.join(next(line.strip() for line in vc.splitlines() if line.strip().startswith(name+' = pad.')) for name in ['gamepadRunning','gamepadHop','gamepadJumping'])
start=vc.index('        renderer?.vehicleHandbrake = acceptsInput')
brake=vc[start:vc.index('\n        renderer?.vehicleControllerInput',start)].strip()
hop=next(line.strip() for line in vc.splitlines() if line.strip().startswith('renderer?.vehicleHop = acceptsInput'))
bicycle='''
struct PadButton {var isPressed:Bool=false}
struct ActualPad {var buttonA=PadButton(),buttonX=PadButton()}
func actualBicycle(_ pad:ActualPad,context:NativeGameBindings.Context,acceptsInput:Bool=true,bunnyHopPressed:Bool=false,keyCodes:Set<Int>=[])->(Bool,Bool,Bool) {
    var gamepadRunning=false,gamepadHop=false,gamepadJumping=false
    let handbrakePressed=false,currentVehicle:Int?=context.driving ? 1:nil
    let keyboard=NativeGameBindings.keyboard(keyCodes,context:context),renderer:FakeRenderer?=FakeRenderer()
'''+pad_lines+'\n'+brake+'\n'+hop+'''
    return (renderer!.vehicleHop,renderer!.vehicleHandbrake,gamepadRunning)
}
'''
stub=r'''
struct Row {let id:Int}
struct RawKey:Hashable {let rawValue:Int;static let keyboardEscape=RawKey(rawValue:41)}
typealias UIKeyboardHIDUsage=RawKey
struct FakeKey:Hashable {let keyCode:RawKey}
struct UIPress:Hashable {let key:FakeKey?;init(_ raw:Int){key=FakeKey(keyCode:RawKey(rawValue:raw))}}
struct UIPressesEvent {}
class FakeResponder {
    func pressesBegan(_ presses:Set<UIPress>,with event:UIPressesEvent?) {}
    func pressesEnded(_ presses:Set<UIPress>,with event:UIPressesEvent?) {}
}
class FakeWeapons {var synchronized=true;var selected=0;var weapons=[Row(id:0),Row(id:22),Row(id:25)]}
class FakeNetwork {var isReady=true;var inventoryConnection:String?="one";var resyncs=0,health=100;var passive=false;func requestInventoryResync(){resyncs += 1}}
class FakeGameplay {
    var state:[String:Any]=[:]
    var requests:[(String,[String:Any],(Bool?)->Void)]=[]
    func perform(_ action:String,payload:[String:Any],completion:@escaping(Bool?)->Void){requests.append((action,payload,completion))}
}
class FakeRenderer {
    var vehicleKind="car",isClimbing=false,swimming=false,isChuting=false,wearingJetpack=false,hasLandingGear=false,hasJetNozzle=false,vehicleLights=false
    var cancels=0,cameras=0,jumps=0,alternates=0
    var canNativeFootMeleeGuard=false
    var hasNativeFootWeaponTiming=false,hasNativeFootMeleeTiming=false,weaponTriggerHeld=false
    var hasVehicleWorkingControls=false,vehicleWorkingIsTow=false,canUnhitchVehicle=false,unhitches=0
    func releaseVehicleCoupling(secondOnly:Bool=false){unhitches+=1}
    var vehicleHop=false,vehicleHandbrake=false
    func cancelWeaponInput(){cancels += 1}
    func cycleCameraView(){cameras += 1}
    func jump(){jumps += 1}
    func requestFootMeleeAttack(alternate:Bool=false)->Bool {if alternate{alternates += 1};return false}
}
enum State {case normal}
class FakeButton {func setTitle(_ text:String,for state:State){}}
class FakeRadio {var stationName="radio",previousCount=0;func previous(){previousCount += 1}}
class FakeStatus {var text=""}
class FakeView {var window:Int?=1}
class Harness:FakeResponder {
    let viewIfLoaded:FakeView?=FakeView()
    var currentVehicle:Int?,renderer:FakeRenderer?=FakeRenderer()
    var applicationActive=true,presentedViewController:Int?,heldKeys:Set<RawKey>=[],touchMeleeGuard=false,lastGamepadAim=false,usingMelee=true
    var pauseEscapeHandoff:NativeModalKeyHandoff?
    var lastAttackButton=false
    let status=FakeStatus()
    let weapons=FakeWeapons(),network=FakeNetwork(),gameplay=FakeGameplay(),radio=FakeRadio(),radioButton=FakeButton(),weaponCycle=NativeWeaponCycleQueue()
    var events:[String]=[]
    func toggleCrouch(){events.append("crouch/dive")};func toggleVehicle(){events.append("enter/drop")}
    func reload(){events.append("reload")};func performNearbyMissionAction(){events.append("action")};func openGameplay(){events.append("jobs")}
    func openChat(){events.append("chat")};func openMap(){events.append("map")};func openAnimations(){events.append("animations")}
    func toggleGear(){events.append("gear")};func nextRadioStation(){events.append("radioNext")};func openPause(){events.append("pause")};func attack(){events.append("attack")}
    func cycleCameraPreference(){renderer?.cycleCameraView()}
'''
integration=r'''
let offline=Harness()
offline.network.isReady=false
offline.performBinding(.attack);offline.performBinding(.jump)
check(offline.events.isEmpty && offline.renderer?.jumps==0,"offline gameplay blocked by actual computed readiness")
offline.performBinding(.pause)
check(offline.events==["pause"],"offline player can still open game menu")
offline.events=[];offline.pressesBegan([UIPress(26)],with:nil)
check(offline.heldKeys.isEmpty,"offline keyboard movement not latched")
offline.network.isReady=true;offline.pressesBegan([UIPress(26)],with:nil)
check(!offline.heldKeys.isEmpty,"fresh ready keyboard movement resumes")
offline.presentedViewController=1;offline.performBinding(.pause)
check(offline.events.isEmpty,"offline exception cannot open nested pause over modal")
let h=Harness()
h.performBinding(.jump);h.performBinding(.enter);h.performBinding(.pause)
check(h.renderer?.jumps==1 && h.events==["enter/drop","pause"],"actual VC dispatch targets")
h.presentedViewController=1;h.performBinding(.attack)
check(h.events.count==2,"actual dispatch suppresses overlay/background input")
h.presentedViewController=nil
h.gameplay.state=["weaponInventory":["weapons":[["id":25,"slot":3],["id":0,"slot":0],["id":22,"slot":2]]]]
h.performBinding(.weaponNext);h.performBinding(.weaponNext);h.performBinding(.weaponPrevious)
check(h.gameplay.requests.count==1,"actual VC serializes equip HTTP calls")
for expected in [22,25,22] {
    let request=h.gameplay.requests.removeFirst()
    check(request.0=="weapon.select" && request.1["weapon"] as? Int==expected,"actual backend action/payload and requested cursor")
    h.weapons.selected=expected;request.2(true)
}
check(h.gameplay.requests.isEmpty && !h.weaponCycle.busy,"actual dispatch drains equip queue")
h.performBinding(.weaponNext)
let pending=h.gameplay.requests.removeFirst();h.weaponCycle.cancel();pending.2(true)
check(!h.weaponCycle.busy && h.gameplay.requests.isEmpty,"actual cancellation does not emit queued mutations")
h.performBinding(.weaponNext)
let unknown=h.gameplay.requests.removeFirst();unknown.2(nil)
check(h.network.resyncs==1 && !h.weaponCycle.busy,"unknown selection requests authoritative resync")
h.performBinding(.weaponNext)
let stale=h.gameplay.requests.removeFirst();h.network.inventoryConnection="two";h.weaponCycle.disconnected();stale.2(true)
check(h.gameplay.requests.isEmpty && !h.weaponCycle.busy,"late completion from old connection discarded")
h.currentVehicle=1;h.renderer?.vehicleKind="plane";h.renderer?.hasLandingGear=true
check(h.bindingContext.aircraft && h.bindingContext.landingGear,"actual renderer context enters aircraft")
h.currentVehicle=nil;h.renderer?.isClimbing=true
check(h.bindingContext.mode == .climb,"actual renderer context prioritizes climb")
print("PASS: actual extracted VC dispatch/context/equip integration; total \(checks) checks")
let bike=NativeGameBindings.Context(mode:.vehicle("bicycle"))
var pedalA=ActualPad();pedalA.buttonA.isPressed=true
var brakeX=ActualPad();brakeX.buttonX.isPressed=true
let bikeA=actualBicycle(pedalA,context:bike),bikeX=actualBicycle(brakeX,context:bike)
check(bikeA.0 && !bikeA.1 && !bikeA.2,"actual A/Cross charges hop without brake or duplicate generic sprint/pedal")
check(!bikeX.0 && bikeX.1,"actual X/Square brakes without charging bunny hop")
let blocked=actualBicycle(pedalA,context:bike,acceptsInput:false)
check(!blocked.0 && !blocked.1,"overlay blocks actual bicycle controls")
check(actualBicycle(.init(),context:bike,bunnyHopPressed:true).0,"existing touch fire control delivers separate hop intent")
check(!actualBicycle(pedalA,context:NativeGameBindings.Context(mode:.vehicle("car"))).0,"car A cannot charge a bicycle hop")
for k in [NativeGameBindings.Key.control,.keypadZero] {
    check(actualBicycle(.init(),context:bike,keyCodes:[k.rawValue]).0,"actual PC secondary-fire routing reaches bicycle hop")
    check(!actualBicycle(.init(),context:bike,acceptsInput:false,keyCodes:[k.rawValue]).0,"overlay suppresses held PC hop")
}
print("PASS: actual extracted A-hop/X-brake/touch/overlay adapter; total \(checks) checks")
let guardedInput=Harness();guardedInput.renderer?.canNativeFootMeleeGuard=true
guardedInput.pressesBegan([UIPress(57),UIPress(225)],with:nil)
check(guardedInput.renderer?.jumps==0,"actual simultaneous aim+Shift batch blocks rather than jumps")
guardedInput.heldKeys=[]
guardedInput.pressesBegan([UIPress(9),UIPress(57)],with:nil)
check(guardedInput.renderer?.alternates==1 && guardedInput.events.isEmpty,"actual aim+F cannot enter a vehicle or silently fire normally")
check(guardedInput.status.text.contains("NOT AVAILABLE"),"unsupported special profile is explicit")
let unsupported=Harness()
unsupported.pressesBegan([UIPress(57),UIPress(225)],with:nil)
check(unsupported.renderer?.jumps==1,"unsupported guard profile retains normal jump")
let modalState=NativeModalKeyHandoff(pressed:true),presenter=Harness()
presenter.pauseEscapeHandoff=modalState
presenter.pressesEnded([UIPress(41)],with:nil) // real presenter method during presentation
check(modalState.press(),"actual presenter key-up transfers to the delayed modal")
check(!modalState.press(),"modal repeat is not a new press")
print("PASS: actual extracted key-batch/guard/special/modal-handoff; total \(checks) checks")
for melee in [false,true] {
    let firing=Harness()
    firing.renderer?.hasNativeFootMeleeTiming=melee
    firing.renderer?.hasNativeFootWeaponTiming = !melee
    for _ in 0..<120 {firing.pollAttack(true)}
    check(firing.events==["attack"],"actual native keyboard/pad held trigger emits exactly one request")
    check(firing.renderer?.weaponTriggerHeld==true,"actual raw held trigger remains available to source timing")
    firing.pollAttack(false);firing.pollAttack(true)
    check(firing.events==["attack","attack"],"release and re-press begins next native intent")
    let count=firing.events.count
    for _ in 0..<120 {firing.pollTouchHeld(true)}
    check(firing.events.count==count,"actual touch-held path does not continuously re-buffer native melee/gun")
}
print("PASS: actual extracted held-trigger edge/touch timing; total \(checks) checks")
let detonatorInput=Harness();detonatorInput.weapons.selected=40
for _ in 0..<120 {detonatorInput.pollAttack(true);detonatorInput.pollTouchHeld(true)}
check(detonatorInput.events==["attack"],"actual detonator held trigger must stay one edge action")
detonatorInput.pollAttack(false);detonatorInput.pollAttack(true)
check(detonatorInput.events==["attack","attack"],"fresh detonator press did not rearm")
let workingInput=Harness();workingInput.currentVehicle=1;workingInput.renderer?.hasVehicleWorkingControls=true
workingInput.renderer?.vehicleWorkingIsTow=true;workingInput.renderer?.canUnhitchVehicle=true
check(workingInput.bindingContext.working && workingInput.bindingContext.workingIsTow && workingInput.bindingContext.hasCoupling,"actual context omitted working/coupling metadata")
workingInput.performBinding(.unhitch);check(workingInput.renderer?.unhitches==1,"actual binding dispatch did not release coupling")
for releaseBeforeAppearance in [false,true] {
    let shared=NativeModalKeyHandoff(pressed:true),presenter=Harness(),panel=PauseHarness(shared)
    presenter.pauseEscapeHandoff=shared
    panel.pressesBegan([UIPress(41)],with:nil) // opening held repeat
    check(panel.dismissed==0,"actual modal suppresses opening held Escape")
    // Whether UIKit appearance precedes or follows this key-up, the actual
    // viewDidAppear method has no state reseed and both responders share it.
    presenter.pressesEnded([UIPress(41)],with:nil)
    panel.pressesBegan([UIPress(41)],with:nil)
    check(panel.dismissed==1,"actual presenter-to-modal handoff accepts first new press; early release=\(releaseBeforeAppearance)")
    panel.pressesBegan([UIPress(41)],with:nil)
    check(panel.dismissed==1,"actual modal autorepeat cannot resume twice")
    panel.pressesEnded([UIPress(41)],with:nil)
    panel.pressesBegan([UIPress(41)],with:nil)
    check(panel.dismissed==2,"actual panel key-up rearms the next press")
}
let touchPanel=PauseHarness(NativeModalKeyHandoff())
touchPanel.pressesBegan([UIPress(41)],with:nil)
check(touchPanel.dismissed==1,"touch-opened menu resumes on its first Escape")
print("PASS: actual extracted modal/presenter key-up lifecycle; total \(checks) checks")
let eligibility=Harness();eligibility.renderer?.wearingJetpack=true
eligibility.renderer?.hasNativeFootMeleeTiming=true
check(eligibility.fightAllowed(),"actual grounded worn-pack melee capability is not cancelled by gun-only gate")
eligibility.renderer?.hasNativeFootMeleeTiming=false
check(!eligibility.fightAllowed(),"unsupported airborne pack melee stays blocked")
eligibility.renderer?.hasNativeFootWeaponTiming=true
check(eligibility.fightAllowed(),"eligible pack arm-gun remains supported")
eligibility.renderer?.isChuting=true;check(!eligibility.fightAllowed(),"parachute combat stays blocked")
eligibility.renderer?.isChuting=false;eligibility.renderer?.swimming=true;check(!eligibility.fightAllowed(),"swim combat stays blocked")
eligibility.renderer?.swimming=false;eligibility.renderer?.isClimbing=true;check(!eligibility.fightAllowed(),"climb combat stays blocked")
eligibility.renderer?.isClimbing=false;check(!eligibility.fightAllowed(false),"overlay/background combat stays blocked")
print("PASS: actual extracted native combat-context capability gate; total \(checks) checks")
'''
required=['NativeGameBindings.keyAction(Int(code.rawValue),context:context)','NativeGameBindings.keyboard(Set(heldKeys.map','NativeGameBindings.padActions(buttons,previous:previousPad,context:padContext)','NativeGameBindings.padLook(buttons,context:context)','gamepadJumping = pad.buttonX.isPressed','pad.buttonB.isPressed && context.mode != .swim','self.weaponCycle.disconnected()','renderer?.walkHeld = acceptsInput && currentVehicle == nil && keyboard.walk','panel.escapeHandoff=escapeState','pauseEscapeHandoff?.release()']
assert all(x in vc for x in required),'VC adapter no longer routes the tested bindings'
assert 'case .keyboardF: openGameplay()' not in vc and 'gamepadJumping = pad.buttonB' not in vc
radio=inputs['ios/App/NativeVehicleRadio.swift'].decode()
assert 'func previous() { cycle(-1) }' in radio and 'NativeRadioSelection.cycle(stationID, choices: choices, direction: direction)' in radio
assert 'Array(1...11) + [13]' in radio and '[12, 13]' in radio,'test station rings must track actual source'
assert 'button.pressedChangedHandler' in pause and 'NativeReleaseEdge(pressed:button.isPressed)' in pause and '.keyboardEscape' in pause
with tempfile.TemporaryDirectory(prefix='snapshot-',dir=OUT) as tmp:
    tmp=pathlib.Path(tmp);sources=[]
    names=['NativeGameBindings.swift','NativeRadioSelection.swift','NativeGameInput.swift']
    for name in names:
        dest=tmp/name;dest.write_bytes(inputs['ios/App/'+name]);sources.append(str(dest))
    (tmp/'main.swift').write_text(inputs['smoke_native_bindings.swift'].decode()+'\n'+stub+methods+attack_methods+fight_method+'\n}\n'+pause_harness+bicycle+integration)
    subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(OUT/'module-cache'),*sources,str(tmp/'main.swift'),'-o',str(tmp/'verify')],check=True)
    result=subprocess.run([str(tmp/'verify')],text=True,capture_output=True)
    print(result.stdout,end='');print(result.stderr,end='')
    result.check_returncode()
    (OUT/'report.json').write_text(json.dumps({'pass':True,
        'sourceSHA256':{p:hashlib.sha256(value).hexdigest() for p,value in inputs.items()},
        'liveFilesStillMatchSnapshot':{p:(ROOT/p).read_bytes()==value for p,value in inputs.items()},
        'result':result.stdout,'physicalControllerVerified':False},indent=2)+'\n')
