#!/usr/bin/env python3
"""Compile actual reload/one-shot ownership methods against an inert audio sink.

No game samples, AVAudioSession, speaker, socket, service or wall-clock sleep.
An optional literal historical source control is never substituted for current.
"""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'local-only/research/combat-audit-117/reload-audio-gate'


def declaration(source, marker):
    start = source.index(marker)
    brace = source.index('{', start)
    depth, quoted, escaped = 0, False, False
    for end in range(brace, len(source)):
        char = source[end]
        if quoted:
            if escaped:
                escaped = False
            elif char == '\\':
                escaped = True
            elif char == '"':
                quoted = False
        elif char == '"':
            quoted = True
        elif char == '{':
            depth += 1
        elif char == '}':
            depth -= 1
            if depth == 0:
                return source[start:end + 1]
    raise ValueError('Unclosed actual source declaration: ' + marker)


STUB = r'''
struct FixtureDeadline {
 var seconds:Double
 static func now()->Self{Self(seconds:0)}
 static func +(lhs:Self,rhs:Double)->Self{Self(seconds:lhs.seconds+rhs)}
}
final class DispatchQueue {
 static let main=DispatchQueue()
 var tasks:[()->Void]=[],deadlines:[Double]=[]
 func asyncAfter(deadline:FixtureDeadline,execute:@escaping()->Void){deadlines.append(deadline.seconds);tasks.append(execute)}
 func drain(){let batch=tasks;tasks=[];batch.forEach{$0()}}
 func clear(){tasks=[];deadlines=[]}
}
enum Sink {static var played:[String]=[],stopped:[String]=[]}
final class AVAudioPlayer {
 let name:String
 var enableRate=false,rate:Float=1,pan:Float=0,volume:Float=1,currentTime:Double=0
 var duration:Double{1}
 weak var delegate:AnyObject?
 init(data:Data)throws{name=String(data:data,encoding:.utf8)!}
 func play(){Sink.played.append(name)}
 func stop(){Sink.stopped.append(name)}
}
final class Graph {
 func stop(){}
 func stopAll(immediate:Bool){}
 func quiet()->Int{0}
 func play(_ data:Data,name:String,rate:Float,gain:Float,pan:Float,rise:Double)->Bool{
  Sink.played.append(name);return true
 }
}
final class Audio {
 struct Fade {let begins:Double,ends:Double;let to:Float}
 var suspended=false,volume:Float=0.7,settingsGain:Float=1
 var reloads:[String:[NSNumber]]=["22":[11,12],"25":[21,22]]
 var oneShots:[ObjectIdentifier:AVAudioPlayer]=[:]
 var oneShotLevels:[ObjectIdentifier:NativeAudioEnvelope]=[:]
 let rateAudio=Graph(),weather=Graph(),vehicleLoops=Graph()
 var contactAudio:Graph?=Graph(),remoteEngines:[String:Int]=[:],flightPackIdle:[String:Double]=[:]
 var loops=Set<String>(),vehicleModel:Int?,distanceSinceStep:Float=0,lastEvent=""
 var deferFetch=false,requests:[String]=[],pending:[(String,(Data?)->Void)]=[]
 func fetch(_ name:String,completion:@escaping(Data?)->Void){
  requests.append(name)
  if deferFetch{pending.append((name,completion))}else{completion(Data(name.utf8))}
 }
 func releaseSamples(){let batch=pending;pending=[];batch.forEach{$0.1(Data($0.0.utf8))}}
 func startFadeTimer(){}
 func clearFades(){}
 func configureSession(){}
 func committed(_ name:String,rate:Float=1){once(name,rate:rate)}
'''

