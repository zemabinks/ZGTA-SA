#!/usr/bin/env python3
"""Deterministic native target/LOS/emission regression without UIKit or Metal."""
from pathlib import Path
import subprocess,tempfile
from smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parent

def main():
 vc=(ROOT/'ios/App/NativeGameViewController.swift').read_text()
 methods='\n'.join(function(vc,marker) for marker in ['private func currentShotRay(','private func emitWeaponShot('])
 source=(ROOT/'smoke_native_shot_targeting.swift').read_text().replace('// ACTUAL_EMISSION_METHODS',methods)
 with tempfile.TemporaryDirectory(prefix='zgtasa-shot-targets-') as temporary:
  work=Path(temporary);(work/'verify.swift').write_text(source)
  subprocess.run(['swiftc','-parse-as-library','-whole-module-optimization','-Onone','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',
    str(ROOT/'ios/App/NativeShotTargeting.swift'),str(ROOT/'ios/App/WorldCollision.swift'),str(ROOT/'ios/App/NativeInventoryPrediction.swift'),str(work/'verify.swift'),'-o',str(work/'verify')],check=True)
  subprocess.run([str(work/'verify'),str(ROOT)],check=True)
if __name__=='__main__':main()
