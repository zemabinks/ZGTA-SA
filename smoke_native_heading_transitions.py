#!/usr/bin/env python3
"""Run native task-heading regression and retain only local proof metrics."""
from pathlib import Path
import hashlib,json,math,subprocess,tempfile
import prepare_native_animations as archive
ROOT=Path(__file__).resolve().parent

def main():
 with tempfile.TemporaryDirectory(prefix='zgta-core-heading-') as temporary:
  work=Path(temporary)
  sources=['ios/App/NativePersonalFlightController.swift','ios/App/NativeFootLocomotion.swift',
           'ios/App/NativeHeadingContinuity.swift','smoke_native_heading_transitions.swift']
  subprocess.run(['swiftc','-whole-module-optimization','-Onone','-module-cache-path',
                  '/private/tmp/zgtasa-core-swift-modules',*[str(ROOT/p) for p in sources],
                  '-o',str(work/'verify')],check=True)
  subprocess.run([str(work/'verify'),str(ROOT)],check=True)
 path=ROOT/'local-only/research/heading-transitions.json'
 report=json.loads(path.read_text())
 asset=ROOT/'local-only/site/game/world/pedanims.bin'
 duration,tracks=archive.clips_from_anp3(asset,('idle_stance',))['idle_stance']
 first,last=tracks[0][0][1],tracks[0][-1][1]
 dot=abs(sum(a*b for a,b in zip(first,last)))/math.sqrt(sum(x*x for x in first)*sum(x*x for x in last))
 angle=2*math.acos(min(1,dot))*180/math.pi
 assert angle<1e-6
 report['assetCheck']={'source':'Local ANP3 ped idle_stance; current jetpack display uses the normal foot base',
  'sha256':hashlib.sha256(asset.read_bytes()).hexdigest(),'idleDuration':duration,'rootFirstLastRotationDegrees':angle,
  'authority':'animation bytes only; not a retail runtime capture'}
 path.write_text(json.dumps(report,indent=2)+'\n')
 print('PASS original local idle root has no half-turn; baseline/fix proof:',path)
if __name__=='__main__':main()