TESTS = r'''
var checks=0
func check(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
func fresh()->Audio{DispatchQueue.main.clear();Sink.played=[];Sink.stopped=[];return Audio()}
let normal=fresh();normal.reload(weapon:22)
check(Sink.played==["143_11"],"normal first phase")
check(DispatchQueue.main.deadlines==[0.42],"existing normal delay must remain unchanged")
DispatchQueue.main.drain()
check(Sink.played==["143_11","143_12"],"normal second phase once")
DispatchQueue.main.drain();check(Sink.played.count==2,"queue drain cannot replay phase")
for boundary in ["weapon switch","death","authoritative teleport","accepted vehicle entry","session replacement","input/task reset"]{
 let audio=fresh();audio.reload(weapon:22);audio.cancelReload()
 DispatchQueue.main.drain()
 check(Sink.played==["143_11"],"old delayed phase survived \(boundary)")
 check(Sink.stopped.isEmpty,"\(boundary) stopped a committed voice")
}
for boundary in ["weapon switch","death","authoritative teleport","accepted vehicle entry","session replacement"]{
 let audio=fresh();audio.deferFetch=true;audio.reload(weapon:22)
 DispatchQueue.main.drain();check(audio.pending.count==2,"both actual phase fetches queued")
 audio.cancelReload();audio.releaseSamples()
 check(Sink.played.isEmpty,"pending sample fetch survived \(boundary)")
}
let beforeTimer=fresh();beforeTimer.deferFetch=true;beforeTimer.reload(weapon:22)
beforeTimer.cancelReload();DispatchQueue.main.drain();beforeTimer.releaseSamples()
check(beforeTimer.requests==["143_11"] && Sink.played.isEmpty,"cancel before timer must reject first fetch completion and avoid second fetch")
let replacement=fresh();replacement.reload(weapon:22);replacement.reload(weapon:25)
DispatchQueue.main.drain()
check(Sink.played==["143_11","143_21","143_22"],"replacement reload must retain only its own queued phase")
let sameID=fresh();sameID.deferFetch=true;sameID.reload(weapon:22)
sameID.cancelReload();sameID.reload(weapon:22);DispatchQueue.main.drain();sameID.releaseSamples()
check(Sink.played==["143_11","143_12"],"same-ID reload is a distinct owner")
for stopKind in [0,1]{
 let audio=fresh();audio.deferFetch=true;audio.reload(weapon:22)
 if stopKind==0{audio.suspend()}else{audio.stop()}
 audio.resume();DispatchQueue.main.drain();audio.releaseSamples()
 check(Sink.played.isEmpty,"stop/suspend then resume revived old reload")
 audio.deferFetch=false;audio.reload(weapon:25);DispatchQueue.main.drain()
 check(Sink.played==["143_21","143_22"],"fresh reload after resume must work")
}
let independent=fresh();independent.deferFetch=true;independent.reload(weapon:22)
independent.committed("accepted-shot");independent.committed("accepted-blast")
independent.committed("rate-shot",rate:3);independent.cancelReload()
DispatchQueue.main.drain();independent.releaseSamples()
check(Sink.played==["accepted-shot","accepted-blast","rate-shot"],"reload cancellation altered unrelated committed audio")
let invalid=fresh();invalid.reload(weapon:22);invalid.reload(weapon:99);DispatchQueue.main.drain()
check(Sink.played==["143_11"],"replacement without reload resources retained an older queued owner")
let absent=fresh();absent.reloads=["22":[11]];absent.reload(weapon:22)
check(DispatchQueue.main.tasks.isEmpty && Sink.played.isEmpty,"incomplete reload resources fabricated a phase")
let inactive=fresh();inactive.suspend();inactive.reload(weapon:22);inactive.resume();DispatchQueue.main.drain()
check(DispatchQueue.main.tasks.isEmpty && Sink.played.isEmpty,"inactive reload request appeared after resume")
let loaded=fresh();loaded.deferFetch=true;loaded.reload(weapon:22)
DispatchQueue.main.drain();loaded.releaseSamples()
check(Sink.played==["143_11","143_12"],"uncancelled deferred loads must complete")
var dead:Audio?=fresh();dead!.reload(weapon:22);dead=nil;DispatchQueue.main.drain()
check(Sink.played==["143_11"],"dead audio owner retained by delayed closure")
print("PASS: \(checks) actual reload/once lifecycle and sample-admission checks; inert audio sink only")
'''

