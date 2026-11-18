#!/usr/bin/env python3
"""Actual native dead-attack/respawn callbacks with controlled health ACKs."""
from pathlib import Path
import hashlib,json,subprocess,tempfile

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/native-physics/tests/respawn-dispatch';OUT.mkdir(parents=True,exist_ok=True)
APP=['NativeOriginalWorldVitals','NativeOriginalWorldEffects','ServerAddress','NativeInventoryPrediction','NativeOriginalWorldArsenal','NativeWeaponState','NativeWeaponShotDelivery']
FILES=[f'ios/App/{name}.swift' for name in APP]+['ios/App/NativeGameViewController.swift','ios/App/NativeMultiplayerClient.swift','ios/App/NativeActorAnimation.swift','smoke_native_respawn_dispatch.py']
inputs={p:(ROOT/p).read_bytes() for p in FILES}
def extract(source,marker):
    start=source.index(marker);at=source.index('{',start);depth=1;end=at+1
    while depth:
        depth+=(source[end]=='{')-(source[end]=='}');end+=1
    return source[start:end].replace('@objc ','').replace('private ','')
vc=inputs['ios/App/NativeGameViewController.swift'].decode()
mp=inputs['ios/App/NativeMultiplayerClient.swift'].decode()
prediction=extract(mp,'struct NativeHealthPrediction {')
network_methods='\n'.join(extract(mp,marker) for marker in ['    func cancelOriginalFatal()','    func respawn()','    func syncVitals(','    private func sendHealthRequest(','    @discardableResult private func applyAcknowledgedVitals('])
game_methods='\n'.join(extract(vc,marker) for marker in ['@objc private func attack()','    private func finishRespawn()','    private func leaveForOriginalTeleport()'])
callback='\n'.join(extract(vc,marker) for marker in ['        network.onVitals =','        network.onRespawn ='])
animation=extract(inputs['ios/App/NativeActorAnimation.swift'].decode(),'struct NativeWeaponAnimation {')
SWIFT=r'''
import Foundation
import CoreFoundation
var checks=0
func check(_ value:@autoclosure()->Bool,_ message:String){checks+=1;precondition(value(),message)}
HEALTH_PREDICTION
final class Socket {}
final class DisabledLegacy {func send(_ packet:[String:Any])->Bool{preconditionFailure("Legacy branch in strict self-host test")}}
final class Network {
    var healthPrediction=NativeHealthPrediction(),health=0,armour=25
    var passive=false,isReady=true,usesClientOwnedWeapons=false,transportGeneration:UInt64=1,deliveredRespawnSequence=0
    var positionAcknowledgements=false
    let originalVitals=NativeOriginalWorldVitals()
    var originalRespawnWasDead=false
    var originalRespawnRequested:Double?
    var usesOriginalWorldProtocol=false
    var legacy:DisabledLegacy?
    func clock()->Double{0}
    func sendOriginal(_ packet:[String:Any])->Bool{preconditionFailure("Original branch in strict self-host test")}
    var inventoryConnection:String?="peer-one",socket:Socket?=Socket()
    var onVitals:((Int,Int)->Void)?,onRespawn:(()->Void)?
    var requests:[[String:Any]]=[]
    func send(_ value:[String:Any]){requests.append(value)}
    func reserveShot()->NativeShotTicket?{nil}
    func detonateSatchels(){}
    func begin(_ nonce:String="peer-one",health:Int=0){
        transportGeneration+=1;inventoryConnection=nonce;socket=Socket();deliveredRespawnSequence=0
        healthPrediction.begin(connection:nonce,health:health,armour:25,revision:0,processed:0)
        self.health=health;armour=25
    }
    func disconnect(){transportGeneration+=1;inventoryConnection=nil;socket=nil;isReady=false;healthPrediction.disconnect();deliveredRespawnSequence=0}
    @discardableResult func receive(_ health:Int,processed:Int,revision:Int,respawned:Int?=nil,connection:String="peer-one")->Bool {
        var ack:[String:Any]=["connection":connection,"processed":processed,"revision":revision]
        if let respawned{ack["respawned"]=respawned}
        return applyAcknowledgedVitals(["health":health,"armour":0,"healthAck":ack])
    }
    NETWORK_METHODS
}
enum ControlState {case normal}
final class Button {var title="";func setTitle(_ value:String,for state:ControlState){title=value}}
final class Label {var text=""}
final class Radio {var stops=0;func stop(){stops+=1}}
final class HUD {var samples:[Int]=[],vehicleUpdates=0;func updateVitals(health:Int,armour:Int){samples.append(health)};func updateVehicle(name:String?,speed:Float){vehicleUpdates+=1}}
struct WeaponCycle {var busy=false}
struct Ray {}
final class Renderer {
    var isChuting=false,isClimbing=false,swimming=false,wearingJetpack=false,crouching=false
    var canRequestFootWeaponFire=true,canUseFootUtility=true
    var hasNativeFootWeaponTiming=false,hasNativeFootMeleeTiming=false
    var health=0,exits=0,deploys=0,teleports:[SIMD3<Float>]=[],feet=SIMD3<Float>(100,200,30)
    func openParachute(){deploys+=1}
    func requestFootWeaponFire()->Bool{false}
    func requestFootMeleeAttack()->Bool{false}
    func fireWeapon(clip:String,duration:Float){}
    // Controlled renderer boundary records ownership/effect calls; the actual
    // Renderer implementation is exercised by the original-renderer gate.
    var originalLeaves=0,effectClears=0
    func leaveVehicleForOriginalTeleport(){originalLeaves+=1}
    func setOriginalActorEffects(burning:Bool,coughing:Bool){check(!burning && !coughing,"Respawn re-enabled actor effects");effectClears+=1}
    func exitVehicle(){exits+=1}
    func teleport(x:Float,y:Float,z:Float,direction:Float?=nil){feet=SIMD3(x,y,z);teleports.append(feet)}
}
final class ReloadAudio {var cancels=0;func cancelReload(){cancels+=1}}
final class Game {
    var acceptsHeldInput=true,currentVehicle:Int?=42,renderer:Renderer?=Renderer(),weaponCycle=WeaponCycle()
    let originalEffects=NativeOriginalWorldEffects()
    let audio=ReloadAudio()
    var originalExitToken:UInt64?
    let network:Network,weapons=NativeWeaponState(allowLegacySnapshots:true)
    let status=Label(),vitals=Label(),vehicleButton=Button(),attackButton=Button(),radio=Radio(),gameHUD=HUD()
    var lastAttackTime:Double = -.infinity,resets=0,heldFire=true,drivingChanges:[Bool]=[]
    var usingPistol:Bool{weapons.current.isGun}
    init(_ network:Network=Network()) {self.network=network;installCallbacks()}
    func installCallbacks(){
        CALLBACKS
    }
    func resetControls(){resets+=1;heldFire=false}
    func updateAuxiliaryControls(){} // Actual UI-context dispatch is a separate gate.
    func setDrivingControls(_ driving:Bool){drivingChanges.append(driving)}
    func updateWeaponHUD(){}
    func currentShotRay(weapon:Int,left:Bool)->Ray?{nil}
    func emitWeaponShot(weapon:Int,left:Bool,ticket:NativeShotTicket?,ray:Ray){}
    GAME_METHODS
}
@main enum Verify {
    static func main(){
        let accepted=Game();accepted.network.begin();let initial=accepted.renderer!.feet
        accepted.attack()
        check(accepted.network.requests.count==1 && accepted.network.requests[0]["kind"] as? String=="respawn","Dead attack did not submit one health request")
        check(accepted.network.health==0 && accepted.currentVehicle==42 && accepted.renderer!.feet==initial && accepted.renderer!.exits==0 && accepted.resets==0 && accepted.heldFire,"Respawn request teleported/reset before acceptance")
        check(accepted.status.text=="RESPAWN REQUESTED","Request feedback lost")
        accepted.attack();check(accepted.network.requests.count==1 && accepted.renderer!.teleports.isEmpty,"Held/repeated request duplicated pending respawn")
        let beforeReloadCancels=accepted.audio.cancels
        check(accepted.network.receive(100,processed:1,revision:1,respawned:1),"Accepted acknowledgement was rejected")
        check(accepted.audio.cancels==beforeReloadCancels+1,"Accepted respawn retained queued reload audio")
        check(accepted.network.health==100 && accepted.currentVehicle==nil && accepted.renderer!.exits==1 && accepted.radio.stops==1 && accepted.drivingChanges==[false],"Accepted respawn did not transfer vehicle/control ownership")
        check(accepted.resets==1 && !accepted.heldFire && accepted.renderer!.teleports==[SIMD3(1480,-1738,13)],"Accepted respawn must reset/teleport exactly once")
        check(accepted.status.text=="RESPAWNED AT THE CITY CENTRE" && accepted.vehicleButton.title=="ENTER CAR","Accepted callback presentation missing")
        _=accepted.network.receive(100,processed:1,revision:1,respawned:1)
        check(accepted.resets==1 && accepted.renderer!.teleports.count==1 && accepted.renderer!.exits==1,"Duplicate acknowledgement displaced player again")
        check(accepted.audio.cancels==beforeReloadCancels+1,"Duplicate live acknowledgement canceled a fresh reload owner")

        let rejected=Game();rejected.network.begin();rejected.attack()
        check(rejected.network.receive(0,processed:1,revision:1),"Rejected request was not acknowledged")
        // The real onVitals(0) cancels dead input. It is not finishRespawn and
        // must preserve vehicle/world position until a real accepted respawn.
        check(rejected.network.health==0 && rejected.currentVehicle==42 && rejected.renderer!.feet==initial && rejected.renderer!.teleports.isEmpty && rejected.renderer!.exits==0 && rejected.radio.stops==0 && rejected.drivingChanges.isEmpty,"Rejected respawn executed the respawn reset")
        check(rejected.resets==1 && rejected.status.text=="RESPAWN REQUESTED","Death vitals callback or request state was hidden")
        rejected.attack();check(rejected.network.requests.count==2,"Rejected respawn blocked a fresh retry")
        check(rejected.network.receive(100,processed:2,revision:2,respawned:2),"Retry acceptance rejected")
        check(rejected.renderer!.teleports.count==1 && rejected.currentVehicle==nil,"Retry did not complete exactly once")

        for marker in [nil,0,9] as [Int?] {
            let healed=Game();healed.network.begin();healed.attack()
            check(healed.network.receive(50,processed:1,revision:1,respawned:marker),"Authoritative unrelated heal rejected")
            check(healed.network.health==50 && healed.renderer!.teleports.isEmpty && healed.currentVehicle==42 && healed.resets==0,"Unrelated heal or mismatched respawn marker displaced the player")
        }
        let unsolicited=Game();unsolicited.network.begin()
        check(unsolicited.network.receive(100,processed:0,revision:1,respawned:0),"Server heal without request rejected")
        check(unsolicited.renderer!.teleports.isEmpty && unsolicited.currentVehicle==42 && unsolicited.resets==0,"No-pending marker fabricated a respawn")

        let replaced=Game();replaced.network.begin();replaced.attack();replaced.network.begin("peer-two")
        check(!replaced.network.receive(100,processed:1,revision:1,respawned:1),"Foreign-peer acknowledgement accepted")
        check(replaced.renderer!.teleports.isEmpty && replaced.network.health==0,"Old peer displaced replacement world")
        replaced.attack();check(replaced.network.receive(100,processed:1,revision:1,respawned:1,connection:"peer-two"),"New peer acceptance rejected")
        check(replaced.renderer!.teleports.count==1,"New peer callback missing")

        let legacy=Game();legacy.attack()
        check(legacy.network.health==100 && legacy.renderer!.teleports.count==1 && legacy.resets==1 && legacy.currentVehicle==nil && legacy.network.requests.isEmpty,"Legacy synchronous callback behavior was lost")
        check(legacy.status.text=="RESPAWNED AT THE CITY CENTRE","Inline accepted feedback overwritten by request label")
        legacy.network.respawn();check(legacy.renderer!.teleports.count==1,"Live legacy player respawned twice")
        let legacyHeal=Game();legacyHeal.network.syncVitals(from:["health":100,"armour":0])
        check(legacyHeal.renderer!.teleports.isEmpty && legacyHeal.resets==0,"Legacy ordinary heal became respawn")

        // Exercise the actual newly linked original branch, with real effect
        // and fatal-token owners plus recorded Renderer/UI call boundaries.
        for wasDead in [false,true] {
            let original=Game();original.network.usesOriginalWorldProtocol=true
            original.network.originalRespawnWasDead=wasDead;original.originalExitToken=17
            _=original.originalEffects.light();original.originalEffects.whiff(random:{0.5})
            _=original.network.originalVitals.deferMovingCarSelfKill(nowMilliseconds:0,drivingCar:true,speed:2)
            original.finishRespawn()
            check(original.network.originalVitals.pendingFatal==nil && original.originalExitToken==nil,"Original respawn retained delayed vehicle fatal ownership")
            check(original.currentVehicle==nil && original.renderer!.originalLeaves==1 && original.radio.stops==1 && original.drivingChanges==[false] && original.gameHUD.vehicleUpdates==1,"Original respawn failed vehicle/UI ownership transfer")
            check(original.renderer!.teleports==[SIMD3(1154.13,-1771.15,16.6)] && original.status.text=="RESPAWNED" && original.resets==1,"Original spawn destination/reset diverged")
            check(original.renderer!.effectClears==(wasDead ? 1:0) && original.originalEffects.burning == !wasDead && original.originalEffects.coughing == !wasDead,"Original living teleport cleared effects or dead respawn retained them")
        }

        let offline=Game();offline.network.begin();offline.acceptsHeldInput=false;offline.attack()
        check(offline.network.requests.isEmpty && offline.renderer!.teleports.isEmpty,"Offline input requested a respawn")
        offline.acceptsHeldInput=true;offline.network.isReady=false;offline.attack()
        check(offline.network.requests.isEmpty && offline.network.health==0 && offline.renderer!.teleports.isEmpty,"Lost-ready race optimistically respawned")
        let blocked=Game();blocked.network.begin();blocked.weaponCycle.busy=true;blocked.attack()
        check(blocked.network.requests.isEmpty,"Busy action passed attack ownership guard")
        let foot=Game();foot.currentVehicle=nil;foot.network.begin();foot.attack();_=foot.network.receive(100,processed:1,revision:1,respawned:1)
        check(foot.renderer!.teleports.count==1 && foot.renderer!.exits==0 && foot.radio.stops==0 && foot.drivingChanges.isEmpty,"On-foot respawn manufactured vehicle exit")
        let deadCanopy=Game();deadCanopy.network.begin();deadCanopy.renderer!.isChuting=true;deadCanopy.attack()
        check(deadCanopy.network.requests.count==1 && deadCanopy.renderer!.deploys==0 && deadCanopy.renderer!.teleports.isEmpty,"Dead parachutist deployed instead of requesting acknowledged respawn")

        // API callbacks may synchronously change world ownership. The ACK
        // caller must recheck that boundary before moving a replacement world.
        for boundary in ["disconnect","replace"] {
            let h=Game();h.network.begin();h.attack();let normal=h.network.onVitals
            h.network.onVitals={hp,armour in normal?(hp,armour);if boundary=="disconnect"{h.network.disconnect()}else{h.network.begin("replacement")}}
            _=h.network.receive(100,processed:1,revision:1,respawned:1)
            check(h.renderer!.teleports.isEmpty && h.currentVehicle==42,"Accepted old ACK crossed a reentrant \(boundary) boundary")
        }
        // A sequenced respawn ACK can arrive after a newer authoritative
        // placement. Its presentation callback must not move/revoke that world.
        let strict=Game();strict.network.positionAcknowledgements=true;strict.network.begin();strict.attack()
        let newerPlacement=SIMD3<Float>(700,800,60);strict.renderer!.feet=newerPlacement
        check(strict.network.receive(100,processed:1,revision:1,respawned:1),"Strict accepted respawn ACK rejected")
        check(strict.renderer!.feet==newerPlacement && strict.renderer!.teleports.isEmpty,"Late strict respawn ACK overwrote a newer server placement")
        check(strict.currentVehicle==42 && strict.renderer!.exits==0 && strict.radio.stops==0 && strict.drivingChanges.isEmpty,"Late strict respawn ACK revoked a newer role")
        check(strict.resets==1 && !strict.heldFire && strict.status.text=="RESPAWNED","Strict accepted respawn presentation did not complete once")
        _=strict.network.receive(100,processed:1,revision:1,respawned:1)
        check(strict.resets==1 && strict.renderer!.teleports.isEmpty && strict.currentVehicle==42,"Duplicate strict respawn ACK repeated presentation or placement")
        print("PASS actual respawn dispatch: \(checks) checks; dead request, accepted once, rejected, heal, reconnect, legacy, callback ownership")
    }
}
'''

