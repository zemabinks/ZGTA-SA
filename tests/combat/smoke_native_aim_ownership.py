#!/usr/bin/env python3
"""Asset-free literal task/GVC/camera aim-ownership regression; no device/UI."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import argparse,hashlib,json,pathlib,subprocess,tempfile
ROOT=pathlib.Path(__file__).resolve().parents[2]

def block(source,marker):
    start=source.index(marker);brace=source.index('{',start);depth=1;end=brace+1
    while depth:
        depth+=(source[end]=='{')-(source[end]=='}');end+=1
    return source[start:end]

def main():
    p=argparse.ArgumentParser();p.add_argument('--prepare-only',action='store_true');p.add_argument('--baseline',type=pathlib.Path)
    p.add_argument('--expect-historical-latch',action='store_true')
    p.add_argument('--expect-historical-flight-aim',action='store_true');a=p.parse_args()
    historical=a.expect_historical_latch or a.expect_historical_flight_aim
    root=(a.baseline or ROOT).resolve();out=ROOT/'local-only/research/aim-ownership-118';out.mkdir(parents=True,exist_ok=True)
    names=['NativeGameViewController','NativeWorldRenderer','ServerAddress','NativeGameInput','NativeGameBindings',
           'NativeGameCamera','NativeSwimController','NativePersonalFlightController','NativeClimbController']
    inputs={n:(root/'ios/App'/f'{n}.swift').read_text() for n in names};vc=inputs[names[0]];r=inputs[names[1]]
    old='var canMaintainFootAim:' not in r
    def method(source,marker):return block(source,marker).replace('private ','').replace('@objc ','')
    renderer_methods=method(r,'var supportsFootWeaponAim:')
    if not old:renderer_methods+='\n'+method(r,'var canMaintainFootAim:')+'\n'+method(r,'private func cancelFootAimForTask()')
    renderer_methods+='\n'+method(r,'private func beginClimb(')
    gvc_methods='\n'.join(method(vc,m) for m in ['private var bindingContext:','private func setAiming(','@objc private func toggleAim()'])
    if 'private func reconcileAimOwnership()' in vc:gvc_methods+='\n'+method(vc,'private func reconcileAimOwnership()')
    swim=block(r,'if !swimController.on && swimController.enters(depth) {')
    chute=block(r,'if !personalFlight.on,hasParachute,!state.grounded,personalFlight.dives(')
    takeoff=block(r,'if personalFlight.lifts,footAnimator?.busy != true')
    flight_aim=block(r,'if personalFlight.flying && footWeaponDefinitions[equippedWeapon]?.arm != true') if not old else ''
    start=r.index('gameCameraFrame=gameCamera.followFoot(');end=start+len('gameCameraFrame=gameCamera.followFoot(');depth=1
    while depth:depth+=(r[end]=='(')-(r[end]==')');end+=1
    call=r[start:end];line=r.rfind('\n',0,start)+1;prefix=r[r.rfind('\n',0,line-1)+1:line]
    if 'let cameraAiming=' in prefix:call=prefix+call
    binding=next((line.strip() for line in vc.splitlines() if line.strip().startswith('renderer?.onFootAimCancelled =')),'')
    poll_start=vc.index('        let heldAim=acceptsInput')
    previous=vc[vc.rfind('\n',0,poll_start-1)+1:poll_start]
    if 'reconcileAimOwnership()' in previous:poll_start=vc.rfind('        reconcileAimOwnership()',0,poll_start)
    poll_end=vc.index('\n',vc.index('        lastGamepadAim=heldAim',poll_start))
    poll=vc[poll_start:poll_end]
    move_at=vc.index('            renderer?.move(forward: forward, sideways: sideways,')
    move_start=vc.rfind('for step in timing.steps {',0,move_at);moves=block(vc,vc[move_start:vc.index('{',move_start)+1])
    skeleton=(ROOT/'tests/combat/smoke_native_aim_ownership.swift').read_text()
    for key,value in {'RENDERER_METHODS':renderer_methods,'GVC_METHODS':gvc_methods,'ACTUAL_SWIM_ENTRY':swim,'ACTUAL_CHUTE_ENTRY':chute,
                      'ACTUAL_CAMERA_CALL':call,'ACTUAL_GVC_BINDING':binding,'ACTUAL_POLL':poll,'ACTUAL_MOVES':moves,
                      'ACTUAL_TAKEOFF':takeoff,'ACTUAL_FLIGHT_AIM_GATE':flight_aim,
                      'HISTORICAL_MODE':str(a.expect_historical_latch).lower(),
                      'HISTORICAL_FLIGHT_MODE':str(a.expect_historical_flight_aim).lower()}.items():
        skeleton=skeleton.replace('// '+key,value)
    if historical:
        # Keep the real historical task/input/camera code. Current-only tests
        # reference the new predicate, so exclude those tests, not source APIs.
        skeleton=skeleton[:skeleton.index('for hz in [15,30,60,120]')]
    work=pathlib.Path(tempfile.mkdtemp(prefix='gate-',dir=out));(work/'main.swift').write_text(skeleton)
    sources=[]
    for n in names[2:]:
        source=inputs[n]
        if n=='NativeClimbController':
            # Aim admission only constructs this owner. Preserve its literal
            # data/initializer; stepping and probes have separate real gates.
            source=source[:source.index('    private func approach(')]+'\n}\n'
        f=work/f'{n}.swift';f.write_text(source);sources.append(str(f))
    exe=work/'verify';command=['nice','-n','15','swiftc','-O','-whole-module-optimization','-num-threads','1','-swift-version','5',
                             '-module-cache-path',str(work/'modules'),*sources,str(work/'main.swift'),'-o',str(exe)]
    manifest={'prepared':True,'compiled':False,'executed':False,'historical':historical,'historicalFlight':a.expect_historical_flight_aim,'sourceRoot':str(root),
              'sourceHashes':{n:hashlib.sha256(s.encode()).hexdigest() for n,s in inputs.items()},
              'testHashes':{n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in ['tests/combat/smoke_native_aim_ownership.py','tests/combat/smoke_native_aim_ownership.swift']},
              'carrierSHA256':hashlib.sha256(skeleton.encode()).hexdigest(),'command':command,
              'scope':'Literal accepted swim/chute/climb blocks, GVC binding/toggle/setter/poll/move loop, Renderer predicates/camera call; actual swim/flight/camera, literal climb data/initializer only, authored UI/geometry/CLP-duration boundaries.',
              'climbBoundary':'This aim harness does not call climb step/probe methods; the owner-local climb/movement gates cover those separately.'}
    mp=work/'manifest.json';mp.write_text(json.dumps(manifest,indent=2)+'\n');print(mp,flush=True)
    if a.prepare_only:return
    compilation=subprocess.run(command,capture_output=True,text=True,timeout=180)
    (work/'compile.log').write_text(compilation.stdout+compilation.stderr)
    if compilation.returncode:
        manifest.update(status='COMPILE_FAILURE',output=compilation.stdout+compilation.stderr)
        mp.write_text(json.dumps(manifest,indent=2)+'\n')
        print(manifest['output']);compilation.check_returncode()
    result=subprocess.run([str(exe)],capture_output=True,text=True,timeout=30)
    expected=2 if historical else 0
    marker='HISTORICAL_FLIGHT_LATCH' if a.expect_historical_flight_aim else 'HISTORICAL_LATCH'
    accepted=result.returncode==expected and (not historical or marker in result.stdout)
    manifest.update(compiled=True,executed=True,status='PASS' if accepted else 'FAIL',exitCode=result.returncode,output=result.stdout+result.stderr)
    name='historical-flight-result.json' if a.expect_historical_flight_aim else 'historical-result.json' if historical else 'current-result.json'
    mp.write_text(json.dumps(manifest,indent=2)+'\n');(out/name).write_text(json.dumps(manifest,indent=2)+'\n')
    print(result.stdout,end='');print(result.stderr,end='')
    if not accepted:raise SystemExit('Aim ownership regression failed: '+str(result.returncode))
if __name__=='__main__':main()