GVC_STUB = r'''
struct Vehicle {let id:String;var code="400"}
final class Label {var text:String?}
enum State {case normal}
final class Button {func setTitle(_ title:String,for state:State){}}
final class Radar {var target:Int?}
final class HUD {
 let radar=Radar()
 func updateVehicle(name:String?,speed:Int){}
 func updateVitals(health:Int,armour:Int){}
}
final class Radio {func enter(model:Int){};func stop(){}}
final class Scene {
 var wearingJetpack=false,isPassenger=false,direction:Float=0,health=100
 var position=SIMD3<Float>.zero
 var equippedWeapon=0
 var onReloadTaskCancelled:(()->Void)?
 var isClimbing=false,swimming=false,isChuting=false,crouching=false,passengerOK=true
 var cancels=0,entries=0,teleports=0
 func setFlightGear(parachute:Bool,jetpack:Bool){}
 func setVehicleCouplingConnection(_ nonce:String?){}
 func cancelWeaponInput(){}
 func cancelReloadAnimation(){cancels+=1}
 func enter(_ source:Vehicle,kind:String){entries+=1}
 func enterPassenger(_ source:Vehicle,seat:Int,kind:String)->Bool{passengerOK}
 func revokePassenger(at point:SIMD3<Float>?=nil){}
 func revokeVehicleForServerPlacement(){}
 func leaveVehicleForOriginalTeleport(){}
 func exitVehicle(){}
 func setOriginalActorEffects(burning:Bool,coughing:Bool){}
 func teleport(x:Float,y:Float,z:Float,direction:Float?=nil){teleports+=1}
 func fireWeapon(clip:String,duration:Double){}
}
final class OwnedWeapons {
 struct Item {let id:Int;var name="Fixture";var capacity=17}
 var selected=22,reloading=false,weapons:[Item]=[],current=Item(id:22),onChange:(()->Void)?
 func setConnection(_ nonce:String?){}
 func reloadOriginal()->Bool{true}
 func beginReloadRequest()->String{reloading=true;return "request"}
 func finishReloadRequest(id:String,succeeded:Bool?){if succeeded != nil{reloading=false}}
 func reviveOriginalWeapons(){}
}
final class Peer {
 var vehicles=["car":Vehicle(id:"car")],usesClientOwnedWeapons=false,positionAcknowledgements=false
 var usesOriginalWorldProtocol=false,originalRespawnWasDead=false,inventoryConnection:String?="peer"
 var onEnter:((String,Bool)->Void)?,onPassengerEnter:((String,Int,Bool)->Void)?
 var onTeleport:((SIMD3<Float>,Float?)->Void)?,onVitals:((Int,Int)->Void)?
 var onInventoryConnection:((String?)->Void)?
 func sendPassengerExit(_ point:SIMD3<Float>,heading:Float){}
 func cancelOriginalFatal(){}
 func detonateSatchels(){}
}
final class Actions {
 var inventoryConnection:String?,pending:[(Bool?)->Void]=[]
 func perform(_ name:String,completion:@escaping(Bool?)->Void){pending.append(completion)}
 func setConnectionReady(_ ready:Bool){}
 func refresh(){}
}
final class WeaponCycle {func disconnected(){}}
final class Effects {func reset(){}}
enum NativeMultiplayerClient {enum ConnectionState {case ready,reconnecting,stopped}}
struct NativeWeaponAnimation {
 var reload="fixture/reload",crouchReload="fixture/crouchReload"
 static func forWeapon(_ id:Int)->Self{Self()}
}
final class Controller {
 let audio=Audio(),weapons=OwnedWeapons(),network=Peer(),gameplay=Actions(),weaponCycle=WeaponCycle()
 var renderer:Scene?=Scene(),currentVehicle:Vehicle?,guardWeapon=22,touchMeleeGuard=false
 let status=Label(),vitals=Label(),gameHUD=HUD(),radio=Radio(),vehicleButton=Button(),attackButton=Button()
 let originalEffects=Effects()
 var previousAudioPosition:Float?,originalExitToken:Int?,lastNetwork=0,lastGameplay=0
 var acceptsHeldInput=true,usingPistol=true,magazine=4,reserve=30,inputResets=0
 func updateWeaponHUD(){}
 func updateRadioControl(){}
 func updateAuxiliaryControls(){}
 func vehicleModelType(_ vehicle:Vehicle)->String{"car"}
 func vehicleModelName(_ vehicle:Vehicle)->String{"Fixture"}
 // This inert input-only adapter cannot cancel reload ownership. The gate
 // separately asserts the complete actual resetControls has no such call.
 func resetControls(){inputResets+=1}
 func setDrivingControls(_ driving:Bool){resetControls()}
 func connectObservers(){
'''