def main():
    with tempfile.TemporaryDirectory(prefix='run-',dir=OUT) as temporary:
        folder=Path(temporary);sources=[]
        for name in APP:
            p=folder/(name+'.swift');p.write_bytes(inputs[f'ios/App/{name}.swift']);sources.append(str(p))
        main=SWIFT.replace('HEALTH_PREDICTION',prediction).replace('NETWORK_METHODS',network_methods).replace('CALLBACKS',callback).replace('GAME_METHODS',game_methods)+'\n'+animation
        p=folder/'main.swift';p.write_text(main);sources.append(str(p));exe=folder/'verify'
        compile=subprocess.run(['xcrun','swiftc','-whole-module-optimization','-Onone','-num-threads','1','-parse-as-library','-module-cache-path',str(OUT/'module-cache'),*sources,'-o',str(exe)],capture_output=True,text=True,timeout=900)
        (OUT/'compile.log').write_text(compile.stdout+compile.stderr)
        if compile.returncode:print(compile.stdout+compile.stderr);compile.check_returncode()
        result=subprocess.run([str(exe)],capture_output=True,text=True)
        print(result.stdout,end='');print(result.stderr,end='')
        (OUT/'report.json').write_text(json.dumps({'status':'PASS' if result.returncode==0 else 'FAIL','output':result.stdout+result.stderr,
            'sourceHashes':{p:hashlib.sha256(data).hexdigest() for p,data in inputs.items()},
            'liveFilesStillMatchSnapshot':{p:(ROOT/p).read_bytes()==data for p,data in inputs.items()},
            'evidence':'Extracted actual GameVC attack/finishRespawn/onVitals/onRespawn plus health prediction and network ACK methods; controlled send/UI carriers',
            'limit':'No HTTP/WS listener, Renderer/UI/device or retail-runtime execution; separate actual health wire gate validates transport'},indent=2)+'\n')
        result.check_returncode()
if __name__=='__main__':main()
