#!/usr/bin/env python3
"""Replay actual archived landing damage + current native foot/motor integration."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib
import platform
import subprocess
import tempfile
from tests.movement.smoke_native_climb_runtime import function

ROOT=Path(__file__).resolve().parents[2]
JS=r'''
const fs=require('node:fs'),crypto=require('node:crypto');
const load=require(process.cwd()+'/smoke_vehicle_dynamics').archivedModules();
const source=load.factories[19737].toString();
const start=source.indexOf('(er>18.75'),suffix=',{weapon:54})',end=source.indexOf(suffix,start)+suffix.length;
if(start<0 || end<=start)throw Error('Actual archived landing expression is unavailable');
const expression=source.slice(start,end),evaluate=new Function('er','t','ei',expression);
const hurtStart=source.indexOf('hurt(e){',1700000),hurtEnd=source.indexOf('},rammed(e)',hurtStart);
if(hurtStart<0 || hurtEnd<=hurtStart)throw Error('Actual archived hurt method is unavailable');
const hurt=source.slice(hurtStart,hurtEnd+1);
// Non-fall effects are outside this replay. The original fall path either
// returns after subtracting health or calls the controlled death collector.
const apply=new Function('damage','initial','armour',`let e4=false,e1=initial>0?-1:0,e0=armour,eZ=initial,eb=false,T=null;
const r7=new Map(),nN={F4:()=>false},ay=()=> 'koFront',lr=()=>{eZ=0;e1=0},obj={${hurt}};
obj.hurt(damage,{weapon:54});return {health:Math.round(eZ),armour:e0,dead:e1>=0};`);
const values=[0,12.5,18.75-1e-9,18.75,18.75+1e-9,30-1e-9,30,30+1e-9,33-1e-9,33,33+1e-9];
for(let value=0;value<=60;value+=.5)values.push(value);
const rows=[];
for(const fastest of values)for(const horizontal of values){
 let damage=0,weapon=null,count=0;
 evaluate.call({hurt(amount,meta){damage=amount;weapon=meta.weapon;count++}},fastest,horizontal,false);
 rows.push({fastest,horizontal,damage,weapon,count,health:[0,1,18,25,100].map(value=>apply(damage,value,25))});
}
fs.writeFileSync(process.argv[2],JSON.stringify({factorySHA256:crypto.createHash('sha256').update(source).digest('hex'),start,end,rows}));
console.log('Recorded '+rows.length+' exact archived landing-expression cases');
'''


def main():
    output=ROOT/'local-only/research/fall-damage'
    output.mkdir(parents=True,exist_ok=True)
    (output/'reference.js').write_text(JS)
    subprocess.run(['node',str(output/'reference.js'),str(output/'reference.json')],cwd=ROOT,check=True)
    renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
    methods=['private func combatEligibility(','var canEmitFootWeaponShot:','var canEmitFootCombatMarker:','var hasNativeFootWeaponTiming:','private func footMotion(','private func beginClimb(','private func climbingMotion(',
             'private func emitFootWeaponEvents(','func cancelWeaponInput(','func cancelGameplayInput(','func letGoOfLedge(',
             'private var activeMeleeDefinition:','var hasNativeFootMeleeTiming:','var canNativeFootMeleeGuard:',
             'private func meleeControls(','private func advanceMelee(','private func cancelFootAimForTask(']
    extracted='\n\n'.join(function(renderer,marker) for marker in methods)
    shot=renderer.index('    private var weaponEventFeet:')
    extracted=renderer[shot:renderer.index('    func weaponMuzzle(',shot)]+'\n'+extracted
    skeletal=(ROOT/'ios/App/NativeSkeletalActor.swift').read_text()
    source=skeletal[:skeletal.index('struct NativeSkinVertex')].replace('import Metal','')
    source+='\nfinal class NativeSkeletalActor {\n'+skeletal[skeletal.index('    struct OriginalAim {'):skeletal.index('    struct Pose {')]+'}\n'
    for name in ['NativeCombatEligibility','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation',
                 'NativePersonalFlightController','NativeFootLocomotion','NativeHeadingContinuity',
                 'NativeSprintController','NativeMelee','NativeMeleeInput','NativeFallDamage']:
        source+='\n'+(ROOT/'ios/App'/f'{name}.swift').read_text()
    harness=(ROOT/'tests/movement/smoke_native_climb_runtime.swift').read_text().split('@main enum ClimbRuntimeSmoke')[0]
    source+='\n'+harness.replace('// ACTUAL_RENDERER_METHODS',extracted)
    source+='\n'+(ROOT/'tests/movement/smoke_native_fall_damage.swift').read_text()
    (output/'runtime-source.swift').write_text(source)
    (output/'renderer-methods.sha256').write_text(hashlib.sha256(extracted.encode()).hexdigest()+'\n')
    with tempfile.TemporaryDirectory(prefix='fall-',dir=output) as directory:
        work=Path(directory);(work/'main.swift').write_text(source)
        names=['SwiftRapierWorld','NativeCharacterMotor','NativeRapierCharacterQueries','NativeCharacterController',
               'NativeClimbController','NativeRapierClimbQueries']
        subprocess.run(['swiftc','-parse-as-library','-whole-module-optimization','-Onone','-module-cache-path',
                        '/private/tmp/zgtasa-core-swift-modules','-I',str(ROOT/'native-physics/include'),
                        *[str(ROOT/'ios/App'/f'{name}.swift') for name in names],str(work/'main.swift'),
                        '-L',str(ROOT/f'local-only/native-physics/macos-{platform.machine()}'),'-lzgtasa_native_physics',
                        '-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')],check=True)
        subprocess.run([str(work/'verify'),str(ROOT)],check=True)


if __name__=='__main__':main()