GVC_TESTS = r'''
func controller()->Controller{DispatchQueue.main.clear();Sink.played=[];Sink.stopped=[];let c=Controller();c.connectObservers();return c}
func begin(_ c:Controller){c.audio.reload(weapon:22)}
func drain(){DispatchQueue.main.drain()}
let selected=controller();begin(selected);selected.weapons.selected=25;selected.weapons.onChange?();drain()
check(Sink.played==["143_11"],"actual selected-ID callback retained old phase")
let unchanged=controller();begin(unchanged);unchanged.weapons.onChange?();unchanged.resetControls();drain()
check(Sink.played==["143_11","143_12"],"same-selection snapshot or input/menu reset canceled legitimate reload")
for hp in [100,0]{let c=controller();begin(c);c.network.onVitals?(hp,0);drain()
 check(Sink.played.count==(hp>0 ? 2:1),"actual vitals callback canceled living reload or retained dead reload")}
for accepted in [false,true]{let c=controller();begin(c);c.network.onEnter?("car",accepted);drain()
 check(Sink.played.count==(accepted ? 1:2),"driver denial/acceptance owner boundary")}
for admitted in [false,true]{let c=controller();c.renderer!.passengerOK=admitted;begin(c)
 c.network.onPassengerEnter?("car",1,true);drain()
 check(Sink.played.count==(admitted ? 1:2),"passenger resource denial/acceptance owner boundary")}
let deniedPassenger=controller();begin(deniedPassenger);deniedPassenger.network.onPassengerEnter?("car",1,false);drain()
check(Sink.played.count==2,"denied passenger request canceled a continuing foot reload")
let teleported=controller();begin(teleported);teleported.network.onTeleport?(.zero,nil);drain()
check(Sink.played.count==1 && teleported.renderer!.teleports==1,"actual teleport callback retained reload phase")
let originalTP=controller();begin(originalTP);originalTP.leaveForOriginalTeleport();drain()
check(Sink.played.count==1,"actual original teleport helper retained phase")
let replacedTask=controller();begin(replacedTask);replacedTask.renderer!.onReloadTaskCancelled?();drain()
check(Sink.played.count==1,"actual Renderer task-cancellation binding retained phase")
let respawn=controller();begin(respawn);respawn.network.positionAcknowledgements=true;respawn.finishRespawn();drain()
check(Sink.played.count==1,"actual accepted respawn retained phase")
let nonce=controller();begin(nonce);nonce.network.onInventoryConnection?("new-peer");drain()
check(Sink.played.count==1 && nonce.renderer!.cancels==1,"actual inventory-boundary cancellation missing")
for state in [NativeMultiplayerClient.ConnectionState.ready,.reconnecting]{
 let c=controller();begin(c);c.connectionChanged(state);drain()
 check(Sink.played.count==(state == .ready ? 2:1),"actual session-prefix owner boundary")
}
let rejected=controller();rejected.reload();rejected.gameplay.pending.removeFirst()(false);drain()
check(Sink.played==["143_11"] && rejected.renderer!.cancels==1,"actual HTTP rejection retained delayed phase")
let acceptedReload=controller();acceptedReload.reload();acceptedReload.gameplay.pending.removeFirst()(true);drain()
check(Sink.played==["143_11","143_12"],"actual accepted HTTP reload canceled its phase")
let oldPeer=controller();oldPeer.reload();oldPeer.network.inventoryConnection="replacement"
oldPeer.network.onInventoryConnection?("replacement");oldPeer.audio.reload(weapon:25)
oldPeer.gameplay.pending.removeFirst()(false);drain()
check(Sink.played==["143_11","143_21","143_22"],"stale HTTP result canceled replacement reload")
'''

HISTORICAL = r'''
Sink.played=[];DispatchQueue.main.clear()
let audio=Audio();audio.reload(weapon:22)
// Literal historical production has no reload-cancellation API. A weapon
// selection/task reset therefore cannot alter its already queued callback.
DispatchQueue.main.drain()
precondition(Sink.played==["143_11","143_12"],"historical defect no longer reproduces")
Sink.played=[];DispatchQueue.main.clear()
let stopped=Audio();stopped.reload(weapon:22);stopped.stop();stopped.resume()
DispatchQueue.main.drain()
precondition(Sink.played==["143_11","143_12"],"historical stop/resume resurrection no longer reproduces")
print("PASS historical controls: queued old reload phase and stop/resume resurrection reproduced in literal old methods")
'''


def gvc_carrier(vc):
    callbacks = ['        weapons.onChange =', '        network.onInventoryConnection =',
                 '        network.onEnter =', '        network.onPassengerEnter =',
                 '        network.onTeleport =', '        network.onVitals =',
                 '        renderer?.onReloadTaskCancelled =']
    observers = '\n'.join(declaration(vc, item) for item in callbacks)
    methods = '\n'.join(declaration(vc, item).replace('@objc ', '').replace('private ', '') for item in [
        '    @objc private func reload()', '    private func leaveForOriginalTeleport()',
        '    private func finishRespawn()'])
    # Preserve the exact ready/nonready control-flow prefix, omitting only the
    # unrelated UI/world cleanup tail after cancellation was already admitted.
    connection = declaration(vc, '    private func connectionChanged(')
    prefix = connection[:connection.index('        legacyClassSkin=nil;')] + '\n    }'
    assert 'audio.cancelReload()' in prefix
    return GVC_STUB + observers + '\n}\n' + methods + '\n' + prefix.replace('private ', '') + '\n}\n'


