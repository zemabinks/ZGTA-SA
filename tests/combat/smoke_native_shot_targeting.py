#!/usr/bin/env python3
"""Deterministic native target/LOS/emission regression without UIKit or Metal."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess,tempfile
from tests.movement.smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parents[2]

def main():
 vc=(ROOT/'ios/App/NativeGameViewController.swift').read_text()
 methods='\n'.join(function(vc,marker) for marker in ['private func currentShotRay(','private func emitWeaponShot('])
 source=(ROOT/'tests/combat/smoke_native_shot_targeting.swift').read_text().replace('// ACTUAL_EMISSION_METHODS',methods)
 with tempfile.TemporaryDirectory(prefix='zgtasa-shot-targets-') as temporary:
  work=Path(temporary);(work/'verify.swift').write_text(source)
  subprocess.run(['swiftc','-parse-as-library','-whole-module-optimization','-Onone','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',
    str(ROOT/'ios/App/NativeShotTargeting.swift'),str(ROOT/'ios/App/NativeWeaponMuzzle.swift'),str(ROOT/'ios/App/NativeStreamShotClaims.swift'),str(ROOT/'ios/App/WorldCollision.swift'),str(ROOT/'ios/App/NativeInventoryPrediction.swift'),str(work/'verify.swift'),'-o',str(work/'verify')],check=True)
  subprocess.run([str(work/'verify'),str(ROOT)],check=True)
if __name__=='__main__':main()
