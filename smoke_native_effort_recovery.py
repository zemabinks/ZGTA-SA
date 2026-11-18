#!/usr/bin/env python3
"""Actual Renderer effort owners, real CLP, and selected archived expressions.

No original scripts, animation data or generated observations are published.
A prepared native library and owner-provided local archive are required.
"""
from pathlib import Path
import argparse,hashlib,json,platform,subprocess,tempfile
from smoke_native_climb_runtime import function

ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/native-physics/tests/effort-recovery'
NAMES=['NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation',
       'NativePersonalFlightController','NativeFootLocomotion','NativeHeadingContinuity',
       'NativeSprintController','NativeSwimController','NativeMelee','NativeMeleeInput','NativeFallDamage','NativeCombatEligibility']
FOOT=['private func footMotion(','private func beginClimb(','private func climbingMotion(',
      'private func emitFootWeaponEvents(','func cancelWeaponInput(','func cancelGameplayInput(','func letGoOfLedge(',
      'private var activeMeleeDefinition:','var hasNativeFootMeleeTiming:','var canNativeFootMeleeGuard:',
      'private func meleeControls(','private func advanceMelee(','private func cancelFootAimForTask(']
WATER=['private func swimmingMotion(','private func personalFlightMotion(',
       'private var personalFlightAnimationInput:','func cancelGameplayInput(','var swimmingBreath:','private func cancelFootAimForTask(']
