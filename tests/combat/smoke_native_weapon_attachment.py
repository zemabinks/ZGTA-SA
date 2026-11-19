#!/usr/bin/env python3
"""Offline real Ko/R6 equipment geometry, selection and lifecycle replay.

Original assets/references stay ignored. Only unused GPU buffer storage is
replaced; actual native rig parsing, animation and attachment math execute.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]

def declaration(source,token):
 begin=source.index(token);start=source.index('{',begin);depth=1;end=start+1
 while depth:
  if source[end]=='{':depth+=1
  elif source[end]=='}':depth-=1
  end+=1
 return source[begin:end]

def native_policy(out):
 renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
 foot=(ROOT/'ios/App/NativeFootAnimation.swift').read_text()
 source='import Foundation\nimport simd\n'+(ROOT/'ios/App/NativeWeaponAttachment.swift').read_text()
 source+='\n'+(ROOT/'ios/App/NativeGunAnimation.swift').read_text()
 source+='\n'+declaration(foot,'struct NativeSkeletalBlend {')
 source+='\n'+(ROOT/'ios/App/NativeFlightAnimation.swift').read_text()
 source+='\nstruct EquipmentFrame {var blends:[NativeSkeletalBlend]\n'+declaration(foot,'var handWeaponVisible: Bool {')+'\n}\n'
 source+='''struct EquipmentInput {
 struct Flight {var chuting=false;var flying=false}
 var personalFlight=Flight(),swimming=false,equippedWeapon=0
 var footWeaponDefinitions:[Int:NativeFootWeaponAnimation]=[:]
 '''+declaration(renderer,'var effectiveWireWeapon:Int {')+'\n}\n'
 source+='''
let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])),weapons=try NativeFootWeaponAnimation.load(data:data)
var input=EquipmentInput(),checks=0
input.footWeaponDefinitions=weapons
func check(_ value:Bool,_ message:String){precondition(value,message);checks += 1}
for selected in weapons.keys {
 check(weapons[selected]!.arm == (weapons[selected]?.flags?["arm"]==true),"Original OP arm flag equals held visibility flag")
 for state in 0...13 {for swimming in [false,true] {
 input.equippedWeapon=selected;input.swimming=swimming
 input.personalFlight.chuting=(1...9).contains(state);input.personalFlight.flying=state==12||state==13
 let carried=input.personalFlight.chuting ? 46:selected
 let expected = !swimming && (!input.personalFlight.flying || weapons[carried]?.flags?["arm"]==true) ? carried:0
 check(input.effectiveWireWeapon==expected,"Actual native effective selection property")
}}}
let flight=NativeFlightAnimation(duration:{_ in 1})
for state in 1...13 {
 let frame=flight.update(delta:1/60,input:.init(state:state),position:.zero,heading:0)
 let held=EquipmentFrame(blends:frame.blends+[.init(clip:"ped/idle_stance",weight:0.1)])
 check(held.handWeaponVisible,"Actual foot visibility alone does not hide old22 in flight")
 input.personalFlight.chuting=(1...9).contains(state);input.personalFlight.flying=state==12||state==13
 input.equippedWeapon=22;input.swimming=false
 check(input.effectiveWireWeapon == ((1...9).contains(state) ? 46:22),"Native auto-bag policy aligns carried model/wire while retaining ammo selection")
}
for clip in ["swim/breast","ped/swim_tread","ped/climb_idle"] {
 check(!EquipmentFrame(blends:[.init(clip:clip,weight:0.1)]).handWeaponVisible,"Traversal owns hands")
 check(EquipmentFrame(blends:[.init(clip:clip,weight:0)]).handWeaponVisible,"Zero-weight old traversal releases hands")
}
try JSONSerialization.data(withJSONObject:["nativePolicyChecks":checks,"nativePolicy":"Separate flightGear auto-carries46 through chute1..9; full inventory utility slot remains unported"]).write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
print("PASS actual native effective-property/flight-visibility contracts: \\(checks) checks")
'''
 with tempfile.TemporaryDirectory(prefix='policy-',dir=out) as temporary:
  work=Path(temporary);(work/'main.swift').write_text(source)
  subprocess.run(['swiftc','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',str(work/'main.swift'),'-o',str(work/'verify')],check=True)
  subprocess.run([str(work/'verify'),str(ROOT/'local-only/site/game/native/foot-animation.json'),str(out/'native-policy.json')],check=True)
 assert '? 0:effectiveWireWeapon' in renderer
 assert 'weapon:renderer.effectiveWireWeapon' in (ROOT/'ios/App/NativeGameViewController.swift').read_text()

def main():
 out=ROOT/'local-only/research/remaining-equipment';out.mkdir(parents=True,exist_ok=True)
 subprocess.run(['node','tests/combat/smoke_native_weapon_attachment_reference.js',str(out/'attachment-reference.json')],cwd=ROOT,check=True)
 skeletal=(ROOT/'ios/App/NativeSkeletalActor.swift').read_text().split('\nextension NativeSkeletalActor {',1)[0].replace('import Metal','')
 begin=skeletal.index('    func bind(pose: Pose, encoder:');end=skeletal.index('    /// CPU reference',begin)
 skeletal=skeletal[:begin]+skeletal[end:]
 source='''import Foundation
final class MTLBuffer {}
final class MTLDevice {
 enum Options {case storageModeShared}
 func makeBuffer<T>(bytes:[T],length:Int,options:Options)->MTLBuffer? {MTLBuffer()}
}
'''+skeletal
 motion=(ROOT/'ios/App/NativeActorAnimation.swift').read_text();source+='\n'+motion[motion.index('struct NativePedestrianMotion {'):motion.index('struct NativeWeaponAnimation {')]
 for name in ['NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativeWeaponAttachment']:
  source+='\n'+(ROOT/'ios/App'/f'{name}.swift').read_text()
 source+='\n'+(ROOT/'tests/combat/smoke_native_weapon_attachment.swift').read_text()
 with tempfile.TemporaryDirectory(prefix='run-',dir=out) as temporary:
  work=Path(temporary);(work/'main.swift').write_text(source)
  subprocess.run(['swiftc','-O','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',str(work/'main.swift'),'-o',str(work/'verify')],check=True)
  subprocess.run([str(work/'verify'),str(ROOT),str(out/'attachment-reference.json'),str(out/'report.json')],check=True)
 # Narrow source integration contract. Event-time muzzle code is deliberately
 # outside the edited block; left-hand gun attachment retains its existing API.
 renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text();begin=renderer.index('            let heldWeapon = NativeWeaponAttachment.selectedWeapon(');end=renderer.index('            if let flight=queued?.flight',begin);block=renderer[begin:end]
 assert 'NativeWeaponAttachment.transform(weapon:heldWeapon,rightHand:rightHand,spine:spine)' in block
 assert 'matrix * transform * attachment' in block
 assert 'NativeWeaponMuzzle.attachment(left:true)' in block
 assert 'personalFlight.flying' in block and 'flags?["arm"] == true' in block
 assert 'actor.transform(bone:NativeWeaponAttachment.rightHandBone,in:pose)' in block
 native_policy(out)
 report=json.loads((out/'report.json').read_text());report['rendererIntegrationChecks']=7
 report.update(json.loads((out/'native-policy.json').read_text()))
 (out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
 print('PASS held-renderer/wire integration: 7 source contracts; event-time muzzle remains separate')
if __name__=='__main__':main()
