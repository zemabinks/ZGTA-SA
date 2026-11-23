#!/usr/bin/env python3
"""Exercise actual VC melee dispatch with actual targeting and inventory state."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import hashlib,json,pathlib,subprocess,time
ROOT=pathlib.Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/native-physics/tests/melee-delivery'
OUT.mkdir(parents=True,exist_ok=True)
vc=(ROOT/'ios/App/NativeGameViewController.swift').read_text()
def extract(marker):
    start=vc.index(marker);brace=vc.index('{',start);depth=1;end=brace+1
    while depth:
        depth+=(vc[end]=='{')-(vc[end]=='}');end+=1
    return vc[start:end].replace('@objc ','').replace('private ','')
methods='\n'.join(extract(m) for m in ['@objc private func attack()','private var meleeCandidates:', 'private func consumeFootMeleeHit('])
profile=(ROOT/'ios/App/NativeGunAnimation.swift').read_text().split('final class NativeGunAnimation')[0]
stub=r'''
import Foundation
import simd
struct ServerAddress {func path(_ path:String)->URL{URL(string:"http://127.0.0.1/"+path)!}}
// This catalog-only VC dispatch carrier cannot load resources. Compiling the
// full resource session would also admit Store/verifier/engine activation.
// Any accidental convenience-init/server-loader call must fail, never return
// a successful or no-op task. Production transport is tested separately.
enum NativeResourceTransport {
 static func dataTask(with url:URL,completion:@escaping(Data?,URLResponse?,Error?)->Void)->URLSessionDataTask {
  preconditionFailure("Network resource loading is forbidden in the catalog-only melee dispatch fixture")
 }
}
struct RemotePlayer {
 var id:String;var name="Fixture";var position:SIMD3<Float>;var heading:Float=0
 var code="s7";var ridingVehicleID:String?;var crouching=false;var down=0;var life=100;var passive=false
}
class Network {
 var usesClientOwnedWeapons=false
 var health=100,passive=false,hits:[String]=[],reservations=0,connected=true,strikes=0,detonations=0
 var orderedPlayers:[RemotePlayer]=[]
 var players:[String:RemotePlayer]{Dictionary(uniqueKeysWithValues:orderedPlayers.map{($0.id,$0)})}
 func sendMeleeHit(to id:String,weapon:Int=0)->Bool{guard connected else{return false};hits.append(id);return true}
 func recordMeleeStrike(weapon:Int)->Bool{guard connected else{return false};strikes+=1;return true}
 func reserveShot()->NativeShotTicket?{reservations+=1;return nil}
 func respawn(){health=100}
 func detonateSatchels(){detonations+=1}
}
class Renderer {
 var people:()->[RemotePlayer]={[]}
 var presentedRemotePlayers:[RemotePlayer]{people()}
 var remotePlayers:[RemotePlayer]{people()}
 // ACTUAL_PASSIVE_ADMISSION
 var presentedAmbientPedestrians:[NativeAmbientPedestrians.Frame]=[]
 var isChuting=false,swimming=false,isClimbing=false,wearingJetpack=false,crouching=false
 // These are observed public Renderer outputs. The real eligibility and
 // actual Renderer wrapper have a separate CLP/source dispatch gate.
 var canRequestFootWeaponFire=true,canEmitFootCombatMarker=true,canUseFootUtility=true
 var hasNativeFootWeaponTiming=false,hasNativeFootMeleeTiming=true,visible=true,requests=0
 func openParachute(){};func exitVehicle(){};func teleport(x:Int,y:Int,z:Int){}
 func requestFootWeaponFire()->Bool{false}
 func requestFootMeleeAttack(alternate:Bool=false)->Bool{requests+=1;return false}
 func hasClearShot(from:SIMD3<Float>,to:SIMD3<Float>)->Bool{visible}
 func fireWeapon(clip:String,duration:Float){}
}
class Queue {var busy=false}
class Audio {var hits=0;func meleeHit(){hits+=1}}
class Status {var text:String?}
enum ControlState{case normal}
class Button {func setTitle(_ name:String,for state:ControlState){}}
class Radio {func stop(){}}
struct Ray{}
struct NativeWeaponAnimation {var fire="",crouchFire="";static func forWeapon(_ weapon:Int)->Self{Self()}}
class Harness {
 var acceptsHeldInput=true,applicationActive=true,presentedViewController:Int?,currentVehicle:Int?
 var renderer:Renderer?=Renderer(),lastAttackTime=0.0
 let network=Network(),weaponCycle=Queue(),audio=Audio(),status=Status(),vehicleButton=Button(),radio=Radio()
 let weapons=NativeWeaponState(catalog:[.init(id:22,name:"Synthetic gun",model:"",range:40,capacity:17,interval:0.3,animation:"fixture",fireKind:"INSTANT_HIT"),.init(id:40,name:"Detonator",model:"",range:0,capacity:1,interval:0.3,animation:"",fireKind:"USE")],allowLegacySnapshots:true)
 init(){renderer?.people = {[weak self]in self?.network.orderedPlayers ?? []}}
 var usingPistol:Bool{weapons.current.isGun}
 func setDrivingControls(_ value:Bool){};func updateWeaponHUD(){}
 func currentShotRay(weapon:Int,left:Bool)->Ray?{Ray()}
 func emitWeaponShot(weapon:Int,left:Bool,ticket:NativeShotTicket?,ray:Ray){}
'''
tests=r'''
var checks=0
func check(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
let h=Harness();h.weapons.apply(["revision":1,"selected":0,"weapons":[]])
let event=NativeMeleeEvent(weapon:0,attack:1,aside:nil,feet:.zero,heading:0,range:1,radius:0.3,simulationTime:1)
h.network.orderedPlayers=[.init(id:"target",position:SIMD3(0,1,0))]
for _ in 0..<100{h.attack()}
check(h.renderer!.requests==100,"Press did not reach animation request")
check(h.network.hits.isEmpty && h.network.reservations==0 && h.audio.hits==0,"Rejected animation request caused damage or reserved ammunition")
check(h.consumeFootMeleeHit(event) && h.network.hits==["target"] && h.audio.hits==1,"Actual marker did not dispatch one hit")
let beforeStunHits=h.network.hits.count,beforeStunStrikes=h.network.strikes
h.renderer!.canEmitFootCombatMarker=false
check(!h.consumeFootMeleeHit(event) && h.network.hits.count==beforeStunHits && h.network.strikes==beforeStunStrikes,"VC bypassed the Renderer combat-marker ownership boundary")
h.renderer!.canEmitFootCombatMarker=true
check(h.network.strikes==1,"A hit marker did not advance exactly one remote strike")
check(h.network.reservations==0 && h.weapons.pendingShotCount==0,"Melee marker consumed a gun sequence")
for blocked in 0..<9 {
 h.applicationActive=true;h.presentedViewController=nil;h.currentVehicle=nil;h.weaponCycle.busy=false
 h.network.health=100;h.network.passive=false;h.renderer!.swimming=false;h.renderer!.isChuting=false;h.renderer!.hasNativeFootMeleeTiming=true
 switch blocked {
 case 0:h.applicationActive=false
 case 1:h.presentedViewController=1
 case 2:h.currentVehicle=1
 case 3:h.weaponCycle.busy=true
 case 4:h.network.health=0
 case 5:h.network.passive=true
 case 6:h.renderer!.swimming=true
 case 7:h.renderer!.isChuting=true
 default:h.renderer!.hasNativeFootMeleeTiming=false
 }
 let hits=h.network.hits.count
 check(!h.consumeFootMeleeHit(event) && h.network.hits.count==hits,"State transition leaked an old melee marker")
}
h.renderer!.hasNativeFootMeleeTiming=true;h.renderer!.visible=false
let beforeBlocked=h.network.hits.count,beforeStrike=h.network.strikes
check(h.consumeFootMeleeHit(event) && h.network.hits.count==beforeBlocked && h.network.strikes==beforeStrike+1,"Blocked miss did not preserve remote swing while denying damage")
h.renderer!.visible=true;h.network.connected=false
check(!h.consumeFootMeleeHit(event),"Disconnected transport produced a delivered hit")
h.network.connected=true
h.renderer!.wearingJetpack=true
check(h.consumeFootMeleeHit(event),"Grounded worn pack incorrectly blocked otherwise eligible melee")
h.renderer!.wearingJetpack=false
h.network.orderedPlayers=[.init(id:"in-car",position:SIMD3(0,0.5,0),code:"410"),.init(id:"passenger",position:SIMD3(0,0.5,0),ridingVehicleID:"car"),.init(id:"target",position:SIMD3(0,1,0))]
check(h.meleeCandidates.map(\.id)==["target"],"Vehicle occupants entered foot melee candidates")
h.network.orderedPlayers=[.init(id:"wall-nearest",position:SIMD3(0,0.5,0)),.init(id:"clear-farther",position:SIMD3(0.1,1,0))]
h.renderer!.visible=false
let priorHits=h.network.hits.count,priorStrikes=h.network.strikes
check(h.consumeFootMeleeHit(event) && h.network.hits.count==priorHits && h.network.strikes==priorStrikes+1,"Blocked nearest target silently retargeted or lost its remote animation")
h.renderer!.visible=true
h.network.orderedPlayers=[]
h.renderer!.presentedAmbientPedestrians=[.init(id:1,skin:14,seed:1,flags:0,position:SIMD3(0,0.7,0),velocity:.zero,heading:0,state:nil)]
let beforeNPC=h.network.hits.count
check(h.consumeFootMeleeHit(event) && h.network.hits.count==beforeNPC+1 && h.network.hits.last=="p1","Actual VC did not dispatch distinct NPC target")
h.renderer!.presentedAmbientPedestrians=[.init(id:1,skin:14,seed:1,flags:9,position:SIMD3(0,0.7,0),velocity:.zero,heading:0,state:nil)]
// The existing original-style selector intentionally admits corpses for
// ground strikes. A claim is not server health authority; dead-actor damage
// rejection is exercised by the server task/backend gates.
check(h.meleeCandidates.first?.dead==true && NativeMeleeTargeting.groundTarget(probe:event.probe,candidates:h.meleeCandidates,visible:h.renderer!.hasClearShot)?.id=="p1","NPC corpse lost distinct ground-target state")
let beforeCorpseNormal=h.network.hits.count,beforeCorpseSounds=h.audio.hits
check(h.consumeFootMeleeHit(event) && h.network.hits.count==beforeCorpseNormal && h.audio.hits==beforeCorpseSounds,"Normal melee reused the separate corpse provider")
let corpseGround=NativeMeleeEvent(weapon:0,attack:-1,aside:"ground",feet:.zero,heading:0,range:1,radius:0.3,simulationTime:1)
check(h.consumeFootMeleeHit(corpseGround) && h.network.hits.count==beforeCorpseNormal+1 && h.network.hits.last=="p1","Ground strike lost its separate fallen-body query")
h.renderer!.presentedAmbientPedestrians=[]
h.weapons.apply(["revision":2,"selected":22,"weapons":[["id":22,"clip":17,"rest":10]]])
check(!h.consumeFootMeleeHit(event) && h.weapons.rounds==17,"Switched weapon accepted stale melee marker")
h.weapons.setConnection("new-unacknowledged-connection")
check(!h.consumeFootMeleeHit(event),"Unsynchronized inventory emitted melee")
h.weapons.setConnection(nil);h.weapons.apply(["revision":3,"selected":40,"weapons":[["id":40,"clip":1,"rest":0]]])
let priorReservations=h.network.reservations
h.attack();check(h.network.detonations==1 && h.weapons.rounds==1 && h.network.reservations==priorReservations,"Detonator spent a gun round/ticket instead of using its real action")
h.renderer!.canUseFootUtility=false;h.attack();check(h.network.detonations==1,"Detonator bypassed hand/task eligibility")
print("PASS: \(checks) actual VC melee dispatch/state/targeting checks;100 rejected requests cause0 hits and0 gun reservations")
'''
def run():
    folder=OUT/('snapshot-'+str(time.time_ns()));folder.mkdir()
    folder=pathlib.Path(folder)
    from tests.network.smoke_native_remote_motion import block
    admission=block((ROOT/'ios/App/NativeWorldRenderer.swift').read_text(),'    var nonPassiveRemotePlayers:')+'\n'+block((ROOT/'ios/App/NativeWorldRenderer.swift').read_text(),'    var livingRemotePlayers:')
    source=folder/'main.swift';source.write_text(profile+'\n'+stub.replace('// ACTUAL_PASSIVE_ADMISSION',admission)+methods+'\n}\n'+tests)
    files=['NativeInventoryPrediction.swift','NativeOriginalWorldArsenal.swift','NativeWeaponState.swift','NativeMelee.swift','NativeAmbientPedestrianProtocol.swift','NativeAmbientPedestrianPaths.swift','NativeAmbientPedestrians.swift']
    binary=folder/'verify'
    subprocess.run(['xcrun','swiftc','-Onone','-whole-module-optimization','-num-threads','1','-module-cache-path',str(OUT/'modules'),*[str(ROOT/'ios/App'/p) for p in files],str(source),'-o',str(binary)],check=True)
    result=subprocess.run([str(binary)],text=True,capture_output=True,timeout=60)
    (folder/'runtime.log').write_text(result.stdout+result.stderr)
    (folder/'result.json').write_text(json.dumps(dict(status='PASS'if result.returncode==0 else'FAIL',exitCode=result.returncode),indent=2)+'\n')
    print(result.stdout,end='');print(result.stderr,end='');result.check_returncode()
    tracked=['tests/combat/smoke_native_melee_delivery.py','ios/App/NativeWorldRenderer.swift','ios/App/NativeGameViewController.swift','ios/App/NativeGunAnimation.swift',*[f'ios/App/{p}' for p in files]]
    (OUT/'report.json').write_text(json.dumps({'pass':True,'sourceSHA256':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in tracked},'result':result.stdout,'retailRuntimeParity':False,'transportBoundary':'Fail-fast test-only dataTask; any call preconditionFails. Actual catalog constructor/inventory/VC/attack logic compiled; resource loading is not exercised or replaced with successful data.'},indent=2)+'\n')
run()