JS=r'''
const fs=require('node:fs'),crypto=require('node:crypto'),path=require('node:path');
const root=process.argv[2],output=process.argv[3],baseline=process.argv[4]==='baseline';
const load=require(path.join(root,'smoke_vehicle_dynamics')).archivedModules(),src=String(load.factories[19737]);
const matches={
 prepare:/td\.under&&tr<=0&&\(tr=\.1\)/.exec(src),
 recovery:/ta=(e=>\{tr=Math\.min\(150,tr\+e\*\(V>1\?\.15:\.5\)\)\})/.exec(src),
 display:/td\.under\|\|td\.breath<1\?Math\.ceil\(100\*td\.breath\):null/.exec(src),
 budget:/to=(\{get left\(\)\{return tr- -90\},take:e=>[\s\S]*?\})\},ti=/.exec(src),
 dead:/e1>=0\)\{e1\+=l,V=0,Y=eR=eL=!1,tR=!1;return\}/.exec(src)
};
for(const [key,value]of Object.entries(matches))if(!value)throw Error('Actual archived effort boundary unavailable: '+key);
const factorySHA256=crypto.createHash('sha256').update(src).digest('hex');
const evidence={factory:19737,factorySHA256,selected:Object.fromEntries(Object.entries(matches).map(([key,m])=>[key,{offset:m.index,bytes:m[0].length,sha256:crypto.createHash('sha256').update(m[0]).digest('hex')}]))};
fs.writeFileSync(path.join(output,'reference-boundaries.json'),JSON.stringify(evidence,null,2)+'\n');
function budget(initial){
 const setup=new Function('initial',`let tr=initial,e3=false,e5=false,V=0;const value=${matches.budget[1]+'}'};const recovery=${matches.recovery[1]};return {value,get current(){return tr},prepare(under){const td={under};${matches.prepare[0]}},rest(ticks,ratio){V=ratio;recovery(ticks)},reset(){tr=150}}`);
 return setup(initial);
}
const display=new Function('td','return '+matches.display[0]);
const traces=JSON.parse(fs.readFileSync(path.join(output,'native.json'))),failures=[],byCase={},tolerance=1e-8;
let checks=0;
function check(actual,expected,label){checks++;const okay=typeof actual==='number'&&typeof expected==='number'?Number.isFinite(actual)&&Math.abs(actual-expected)<tolerance:actual===expected;if(!okay){failures.push({label,actual,expected});byCase[label.split('/')[0]]=(byCase[label.split('/')[0]]||0)+1;}}
for(const row of traces.scalars){const b=budget(row.initial);if(row.kind==='under')b.prepare(row.under);else b.rest(row.ticks,row.ratio);check(row.actual,b.current,'scalar/'+row.kind);}
for(const scenario of traces.water){
 const b=budget(scenario.initial),sprint=load(34719).jZ(),swim=load(19863).dp(),T=load(85339),v=a=>new T.Pq0(...a);
 swim.enter(v([0,0,0]),0,scenario.depth);
 for(const [i,row]of scenario.frames.entries()){
  if(row.reset){b.reset();sprint.reset();swim.revive();}
  const wasOn=swim.on;let pace=0;
  if(wasOn&&row.health>0){
   b.prepare(swim.under);
   pace=sprint.control(swim.under?load(34719).xC.under:load(34719).xC.water,row.delta*50,row.tap,row.running,b.value);
   swim.steer({push:row.push,sprint:pace>=1?pace:0,dive:row.dive,pitch:0});
   if(pace<1||swim.under)b.value.rest(50*row.delta*(swim.state===load(19863).xO.BREAST?.25:.5));
  }else if(wasOn)swim.steer({push:row.push,sprint:0,dive:row.dive,pitch:0});
  if(wasOn)swim.step(row.delta,{depth:row.depth,grounded:false,heading:0,feet:v([1480,102-scenario.depth,0]),dead:row.health<=0});
  else swim.ashore(row.delta);
  const label=scenario.name+'/'+i;
  check(row.value,b.current,label+'/budget');check(row.counter,sprint.counter,label+'/counter');
  check(row.breath,swim.breath,label+'/breath');check(row.display,display(swim),label+'/display');
  check(row.on,swim.on,label+'/on');check(row.state,swim.state,label+'/state');
 }
}
for(const scenario of traces.parachute){let b=budget(scenario.initial);for(const [i,row]of scenario.frames.entries()){
 if(row.health>0&&row.chuting)b.rest(50*row.delta,0);
 check(row.value,b.current,scenario.name+'/'+i+'/budget');check(row.counter,row.initialCounter,scenario.name+'/'+i+'/counterRetained');
}}
for(const scenario of traces.foot){let b=budget(scenario.initial);const sprint=load(34719).jZ();let pace=0;for(const [i,row]of scenario.frames.entries()){
 if(row.reset){b.reset();sprint.reset();pace=0;}
 if(row.health>0){
  if(!row.airborne)pace=sprint.control(load(34719).xC.foot,50*row.delta,row.tap,row.running,b.value);
  if(pace<1)b.rest(50*row.delta,row.ratio);
 }
 check(row.value,b.current,scenario.name+'/'+i+'/budget');check(row.counter,sprint.counter,scenario.name+'/'+i+'/counter');
}}
const report={status:baseline?(failures.length?'RECORDED FAILURE':'UNEXPECTED PASS'):(failures.length?'FAIL':'PASS'),checks,failures:failures.slice(0,30),failureCount:failures.length,byCase,factorySHA256,
 limits:['Actual selected archived steering/recovery/status expressions and actual sprint/swim controllers','Actual current Renderer methods, original local CLP and native Rapier; controlled water/ground poses','No retail runtime, skill curve, body modifier, device FPS or physical-control claim']};
fs.writeFileSync(path.join(output,'comparison.json'),JSON.stringify(report,null,2)+'\n');
console.log(JSON.stringify({status:report.status,checks,failures:failures.length,byCase}));
if(baseline?!failures.length:failures.length)process.exitCode=1;
'''

