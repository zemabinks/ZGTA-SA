#!/usr/bin/env python3
"""Exercise actual VC melee dispatch with actual targeting and inventory state."""
import hashlib,json,pathlib,subprocess,tempfile
ROOT=pathlib.Path(__file__).resolve().parent
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
struct RemotePlayer {
 var id:String;var name="Fixture";var position:SIMD3<Float>;var heading:Float=0
 var code="s7";var ridingVehicleID:String?;var crouching=false;var down=0;var life=100
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
with tempfile.TemporaryDirectory(prefix='snapshot-',dir=OUT) as folder:
    folder=pathlib.Path(folder)
    source=folder/'main.swift';source.write_text(profile+'\n'+stub+methods+'\n}\n'+tests)
    files=['NativeInventoryPrediction.swift','NativeOriginalWorldArsenal.swift','NativeWeaponState.swift','NativeMelee.swift']
    binary=folder/'verify'
    subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(OUT/'modules'),*[str(ROOT/'ios/App'/p) for p in files],str(source),'-o',str(binary)],check=True)
    result=subprocess.run([str(binary)],text=True,capture_output=True);print(result.stdout,end='');print(result.stderr,end='');result.check_returncode()
    tracked=['ios/App/NativeGameViewController.swift','ios/App/NativeGunAnimation.swift',*[f'ios/App/{p}' for p in files]]
    (OUT/'report.json').write_text(json.dumps({'pass':True,'sourceSHA256':{p:hashlib.sha256((ROOT/p).read_bytes()).hexdigest() for p in tracked},'result':result.stdout,'retailRuntimeParity':False},indent=2)+'\n')
