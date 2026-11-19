#!/usr/bin/env python3
"""Literal GVC controller polling/dispatch owner regression; no hardware/UI.

--prepare-only freezes the carrier without invoking Swift. Historical mode uses
an unchanged older checkout and expects the diagnosed offline Menu loss.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import argparse,hashlib,json,pathlib,shutil,subprocess,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]

def method(source,marker):
    start=source.index(marker);brace=source.index('{',start);level=1;end=brace+1
    while level:
        level+=(source[end]=='{')-(source[end]=='}');end+=1
    return source[start:end].replace('private ','').replace('@objc ','')

def main():
    p=argparse.ArgumentParser();p.add_argument('--prepare-only',action='store_true');p.add_argument('--baseline',type=pathlib.Path);p.add_argument('--expect-historical-drop',action='store_true');a=p.parse_args()
    root=(a.baseline or ROOT).resolve();out=ROOT/'local-only/research/input-audit-117';out.mkdir(parents=True,exist_ok=True)
    names=['ios/App/NativeGameViewController.swift','ios/App/NativeGameInput.swift','ios/App/NativeGameBindings.swift','ios/App/NativeVehicleHornController.swift','ios/App/NativeGameAudio.swift']
    inputs={n:(root/n).read_text() for n in names};vc=inputs[names[0]]
    availability=vc.index('        var acceptsInput = active && presentedViewController == nil && network.isReady')
    availability_end=vc.index('\n',vc.index('        inputWasAvailable = acceptsInput',availability))
    select='        let controller = GCController.controllers().compactMap(\\.extendedGamepad).first'
    owner_new='        pollControllerMenu(controller)' in vc
    top=vc[vc.rfind(select,0,availability):availability_end] if owner_new else vc[availability:availability_end]
    local_start=vc.index('        var forward = Float(-stick.value.y)',availability)
    local_end=vc.index('\n',vc.index('        var gamepadAttacking = keyboard.attack',local_start))
    locals_=vc[local_start:local_end]
    gate_start=vc.index('        var controllerAllowed = false',local_end)
    gate_end=vc.index('\n        acceptsInput = acceptsInput && presentedViewController == nil',gate_start)
    gate=vc[gate_start:gate_end]
    if not owner_new:gate=select+'\n'+gate
    # Literal same-frame modal suppression and combat/horn output owners.
    block_start=vc.index('        // Opening a panel from a controller',gate_end)
    block_end=vc.index('        // Pad jump edges',block_start)
    blocked=vc[block_start:block_end]
    horn_start=vc.index('        let hornState=audio.vehicleHornInput',block_end)
    horn_end=vc.index('\n',vc.index('        lastAttackButton = gamepadAttacking',horn_start))
    fight_start=vc.index('        let canFight = acceptsInput',horn_end)
    fight_end=vc.index('\n',vc.index('        renderer?.weaponTriggerHeld = canFight',fight_start))
    running=next(x for x in vc.splitlines() if x.strip().startswith('let running = acceptsInput'))
    markers=['private var canNavigateMenus:','private var acceptsHeldInput:','private func resetControls()',
             'private func performBinding(','@objc private func jump()',
             'override func present(_ viewControllerToPresent:']
    if owner_new:markers+=['private func resetControllerMenuInput()','private func pollControllerMenu(']
    methods='\n'.join(method(vc,m) for m in markers)
    audio=inputs[names[4]]
    audio_methods=method(audio,'    func cancelHornInput()')+'\n'+method(audio,'    func vehicleHornInput(')
    skeleton=(ROOT/'tests/ui/smoke_native_controller_navigation.swift').read_text()
    generated=skeleton.replace('// ACTUAL_AUDIO_METHODS',audio_methods).replace('// ACTUAL_OWNER_METHODS',methods)
    body='''
    func poll(milliseconds:Double=0) -> PollFrame {
        let active=applicationActive && view.window != nil
        let delta:Float=1.0/60.0,link=Link(timestamp:milliseconds/1000)
'''+top+'\n'+locals_+'\n'+gate+'\n'+blocked+'\n'+vc[horn_start:horn_end]+'\n'+running+'\n'+vc[fight_start:fight_end]+'''
        return PollFrame(allowed:controllerAllowed,forward:forward,sideways:sideways,running:running,
                         firing:renderer?.weaponTriggerHeld == true,horn:renderer?.vehicleHorn == true,siren:renderer?.vehicleSiren == true)
    }
'''
    generated=generated.replace('// ACTUAL_POLL_OWNER',body)
    generated=generated.replace('// EXPECTED_HISTORICAL',f'let expectedHistorical={str(a.expect_historical_drop).lower()}')
    work=pathlib.Path(tempfile.mkdtemp(prefix='controller-owner-',dir=out));(work/'main.swift').write_text(generated)
    compile_inputs=[]
    for name in names[1:4]:
        target=work/pathlib.Path(name).name;target.write_text(inputs[name]);compile_inputs.append(str(target))
    exe=work/'verify';command=['nice','-n','10','swiftc','-O','-whole-module-optimization','-num-threads','1','-swift-version','5','-module-cache-path',str(work/'modules'),*compile_inputs,str(work/'main.swift'),'-o',str(exe)]
    manifest={'prepared':True,'compiled':False,'executed':False,'sourceRoot':str(root),'historical':a.expect_historical_drop,
              'sourceHashes':{n:hashlib.sha256(v.encode()).hexdigest() for n,v in inputs.items()},
              'testHashes':{n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in ['tests/ui/smoke_native_controller_navigation.py','tests/ui/smoke_native_controller_navigation.swift']},
              'carrier':str(work/'main.swift'),'carrierSHA256':hashlib.sha256(generated.encode()).hexdigest(),'command':command,
              'scope':'Actual extracted poll/gate/dispatch/reset/present/audio owner source with authored UIKit/GameController spies; no real UIKit/controller/device'}
    mp=work/'manifest.json';mp.write_text(json.dumps(manifest,indent=2)+'\n')
    print(mp,flush=True)
    if a.prepare_only:return
    subprocess.run(command,check=True,timeout=180)
    result=subprocess.run([str(exe)],check=True,capture_output=True,text=True,timeout=30)
    manifest.update(compiled=True,executed=True,output=result.stdout);mp.write_text(json.dumps(manifest,indent=2)+'\n')
    (out/('historical-result.json' if a.expect_historical_drop else 'current-result.json')).write_text(json.dumps(manifest,indent=2)+'\n')
    print(result.stdout,end='')
if __name__=='__main__':main()