def methods(renderer):
    foot='\n\n'.join(function(renderer,marker) for marker in FOOT)
    foot+='\n'+function(renderer,'var hasNativeFootWeaponTiming:')
    if '    private func combatEligibility(' in renderer:
        foot+='\n'+'\n'.join(function(renderer,marker) for marker in ['private func combatEligibility(','var canRequestFootWeaponFire:','var canEmitFootCombatMarker:','var canEmitFootWeaponShot:'])
    a=renderer.index('    private var weaponEventFeet:');foot=renderer[a:renderer.index('    func weaponMuzzle(',a)]+'\n'+foot
    water='\n\n'.join(function(renderer,marker) for marker in WATER)
    if '    private func combatEligibility(' in renderer:water+='\n'+function(renderer,'private func combatEligibility(')
    a=renderer.index('        if !driving, let character {\n            lastFootVelocity =');publish=renderer[a:renderer.index('\n        if let characterOutput',a)]
    a=renderer.index('motion: { [self] step,state,intended in');boundary=renderer[renderer.index('\n',a):renderer.index('                    if let held=climbingMotion',a)]
    return foot,water,publish,boundary

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--baseline-renderer',type=Path);args=parser.parse_args()
    output=OUT/('baseline' if args.baseline_renderer else 'current');output.mkdir(parents=True,exist_ok=True)
    renderer=(args.baseline_renderer or ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
    selected=methods(renderer)
    snapshot={name:(ROOT/'ios/App'/f'{name}.swift').read_bytes() for name in NAMES}
    skeletal=(ROOT/'ios/App/NativeSkeletalActor.swift').read_text()
    source=skeletal[:skeletal.index('struct NativeSkinVertex')].replace('import Metal','')
    source+='\nfinal class NativeSkeletalActor {\n'+skeletal[skeletal.index('    struct OriginalAim {'):skeletal.index('    struct Pose {')]+'}\n'
    source+='\n'.join(value.decode() for value in snapshot.values())
    climb=(ROOT/'smoke_native_climb_runtime.swift').read_text().split('@main enum ClimbRuntimeSmoke')[0]
    climb=climb.replace('    var hasNativeFootWeaponTiming=false\n','')
    water=(ROOT/'smoke_native_fixed_velocity.swift').read_text().split('@main enum Gate')[0]
    source+='\n'+climb.replace('// ACTUAL_RENDERER_METHODS',selected[0])
    source+='\n'+water.replace('// ACTUAL_HANDOFFS',selected[1]).replace('// ACTUAL_PUBLISH',selected[2]).replace('// ACTUAL_MOTION_BOUNDARY',selected[3])
    source+='\n'+(ROOT/'smoke_native_effort_recovery.swift').read_text()
    (output/'runtime-source.swift').write_text(source)
    with tempfile.TemporaryDirectory(prefix='effort-',dir=output) as temp:
        folder=Path(temp);main=folder/'main.swift';main.write_text(source);exe=folder/'verify'
        physics=['SwiftRapierWorld','NativeCharacterMotor','NativeRapierCharacterQueries','NativeCharacterController','NativeClimbController','NativeRapierClimbQueries']
        command=['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-Onone','-module-cache-path',str(OUT/'modules'),'-I',str(ROOT/'native-physics/include'),
                 *[str(ROOT/'ios/App'/f'{name}.swift') for name in physics],str(main),'-L',str(ROOT/f'local-only/native-physics/macos-{platform.machine()}'),'-lzgtasa_native_physics',
                 '-framework','Security','-framework','CoreFoundation','-o',str(exe)]
        result=subprocess.run(command,capture_output=True,text=True);(output/'compile.log').write_text(result.stdout+result.stderr)
        if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
        subprocess.run([str(exe),str(ROOT),str(output/'native.json')],check=True)
        node=folder/'reference.js';node.write_text(JS)
        result=subprocess.run(['node',str(node),str(ROOT),str(output),'baseline' if args.baseline_renderer else 'current'],capture_output=True,text=True)
        sameOwned=all((ROOT/'ios/App'/f'{name}.swift').read_bytes()==data for name,data in snapshot.items())
        sameMethods=methods((args.baseline_renderer or ROOT/'ios/App/NativeWorldRenderer.swift').read_text())==selected
        report={'status':'PASS' if result.returncode==0 and sameOwned and sameMethods else 'FAIL','mode':'historical negative' if args.baseline_renderer else 'current',
                'output':result.stdout+result.stderr,'ownedSourcesUnchanged':sameOwned,'selectedRendererMethodsUnchanged':sameMethods,
                'sourceHashes':{name:hashlib.sha256(value).hexdigest() for name,value in snapshot.items()},
                'rendererMethodsSHA256':hashlib.sha256('\n'.join(selected).encode()).hexdigest(),
                'localCLPSHA256':hashlib.sha256((ROOT/'local-only/site/game/native/models/animations.clips.bin').read_bytes()).hexdigest()}
        (output/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert sameOwned and sameMethods,'Sources changed during test; rerun after scope freeze'
if __name__=='__main__':main()
