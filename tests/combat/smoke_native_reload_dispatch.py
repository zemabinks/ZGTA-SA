#!/usr/bin/env python3
"""Extract the production reload dispatch; exercise real inline HTTP rejection."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,subprocess,tempfile

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/native-physics/tests/reload-dispatch';OUT.mkdir(parents=True,exist_ok=True)
APP=['ServerAddress','NativeInventoryPrediction','NativeOriginalWorldArsenal','NativeWeaponState','NativeWeaponShotDelivery','NativeGameplayClient']
FILES=[f'ios/App/{name}.swift' for name in APP]+['ios/App/NativeGameViewController.swift','ios/App/NativeActorAnimation.swift','tests/combat/smoke_native_reload_dispatch.py']
inputs={p:(ROOT/p).read_bytes() for p in FILES}
def extract(source,marker):
    start=source.index(marker);at=source.index('{',start);depth=1;end=at+1
    while depth:
        depth+=(source[end]=='{')-(source[end]=='}');end+=1
    return source[start:end].replace('@objc ','').replace('private ','')
reload_method=extract(inputs['ios/App/NativeGameViewController.swift'].decode(),'@objc private func reload()')
animation=extract(inputs['ios/App/NativeActorAnimation.swift'].decode(),'struct NativeWeaponAnimation {')
SWIFT=r'''
import Foundation
var checks=0
func check(_ value:@autoclosure()->Bool,_ message:String){checks+=1;precondition(value(),message)}
final class Status {var text=""}
final class Network {
    var inventoryConnection:String?="peer-one",detonations=0,usesClientOwnedWeapons=false
    func detonateSatchels(){detonations+=1}
}
final class Renderer {
    var isClimbing=false,swimming=false,isChuting=false,crouching=false
    var starts=0,cancels=0
    func fireWeapon(clip:String,duration:Double){starts+=1}
    func cancelReloadAnimation(){cancels+=1}
    func cancelWeaponInput(){}
}
final class Audio {var reloads=0,cancels=0;func reload(weapon:Int){reloads+=1};func cancelReload(){cancels+=1}}
final class DispatchGameplay {
    let actualOffline=NativeGameplayClient(server:ServerAddress("http://127.0.0.1:1")!)
    var rejectInline=false,calls=0,pending:[(Bool?)->Void]=[],successReports:[Bool]=[]
    func perform(_ action:String,reportSuccess:Bool=true,completion:@escaping(Bool?)->Void){
        calls+=1;successReports.append(reportSuccess)
        if rejectInline {actualOffline.perform(action,reportSuccess:reportSuccess,completion:completion)}
        else {pending.append(completion)}
    }
    func complete(_ result:Bool?){let callback=pending.removeFirst();callback(result)}
}
final class Harness {
    var acceptsHeldInput=true,currentVehicle:Int?=nil
    var renderer:Renderer?=Renderer()
    let network=Network(),gameplay=DispatchGameplay(),audio=Audio(),status=Status()
    let weapons=NativeWeaponState(catalog:[
        .init(id:22,name:"Fixture",model:"",range:40,capacity:17,interval:0.3,animation:"fixture",fireKind:"INSTANT_HIT"),
        .init(id:39,name:"Satchel",model:"",range:40,capacity:1,interval:0.3,animation:"fixture",fireKind:"PROJECTILE")])
    var updates=0
    var usingPistol:Bool{weapons.current.isGun}
    var magazine:Int{weapons.rounds}
    var reserve:Int{weapons.reserve}
    func updateWeaponHUD(){updates+=1}
    func baseline(selected:Int=22,clip:Int=4,rest:Int=30,nonce:String="peer-one",revision:Int=0,reload:Bool=false){
        network.inventoryConnection=nonce;weapons.setConnection(nonce)
        let value:[String:Any]=["revision":revision,"selected":selected,
            "weapons":selected==0 ? []:[["id":selected,"clip":clip,"rest":rest]],
            "reload":reload ? ["weapon":selected,"remainingMs":1800,"until":1700000001800] : NSNull(),
            "ack":["connection":nonce,"processedShot":0]]
        check(weapons.apply(value),"Fixture authoritative baseline")
    }
    PRODUCTION_RELOAD
}
@main enum Verify {
    static func main(){
        let rejected=Harness();rejected.baseline();rejected.gameplay.rejectInline=true;rejected.reload()
        check(rejected.gameplay.calls==1,"Inline gate was exercised")
        check(rejected.renderer!.starts==0 && rejected.audio.reloads==0 && rejected.updates==0 && rejected.status.text.isEmpty,
              "A real synchronous HTTP rejection restarted canceled reload feedback")
        check(!rejected.weapons.reloading && rejected.weapons.canFire,"Rejected transaction retained reload ownership")

        let deferred=Harness();deferred.baseline();deferred.reload();deferred.reload()
        check(deferred.gameplay.calls==1 && deferred.renderer!.starts==1 && deferred.audio.reloads==1,"Pending reload must present and submit only once")
        check(deferred.gameplay.successReports==[false],"Owned reload HUD emitted an unowned persistent success toast")
        check(deferred.weapons.reloading && !deferred.weapons.canFire,"Pending reload did not block further rounds")
        deferred.gameplay.complete(false)
        check(!deferred.weapons.reloading && deferred.weapons.canFire && deferred.renderer!.cancels==1,"Delayed definitive rejection did not roll back reload")
        check(deferred.audio.cancels==1,"Definitive rejection retained queued reload audio")
        deferred.reload();check(deferred.gameplay.calls==2 && deferred.renderer!.starts==2,"Fresh reload after rejection was suppressed")
        deferred.baseline(revision:1,reload:true);deferred.gameplay.complete(true)
        check(deferred.weapons.reloading && !deferred.weapons.canFire && deferred.renderer!.cancels==1,"Accepted authoritative reload canceled prematurely")
        check(deferred.audio.cancels==1,"Accepted authoritative reload canceled its audio owner")

        let unknown=Harness();unknown.baseline();var resyncs=0;unknown.weapons.onNeedsResync={resyncs+=1}
        unknown.reload();unknown.gameplay.complete(nil)
        check(unknown.weapons.reloading && !unknown.weapons.canFire && resyncs==1 && unknown.renderer!.cancels==0,"Unknown transport result optimistically unlocked ammunition")

        let stale=Harness();stale.baseline();stale.reload();stale.baseline(nonce:"peer-two");stale.reload()
        stale.gameplay.complete(false)
        check(stale.weapons.reloading && stale.renderer!.cancels==0,"Old-peer rejection canceled a replacement reload")
        check(stale.audio.cancels==0,"Old-peer rejection canceled replacement reload audio")
        stale.gameplay.complete(false)
        check(!stale.weapons.reloading && stale.renderer!.cancels==1,"Current-peer rejection was discarded")

        for context in ["offline","vehicle","climb","swim","chute","full","empty","melee"] {
            let h=Harness();h.baseline(selected:context=="melee" ? 0:22,clip:context=="full" ? 17:4,rest:context=="empty" ? 0:30)
            h.acceptsHeldInput=context != "offline";h.currentVehicle=context=="vehicle" ? 1:nil
            h.renderer!.isClimbing=context=="climb";h.renderer!.swimming=context=="swim";h.renderer!.isChuting=context=="chute"
            h.reload();check(h.gameplay.calls==0 && h.renderer!.starts==0 && h.audio.reloads==0,"Reload escaped \(context) guard")
        }
        let satchel=Harness();satchel.baseline(selected:39,clip:1,rest:0);satchel.reload()
        check(satchel.network.detonations==1 && satchel.gameplay.calls==0 && satchel.renderer!.starts==0,"Satchel detonation became a reload")
        print("PASS actual reload dispatch: \(checks) checks; real inline HTTP rejection, delayed result, reconnect, guard matrix")
    }
}
'''

def main():
    with tempfile.TemporaryDirectory(prefix='run-',dir=OUT) as temporary:
        folder=Path(temporary);sources=[]
        for name in APP:
            p=folder/(name+'.swift');p.write_bytes(inputs[f'ios/App/{name}.swift']);sources.append(str(p))
        p=folder/'main.swift';p.write_text(SWIFT.replace('PRODUCTION_RELOAD',reload_method)+'\n'+animation);sources.append(str(p))
        exe=folder/'verify'
        compile=subprocess.run(['xcrun','swiftc','-whole-module-optimization','-Onone','-num-threads','1','-parse-as-library','-module-cache-path',str(OUT/'module-cache'),*sources,'-o',str(exe)],capture_output=True,text=True,timeout=900)
        (OUT/'compile.log').write_text(compile.stdout+compile.stderr)
        if compile.returncode:print(compile.stdout+compile.stderr);compile.check_returncode()
        result=subprocess.run([str(exe)],capture_output=True,text=True)
        print(result.stdout,end='');print(result.stderr,end='')
        (OUT/'report.json').write_text(json.dumps({'status':'PASS' if result.returncode==0 else 'FAIL','output':result.stdout+result.stderr,
            'sourceHashes':{p:hashlib.sha256(data).hexdigest() for p,data in inputs.items()},
            'liveFilesStillMatchSnapshot':{p:(ROOT/p).read_bytes()==data for p,data in inputs.items()},
            'evidence':'Actual extracted GameVC reload + actual GameplayClient offline perform gate + actual inventory state; delayed callbacks are controlled carriers',
            'limit':'No UI/device/server service and no retail timing claim'},indent=2)+'\n')
        result.check_returncode()
if __name__=='__main__':main()
