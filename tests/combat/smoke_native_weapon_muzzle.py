#!/usr/bin/env python3
"""Replay actual archived Ko/R6 with local game rigs; never publish fixtures.

Only GPU buffer storage/bind are replaced in the source-derived CPU harness.
The real skeleton parser, originalPose, hand transforms and animation run as-is.
Original installer weapon.dat is a data check, not a retail runtime comparison.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,hashlib,json,os,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]

def retail_offsets(out,source):
 if source is None or not source.is_file():
  (out/'retail-offset-report.json').write_text(json.dumps({'status':'SKIP','reason':'Optional original weapon.dat not supplied; set ZGTASA_WEAPON_DAT or --weapon-dat'})+'\n')
  print('SKIP original weapon.dat data comparison: optional owner-supplied reference absent')
  return
 browser=ROOT/'local-only/site/game/native/weapons.json'
 rows={}
 for line in source.read_text(encoding='cp1252').splitlines():
  parts=line.split('#',1)[0].split()
  if len(parts)>14 and parts[0]=='$':rows[parts[1],int(parts[14])]=list(map(float,parts[11:14]))
 count=0
 for value in json.loads(browser.read_text())['stats'].values():
  for level in [value]+value.get('levels',[]):
   if 'skill' not in level:continue
   expected=rows[level['name'],level['skill']]
   assert all(abs(a-b)<1e-8 for a,b in zip(expected,level['offset'])),(level['name'],level['skill'])
   count+=1
 result={'status':'PASS','authority':'Original installer weapon.dat data, not executable behavior','rows':count,'retailSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),'catalogSHA256':hashlib.sha256(browser.read_bytes()).hexdigest()}
 (out/'retail-offset-report.json').write_text(json.dumps(result,indent=2)+'\n')
 print('PASS original weapon.dat:',count,'selected/skill offset rows')

def main():
 parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--weapon-dat',type=Path,default=os.environ.get('ZGTASA_WEAPON_DAT'));args=parser.parse_args()
 reference=Path(args.weapon_dat) if args.weapon_dat else next((p for p in [ROOT/'local-only/retail-reference/installed-selected/data/weapon.dat',ROOT.parent/'ZGTA-SA-core-next/local-only/retail-reference/installed-selected/data/weapon.dat'] if p.is_file()),None)
 out=ROOT/'local-only/research/muzzle';out.mkdir(parents=True,exist_ok=True)
 retail_offsets(out,reference)
 subprocess.run(['node','tests/combat/smoke_native_weapon_muzzle_reference.js',str(out/'rig-reference.json')],cwd=ROOT,check=True)
 skeletal=(ROOT/'ios/App/NativeSkeletalActor.swift').read_text().split('\nextension NativeSkeletalActor {',1)[0].replace('import Metal','')
 begin=skeletal.index('    func bind(pose: Pose, encoder:')
 end=skeletal.index('    /// CPU reference',begin)
 skeletal=skeletal[:begin]+skeletal[end:]
 shim='''import Foundation
final class MTLBuffer {}
final class MTLDevice {
 enum Options {case storageModeShared}
 func makeBuffer<T>(bytes:[T],length:Int,options:Options)->MTLBuffer? {MTLBuffer()}
}
'''
 motion=(ROOT/'ios/App/NativeActorAnimation.swift').read_text()
 motion=motion[motion.index('struct NativePedestrianMotion {'):motion.index('struct NativeWeaponAnimation {')]
 source=shim+skeletal+'\n'+motion
 for name in ['NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativeShotTargeting','NativeWeaponMuzzle']:
  source+='\n'+(ROOT/'ios/App'/f'{name}.swift').read_text()
 source+='\n'+(ROOT/'tests/combat/smoke_native_weapon_muzzle.swift').read_text()
 with tempfile.TemporaryDirectory(prefix='run-',dir=out) as temporary:
  work=Path(temporary);(work/'main.swift').write_text(source)
  subprocess.run(['swiftc','-O','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',str(work/'main.swift'),'-o',str(work/'verify')],check=True)
  subprocess.run([str(work/'verify'),str(ROOT),str(out/'rig-reference.json'),str(out/'report.json')],check=True)
if __name__=='__main__':main()
