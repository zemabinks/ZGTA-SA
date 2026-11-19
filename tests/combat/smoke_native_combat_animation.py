#!/usr/bin/env python3
"""Real CLP/native animator reload interruption, no renderer/device required."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,re,subprocess,tempfile

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/native-physics/tests/combat-animation';OUT.mkdir(parents=True,exist_ok=True)
NAMES=['NativeActorAnimation','NativeSkeletalActor','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativeRiderAnimation']
paths=[f'ios/App/{name}.swift' for name in NAMES]+['ios/App/NativeWorldRenderer.swift','tests/combat/smoke_native_combat_animation.py']
inputs={p:(ROOT/p).read_bytes() for p in paths}
renderer=inputs['ios/App/NativeWorldRenderer.swift'].decode()
methods=re.findall(r'animator\.(reload|beginReload)\(\)',renderer)
assert len(methods)==2 and len(set(methods))==1,'Both native production reload paths must share one ownership boundary'
SWIFT=r'''
import Foundation
let root=URL(fileURLWithPath:CommandLine.arguments[1]),game=root.appendingPathComponent("local-only/site/game")
let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:game.appendingPathComponent("native/models/animations.clips.bin")))!
let definitions=try NativeFootAnimationDefinitions(data:Data(contentsOf:game.appendingPathComponent("world/peds.json")))
let weapons=try NativeFootWeaponAnimation.load(data:Data(contentsOf:game.appendingPathComponent("native/foot-animation.json")))
var checks=0,frames=0,scenarios=0
func check(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
for id in [22,24,26,30,35,37] {for hz in [30,60,120] {for crouched in [false,true] {for mode in ["released","held","cancel","switch"] {
    scenarios+=1
    let animator=NativeFootAnimation(library:library,style:definitions.style(model:"bmori",library:library),random:{0.37})
    animator.arm(weapons[id])
    var input=NativeFootAnimation.Input();input.crouch=crouched;input.gun = .init(pitch:0.2,yaw:-0.1)
    let dt=1.0/Double(hz)
    for _ in 0..<hz { _=animator.update(delta:dt,input:input);frames+=1 }
    check(animator.fire(held:true),"Pending press was not accepted")
    animator.control(.init(fire:true,aim:true,held:true,ready:true))
    let pre=animator.update(delta:dt,input:input);frames+=1
    check(pre.shots.isEmpty,"Fixture already consumed its pre-reload press")
    let length=animator.PRODUCTION_RELOAD()
    check(weapons[id]!.reloads ? length>0:length==0,"Reload clip capability changed")
    let readyAt=max(2.0,length+0.15),until=max(4.0,readyAt+1)
    var elapsed=0.0,interrupted=false,accepted=0
    while elapsed<until {
        elapsed+=dt
        if elapsed>=0.2 && !interrupted {
            if mode=="cancel"{animator.cancelReload()}
            if mode=="switch"{animator.arm(weapons[id==22 ? 28:22])}
            interrupted=true
        }
        let ready=elapsed>=readyAt || mode=="cancel" && interrupted || mode=="switch" && interrupted
        animator.control(.init(fire:mode=="held",aim:true,held:mode=="held",ready:ready))
        let frame=animator.update(delta:dt,input:input);frames+=1
        if ready {accepted+=frame.shots.count}
    }
    if mode=="held" {check(accepted>0,"A genuinely held trigger did not resume after reload")}
    else {check(accepted==0,"Unconsumed trigger survived reload: weapon\(id) \(hz)Hz crouched\(crouched) \(mode), events\(accepted)")}
    if mode != "held" {
        check(animator.fire(held:true),"Explicit fresh press did not rearm after interruption")
        var fresh=0
        for _ in 0..<(hz*2) {
            animator.control(.init(aim:true,ready:true));fresh+=animator.update(delta:dt,input:input).shots.count;frames+=1
        }
        check(fresh>0,"Reload fix suppressed an explicit later shot")
    }
} } } }
print("PASS real-CLP combat animation: \(checks) checks, \(scenarios) scenarios, \(frames) native frames at30/60/120Hz; release/hold/cancel/switch/fresh press")
'''

def main():
    required=['native/models/animations.clips.bin','native/foot-animation.json','world/peds.json']
    for name in required:assert (ROOT/'local-only/site/game'/name).exists(),'Owner-local native data required: '+name
    with tempfile.TemporaryDirectory(prefix='native-combat-',dir=OUT) as temporary:
        folder=Path(temporary);sources=[]
        for name in NAMES:
            p=folder/(name+'.swift');p.write_bytes(inputs[f'ios/App/{name}.swift']);sources.append(str(p))
        p=folder/'main.swift';p.write_text(SWIFT.replace('PRODUCTION_RELOAD',methods[0]));sources.append(str(p))
        exe=folder/'verify'
        compiled=subprocess.run(['xcrun','swiftc','-module-cache-path',str(OUT/'module-cache'),*sources,'-o',str(exe)],capture_output=True,text=True)
        (OUT/'compile.log').write_text(compiled.stdout+compiled.stderr)
        if compiled.returncode:print(compiled.stdout+compiled.stderr);compiled.check_returncode()
        result=subprocess.run([str(exe),str(ROOT)],capture_output=True,text=True)
        print(result.stdout,end='');print(result.stderr,end='')
        (OUT/'report.json').write_text(json.dumps({'status':'PASS' if result.returncode==0 else 'FAIL','output':result.stdout+result.stderr,
            'productionReloadMethod':methods[0],'sourceHashes':{p:hashlib.sha256(data).hexdigest() for p,data in inputs.items()},
            'liveFilesStillMatchSnapshot':{p:(ROOT/p).read_bytes()==data for p,data in inputs.items()},
            'privateDataHashes':{name:hashlib.sha256((ROOT/'local-only/site/game'/name).read_bytes()).hexdigest() for name in required},
            'limits':['Native interruption correctness using real source CLP; no retail runtime comparison or GPU/device claim',
                      'Readiness held behind a synthetic2s barrier, not a replacement reload-duration constant']},indent=2)+'\n')
        result.check_returncode()
if __name__=='__main__':main()