def audio_carrier(source, envelope, historical=False):
    names = ['    private func once(', '    func reload(weapon',
             '    func suspend()', '    func resume()', '    func stop()']
    if not historical:
        names.append('    func cancelReload()')
    methods = '\n'.join(declaration(source, name) for name in names)
    storage = '' if historical else '    private var reloadSerial: UInt64 = 0\n'
    if not historical:
        assert storage.strip() in source
    return envelope + '\n' + STUB + storage + methods + '\n}\n'


def carrier(source, envelope, vc='', historical=False):
    base=audio_carrier(source, envelope, historical=historical)
    if historical:
        return base + HISTORICAL
    return base + gvc_carrier(vc) + TESTS + GVC_TESTS + '\nprint("PASS: \\(checks) total actual Audio and GVC task-boundary checks")\n'


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--historical-root', type=Path)
    args = parser.parse_args()
    inputs = {name: (ROOT / name).read_bytes() for name in [
        'ios/App/NativeGameAudio.swift', 'ios/App/NativeAudioEnvelope.swift',
        'ios/App/NativeGameViewController.swift', 'smoke_native_reload_audio.py']}
    source = inputs['ios/App/NativeGameAudio.swift'].decode()
    vc = inputs['ios/App/NativeGameViewController.swift'].decode()
    assert 'audio.cancelReload()' not in declaration(vc, '    private func resetControls()')
    changed = declaration(vc, '        weapons.onChange =')
    selected = declaration(changed, 'if self.guardWeapon != self.weapons.selected')
    assert 'self.audio.cancelReload()' in selected
    envelope = inputs['ios/App/NativeAudioEnvelope.swift'].decode()
    OUT.mkdir(parents=True, exist_ok=True)
    results = []
    with tempfile.TemporaryDirectory(prefix='actual-source-', dir=OUT) as folder:
        folder = Path(folder)
        modes = [('current', source, False)]
        if args.historical_root:
            old_path = args.historical_root.resolve() / 'ios/App/NativeGameAudio.swift'
            old_bytes = old_path.read_bytes()
            inputs[str(old_path)] = old_bytes
            modes.append(('historical', old_bytes.decode(), True))
        for mode, text, historical in modes:
            work = folder / mode
            work.mkdir()
            entry = work / 'main.swift'
            entry.write_text(carrier(text, envelope, vc=vc, historical=historical))
            binary = work / 'verify'
            build = subprocess.run(['xcrun', 'swiftc', '-whole-module-optimization', '-Onone',
                '-num-threads', '1', '-module-cache-path', str(OUT / 'modules'),
                str(entry), '-o', str(binary)], text=True, capture_output=True, timeout=900)
            (OUT / (mode + '-build.log')).write_text(build.stdout + build.stderr)
            build.check_returncode()
            run = subprocess.run([str(binary)], text=True, capture_output=True, timeout=30)
            (OUT / (mode + '-run.log')).write_text(run.stdout + run.stderr)
            run.check_returncode()
            results.append({'mode': mode, 'output': run.stdout, 'carrierSHA256': hashlib.sha256(entry.read_bytes()).hexdigest()})
            print(run.stdout, end='')
        unchanged = all((Path(name) if Path(name).is_absolute() else ROOT / name).read_bytes() == data for name, data in inputs.items())
        assert unchanged, 'actual source changed during this gate'
        (OUT / 'report.json').write_text(json.dumps({
            'status': 'PASS', 'historicalExecuted': bool(args.historical_root),
            'results': results, 'sourceUnchanged': unchanged,
            'inputSHA256': {name: hashlib.sha256(data).hexdigest() for name, data in inputs.items()},
            'boundary': 'Actual methods and envelope compiled. Audio sink, sample delivery and scheduled-time admission are inert authored adapters. No UIKit, AVAudioSession, resource fetch, speaker or retail timing execution.'
        }, indent=2) + '\n')


if __name__ == '__main__':
    main()
