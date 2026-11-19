#!/usr/bin/env python3
"""Actual archived R6 and native CLP combat interruption/utility replay."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,importlib.util,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/research/combat-88/interruptions';OUT.mkdir(parents=True,exist_ok=True)
NAMES=['NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation']
FILES=['ios/App/NativeSkeletalActor.swift']+[f'ios/App/{n}.swift' for n in NAMES]+['tests/movement/smoke_native_foot_animation.py','tests/combat/smoke_native_combat_interruptions.py']
inputs={n:(ROOT/n).read_bytes() for n in FILES}
spec=importlib.util.spec_from_file_location('existing_foot_reference',ROOT/'tests/movement/smoke_native_foot_animation.py');reference_module=importlib.util.module_from_spec(spec);spec.loader.exec_module(reference_module)
JS=reference_module.JS
a=JS.index(' const scenarios=[');b=JS.index(' const cases=[];',a)
JS=JS[:a]+r'''
 const scenarios=[];
 for(const weapon of [0,5,9,16,17,18,22,24,26,30,32,34,35,36,37,38,39,40,41,42,43,44,45,46])for(const mode of ['reload-stance','death','knock','switch'])scenarios.push({
  name:weapon+'-'+mode,weapon,frames:300,
  input:i=>({ratio:0,crouch:i>=55&&i<150||i>=220,gun:{pitch:.3,yaw:-.2}}),
  control:i=>({aim:true,fire:i>=20&&i<75||i>=130&&i<260,held:i>=20&&i<75||i>=130&&i<260,ready:!(i>=175&&i<205)}),
  method:i=>{const task=mode==='reload-stance'?(i===50?['reload']:i===90?['cancelFire']:null):mode==='death'?(i===50?['die','koFront']:i===110?['revive']:null):mode==='knock'?(i===50?['knock','koSkidBack']:i===130?['flinch','flinch',true]:null):(i===50?['arm',22]:i===150?['arm',weapon]:null);return task||([20,140,240].includes(i)?['fire',true]:null)}
 });
''' +JS[b:]
# This gate compares controller state/travel, not skinned mesh/GPU output.
a=JS.index('   if(frame%9===0 || method){');brace=JS.index('{',a);end=brace+1;depth=1
while depth:depth+=(JS[end]=='{')-(JS[end]=='}');end+=1
JS=JS[:a]+JS[end:]
SWIFT=r'''
let root=URL(fileURLWithPath:CommandLine.arguments[1]),game=root.appendingPathComponent("local-only/site/game")
let library=NativeSkeletalAnimationLibrary(data:try Data(contentsOf:game.appendingPathComponent("native/models/animations.clips.bin")))!
let profiles=try NativeFootWeaponAnimation.load(data:Data(contentsOf:game.appendingPathComponent("native/foot-animation.json")))
let definitions=try NativeFootAnimationDefinitions(data:Data(contentsOf:game.appendingPathComponent("world/peds.json")))
let rows=try JSONDecoder().decode(ExactFixtureJSON.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2]))).any as! [[String:Any]]
var scenario="",animator:NativeFootAnimation!,checks=0,shots=0,failures:[String]=[]
func check(_ v:Bool,_ message:String){checks+=1;if !v{failures.append(message)}}
func n(_ d:[String:Any],_ k:String)->Double{(d[k] as? NSNumber)?.doubleValue ?? 0}
for row in rows {
 let label=row["scenario"] as! String,i=row["frame"] as! Int
 if label != scenario {scenario=label;animator=NativeFootAnimation(library:library,style:definitions.style(model:"bmori",library:library),random:{0.37});animator.arm(profiles[row["weapon"] as! Int])}
 if let method=row["method"] as? [Any],let name=method.first as? String {
  switch name {
   case "reload":_=animator.reload()
   case "fire":_=animator.fire(held:method[1] as! Bool)
   case "cancelFire":animator.cancelFire()
   case "die":animator.die(method[1] as! String)
   case "revive":animator.revive()
   case "knock":_=animator.knock(method[1] as! String)
   case "flinch":animator.flinch(method[1] as! String,stun:method[2] as! Bool)
   case "arm":animator.arm(profiles[method[1] as! Int])
   default:preconditionFailure("Unknown actual reference method")
  }
 }
 let c=row["control"] as! [String:Bool],v=row["input"] as! [String:Any],g=v["gun"] as! [String:Any],e=row["expected"] as! [String:Any]
 animator.control(.init(fire:c["fire"]!,aim:c["aim"]!,held:c["held"]!,ready:c["ready"]!))
 var input=NativeFootAnimation.Input();input.ratio=n(v,"ratio");input.crouch=v["crouch"] as! Bool;input.gun = .init(pitch:n(g,"pitch"),yaw:n(g,"yaw"))
 let frame=animator.update(delta:n(row,"delta"),input:input)
 for(key,value)in[("reloading",animator.reloading),("firing",animator.firing),("gunUp",animator.gunUp),("gunShooting",animator.gunShooting),("fired",animator.fired),("busy",animator.busy),("rolling",animator.rolling),("stunned",animator.stunned),("dead",animator.dead),("fallen",animator.fallen),("shot",frame.shot),("shotLeft",frame.shotLeft)] {
  check(value==e[key] as! Bool,"\(label):\(i) \(key): native\(value) archived\(e[key]!)")
 }
 check(animator.swing==e["swing"] as! Int,"\(label):\(i) combo index differs")
 let travel=e["travel"] as! [NSNumber]
 check(abs(frame.travel.x-travel[0].doubleValue)<1e-9 && abs(frame.travel.y-travel[1].doubleValue)<1e-9,"\(label):\(i) raw animation root travel differs")
 if frame.shot {shots+=1}
}
if !failures.isEmpty {print("FAIL actual combat interruptions: \(failures.count)/\(checks) checks",failures.prefix(40));exit(1)}
print("PASS actual combat interruptions: \(checks) checks /\(rows.count) frames /96 scenarios; reload/crouch/cancel/death/knock/stun/switch and utility profiles, \(shots) raw markers")
'''
def main():
    with tempfile.TemporaryDirectory(prefix='run-',dir=OUT) as temp:
        p=Path(temp);js=p/'reference.js';js.write_text(JS);order=p/'order.json';order.write_text('[]');reference=p/'reference.json'
        subprocess.run(['node',str(js),str(order),str(reference)],cwd=ROOT,check=True)
        skeletal=inputs['ios/App/NativeSkeletalActor.swift'].decode();source=skeletal[:skeletal.index('struct NativeSkinVertex')].replace('import Metal','')
        source+='\nfinal class NativeSkeletalActor {\n'+skeletal[skeletal.index('    struct OriginalAim {'):skeletal.index('    struct Pose {')]+'}\n'
        exact_decoder=reference_module.SWIFT[:reference_module.SWIFT.index('let root=URL')]
        source+='\n'+'\n'.join(inputs[f'ios/App/{n}.swift'].decode() for n in NAMES)+'\n'+exact_decoder+SWIFT
        (p/'verify.swift').write_text(source);exe=p/'verify'
        compiled=subprocess.run(['xcrun','swiftc','-module-cache-path',str(OUT/'modules'),str(p/'verify.swift'),'-o',str(exe)],capture_output=True,text=True)
        (OUT/'compile.log').write_text(compiled.stdout+compiled.stderr)
        if compiled.returncode:print(compiled.stdout+compiled.stderr);compiled.check_returncode()
        result=subprocess.run([str(exe),str(ROOT),str(reference)],capture_output=True,text=True)
        (OUT/'reference.json').write_bytes(reference.read_bytes())
        (OUT/'report.json').write_text(json.dumps({'status':'PASS' if result.returncode==0 else 'FAIL','output':result.stdout+result.stderr,
          'sourceHashes':{n:hashlib.sha256(v).hexdigest() for n,v in inputs.items()},
          'limits':['Actual archived R6/Three/ANP3 with native CLP state/root replay, ordinary Node tooling; no retail runtime or REA capture ID','Raw animation compatibility, not proof that every raw marker is permitted to spend ammo; task eligibility/delivery tested separately']},indent=2)+'\n')
        print(result.stdout,end='');print(result.stderr,end='');result.check_returncode()
if __name__=='__main__':main()
