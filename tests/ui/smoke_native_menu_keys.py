#!/usr/bin/env python3
"""Run real shared latch plus extracted menu/game handlers without opening UI."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,subprocess,tempfile

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/native-physics/tests/menu-keys'
OUT.mkdir(parents=True,exist_ok=True)
paths=['ios/App/NativeDEMenuStyle.swift','ios/App/NativeGameViewController.swift',
       'ios/App/NativeGameBindings.swift','ios/App/HomeViewController.swift','ios/App/MainMenuViewController.swift',
       'test-fixtures/native-menu/core84-responder-handlers.json','tests/ui/smoke_native_menu_keys.py']
inputs={p:(ROOT/p).read_bytes() for p in paths}
style=inputs[paths[0]].decode();vc=inputs[paths[1]].decode()

def extract(source,marker):
    start=source.index(marker);brace=source.index('{',start);depth=1;end=brace+1
    while depth:
        depth+=(source[end]=='{')-(source[end]=='}');end+=1
    return source[start:end].replace('private ','')

panel_methods='\n'.join(extract(style,x) for x in ['override func pressesBegan(','override func pressesEnded(','override func pressesCancelled('])
game_methods='\n'.join(extract(vc,x) for x in ['override func pressesBegan(','override func pressesEnded(','override func pressesCancelled('])
latch_wrapper=extract(style,'enum NativeMenuKeyState {')
main_methods='\n'.join(extract(inputs['ios/App/MainMenuViewController.swift'].decode(),x) for x in ['override func pressesBegan(','override func pressesEnded(','override func pressesCancelled('])
legacy=json.loads(inputs['test-fixtures/native-menu/core84-responder-handlers.json'])
for value in legacy['sources'].values():
    assert hashlib.sha256(value['pressesBegan'].encode()).hexdigest()==value['methodSHA256']
assert 'NativeMenuKeyState.reset()' in inputs['ios/App/HomeViewController.swift'].decode()
assert 'heldKeys.remove(code)' in game_methods

code=r'''
import Foundation
struct UIKeyboardHIDUsage:Hashable {
    let rawValue:Int
    static let keyboardEscape=Self(rawValue:41),keyboardUpArrow=Self(rawValue:82),keyboardDownArrow=Self(rawValue:81)
    static let keyboardLeftArrow=Self(rawValue:80),keyboardRightArrow=Self(rawValue:79),keyboardReturnOrEnter=Self(rawValue:40),keyboardSpacebar=Self(rawValue:44)
}
struct Key:Hashable {let keyCode:UIKeyboardHIDUsage}
struct UIPress:Hashable {let key:Key?;init(_ raw:Int){key=Key(keyCode:UIKeyboardHIDUsage(rawValue:raw))};init(){key=nil}}
struct UIPressesEvent {}
enum UIApplication {static let willResignActiveNotification=Notification.Name("FixtureWillResignActive")}
extension Notification.Name {static let GCKeyboardDidDisconnect=Notification.Name("FixtureKeyboardDisconnected")}
class Responder {
    var parent:Responder?
    var forwardedBegan:[Set<UIPress>]=[]
    func pressesBegan(_ presses:Set<UIPress>,with event:UIPressesEvent?){forwardedBegan.append(presses);parent?.pressesBegan(presses,with:event)}
    func pressesEnded(_ presses:Set<UIPress>,with event:UIPressesEvent?){parent?.pressesEnded(presses,with:event)}
    func pressesCancelled(_ presses:Set<UIPress>,with event:UIPressesEvent?){parent?.pressesCancelled(presses,with:event)}
}
'''+latch_wrapper+r'''
final class Panel:Responder {
    var presentedViewController:Int?
    var closes=0,activations=0,moves=0,adjustments=0
    func closeMenu(){closes+=1};func activateSelection(){activations+=1}
    func moveSelection(_ value:Int){moves+=value};func adjustSelection(_ value:Int){adjustments+=value}
'''+panel_methods+r'''
}
final class Network {var isReady=true,originalInputBlocked=false}
final class Actor {var originalCoughing=false}
final class Game:Responder {
    let network=Network()
    var renderer:Actor?=Actor()
    var applicationActive=true,presentedViewController:Int?,heldKeys:Set<UIKeyboardHIDUsage>=[]
    var pauseEscapeHandoff:NativeModalKeyHandoff?=NativeModalKeyHandoff(pressed:true)
    var bindingContext=NativeGameBindings.Context(),events:[NativeGameBindings.Action]=[]
    func performBinding(_ action:NativeGameBindings.Action){events.append(action)}
    func resetControls(){heldKeys=[]}
'''+game_methods+r'''
}
final class Main:Responder {
    var presentedViewController:Int?,selected=0,activations=0,selections=0
    func select(_ index:Int,sound:Bool){selected=index;selections+=1}
    func activate(_ index:Int){activations+=1}
'''+main_methods+r'''
}
final class LegacyPanel:Responder {
    var presentedViewController:Int?
    var closes=0,activations=0,moves=0,adjustments=0
    func closeMenu(){closes+=1};func activateSelection(){activations+=1}
    func moveSelection(_ value:Int){moves+=value};func adjustSelection(_ value:Int){adjustments+=value}
'''+legacy['sources']['panel']['pressesBegan']+r'''
}
final class LegacyGame:Responder {
    let network=Network()
    var applicationActive=true,presentedViewController:Int?,heldKeys:Set<UIKeyboardHIDUsage>=[]
    var bindingContext=NativeGameBindings.Context(),events:[NativeGameBindings.Action]=[]
    func performBinding(_ action:NativeGameBindings.Action){events.append(action)}
'''+legacy['sources']['game']['pressesBegan']+r'''
}
var count=0
func check(_ condition: @autoclosure()->Bool,_ message:String){count+=1;precondition(condition(),message)}
let esc:Set<UIPress>=[UIPress(41)],confirm:Set<UIPress>=[UIPress(40)],space:Set<UIPress>=[UIPress(44)],up:Set<UIPress>=[UIPress(82)]
NativeMenuKeyState.reset()
let parent=Panel(),child=Panel()
parent.pressesBegan(confirm,with:nil);child.pressesBegan(confirm,with:nil)
check(parent.activations==1 && child.activations==0,"held confirm repeated into destination")
parent.pressesEnded(confirm,with:nil);child.pressesBegan(confirm,with:nil)
check(child.activations==1,"release delivered to presenter did not rearm destination")
child.pressesEnded(confirm,with:nil)
parent.pressesBegan(up,with:nil);child.pressesBegan(up,with:nil)
check(parent.moves == -1 && child.moves==0,"held arrow repeated into submenu")
child.pressesEnded(up,with:nil);child.pressesBegan(up,with:nil)
check(child.moves == -1,"release delivered to destination did not rearm")
child.pressesEnded(up,with:nil)

let game=Game()
for raw in [41,44,40,82,80] {
    NativeMenuKeyState.reset()
    let presses:Set<UIPress>=[UIPress(raw)]
    _=NativeMenuKeyState.press(UIKeyboardHIDUsage(rawValue:raw))
    game.events=[];game.heldKeys=[]
    game.pressesBegan(presses,with:nil)
    check(game.events.isEmpty && game.heldKeys.isEmpty,"menu-owned repeat leaked into game: \(raw)")
    game.pressesEnded(presses,with:nil)
    check(!NativeMenuKeyLatch.isHeld(raw),"game key-up did not release menu ownership")
    game.pressesBegan(presses,with:nil)
    if raw==41 {check(game.events==[.pause],"fresh Escape did not open pause")}
    else {check(game.heldKeys.contains(UIKeyboardHIDUsage(rawValue:raw)),"fresh gameplay key ignored")}
    game.pressesEnded(presses,with:nil)
}

NativeMenuKeyState.reset()
let options=Panel();options.pressesBegan(esc,with:nil)
check(options.closes==1,"Options Escape did not close once")
game.events=[];game.heldKeys=[];game.pressesBegan(esc,with:nil)
check(game.events.isEmpty,"closing Escape auto-repeat reopened pause")
game.pressesEnded(esc,with:nil)
let reopened=Panel();reopened.pressesBegan(esc,with:nil)
check(reopened.closes==1,"reopened Options swallowed first distinct Escape")
reopened.pressesEnded(esc,with:nil)

NativeMenuKeyState.reset()
game.events=[];game.heldKeys=[]
game.pressesBegan(esc,with:nil);game.pressesBegan(esc,with:nil)
check(game.events==[.pause],"normal gameplay Escape repeat changed")
game.pressesEnded(esc,with:nil);game.pressesBegan(esc,with:nil)
check(game.events==[.pause,.pause],"normal pause press/release stopped rearming")
game.pressesEnded(esc,with:nil)

for notification in [UIApplication.willResignActiveNotification,Notification.Name.GCKeyboardDidDisconnect] {
    NativeMenuKeyState.reset();let panel=Panel()
    panel.pressesBegan(confirm,with:nil);panel.pressesBegan(esc,with:nil)
    NotificationCenter.default.post(name:notification,object:nil)
    panel.pressesBegan(confirm,with:nil);panel.pressesBegan(esc,with:nil)
    check(panel.activations==2 && panel.closes==2,"lost release poisoned lifecycle boundary")
}
NativeMenuKeyState.reset()
_=NativeMenuKeyState.press(.keyboardReturnOrEnter);_=NativeMenuKeyState.press(.keyboardEscape)
game.heldKeys=[.keyboardReturnOrEnter,.keyboardEscape]
game.pressesCancelled(esc,with:nil)
check(!NativeMenuKeyLatch.isHeld(40) && !NativeMenuKeyLatch.isHeld(41) && game.heldKeys.isEmpty,"game cancellation left stale ownership")
NativeMenuKeyState.reset()
precondition(count==27,"Existing latch coverage changed")
print("PASS original menu latch: \(count) checks preserved")

// The missing boundary in the old test: super propagates to presenting Home.
let oldHome=LegacyPanel(),oldGame=LegacyGame();oldHome.presentedViewController=1;oldGame.parent=oldHome
oldGame.pressesBegan(esc,with:nil)
check(oldGame.events==[.pause] && oldHome.closes==1,"Exact Core84 Escape specimen did not reproduce dismissal bubble")
NativeMenuKeyState.reset()
let oldConnect=LegacyPanel(),oldSpace=LegacyGame();oldConnect.presentedViewController=1;oldSpace.parent=oldConnect
oldSpace.pressesBegan(space,with:nil)
check(oldConnect.activations==1,"Exact Core84 Space specimen did not reach underlying activation handler")
NativeMenuKeyState.reset()

func gameChain()->(Game,Panel,Main,Responder) {
    let game=Game(),home=Panel(),main=Main(),sink=Responder()
    home.presentedViewController=1;main.presentedViewController=1
    game.parent=home;home.parent=main;main.parent=sink
    return(game,home,main,sink)
}
let (owned,home,title,sink)=gameChain()
owned.pressesBegan(esc,with:nil);owned.pressesBegan(esc,with:nil)
check(owned.events==[.pause] && home.closes==0 && title.activations==0,"Core85 Escape bubbled or failed to pause exactly once")
check(owned.forwardedBegan.isEmpty && sink.forwardedBegan.isEmpty,"Keyboard Escape reached responder super")
owned.pressesEnded(esc,with:nil)
for raw in [44,225,82,40,4] {
    NativeMenuKeyState.reset();let (g,h,m,s)=gameChain();let event:Set<UIPress>=[UIPress(raw)]
    g.pressesBegan(event,with:nil)
    check(g.heldKeys.contains(UIKeyboardHIDUsage(rawValue:raw)),"Owned gameplay keyboard key was discarded: \(raw)")
    check(g.forwardedBegan.isEmpty && h.closes==0 && h.activations==0 && h.moves==0 && m.activations==0 && s.forwardedBegan.isEmpty,"Owned key reached underlying connection/menu: \(raw)")
    if raw==225 {check(g.events==[.jump],"Shift no longer dispatches jump")}
    if raw==40 {check(g.events==[.enter],"Return no longer dispatches enter")}
    g.pressesEnded(event,with:nil)
}
for event in [esc,space,up,confirm] {
    NativeMenuKeyState.reset();let (_,h,m,s)=gameChain()
    h.pressesBegan(event,with:nil)
    check(h.closes==0 && h.activations==0 && h.moves==0 && m.activations==0 && m.selections==0,"Presenting menu handled a child's key")
    check(s.forwardedBegan==[event],"Presenting menu's default forwarding changed")
}
let unknown:Set<UIPress>=[UIPress(4)]
NativeMenuKeyState.reset();let unhandledMenu=Panel(),unhandledSink=Responder();unhandledMenu.parent=unhandledSink
unhandledMenu.pressesBegan(unknown,with:nil)
check(unhandledMenu.closes==0 && unhandledMenu.activations==0 && unhandledSink.forwardedBegan==[unknown],"Menu assigned an action to an unhandled keyboard key")

let nonkey:Set<UIPress>=[UIPress()]
for raw:Int? in [nil,44,41] {
    NativeMenuKeyState.reset();let (g,h,m,s)=gameChain()
    var batch=nonkey;if let raw {batch.insert(UIPress(raw))}
    g.pressesBegan(batch,with:nil)
    check(g.forwardedBegan==[nonkey] && s.forwardedBegan==[nonkey],"Nonkeyboard forwarding lost or carried owned keyboard input")
    check(h.closes==0 && h.activations==0 && m.activations==0,"Nonkeyboard batch activated underlying menus")
}
for boundary in ["offline","inactive","modal","server-freeze","cough"] {
    NativeMenuKeyState.reset();let (g,h,_,s)=gameChain()
    if boundary=="offline"{g.network.isReady=false}
    if boundary=="inactive"{g.applicationActive=false}
    if boundary=="modal"{g.presentedViewController=1}
    if boundary=="server-freeze"{g.network.originalInputBlocked=true}
    if boundary=="cough"{g.renderer?.originalCoughing=true}
    g.pressesBegan(nonkey,with:nil)
    check(g.forwardedBegan==[nonkey] && s.forwardedBegan==[nonkey] && h.closes==0,"Early guard swallowed nonkeyboard event: \(boundary)")
}
NativeMenuKeyState.reset()
print("PASS native menu keys: \(count) actual extracted responder/lifecycle checks")
'''
with tempfile.TemporaryDirectory(prefix='zgtasa-menu-keys-') as temp:
    folder=Path(temp);bindings=folder/'NativeGameBindings.swift';bindings.write_bytes(inputs['ios/App/NativeGameBindings.swift'])
    main=folder/'main.swift';main.write_text(code);exe=folder/'verify'
    subprocess.run(['xcrun','swiftc','-module-cache-path',str(OUT/'module-cache'),str(bindings),str(main),'-o',str(exe)],check=True)
    result=subprocess.run([str(exe)],capture_output=True,text=True)
    print(result.stdout,end='');print(result.stderr,end='')
    (OUT/'report.json').write_text(json.dumps({'status':'PASS' if result.returncode==0 else 'FAIL','output':result.stdout,
        'coverage':['actual menu/shared-HID/game responder handoff','Escape/Space/Return/arrows repeat rejection',
                    'Options close→game key-up→reopen','normal pause Escape unchanged','background/keyboard disconnect/cancel',
                    'exact Core84 bubbling counterexamples','Core85 super→presenting Home→title responder chain',
                    'keyboard ownership and nonkeyboard/mixed/early-guard forwarding'],
        'sourceHashes':{p:hashlib.sha256(data).hexdigest() for p,data in inputs.items()},
        'liveFilesStillMatchSnapshot':{p:(ROOT/p).read_bytes()==data for p,data in inputs.items()},
        'limits':['UIKit notifications/responder events are dispatched into extracted source with small type stubs; physical keyboard acceptance remains separate.']},indent=2)+'\n')
    result.check_returncode()
