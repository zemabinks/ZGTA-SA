#!/usr/bin/env python3
"""Actual R6/controller melee replay and extracted Renderer marker delivery."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess,tempfile
from tests.movement.smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parents[2]
def main():
 out=ROOT/'local-only/research/melee';out.mkdir(parents=True,exist_ok=True)
 assert (ROOT/'local-only/native/melee.json').is_file(),'Prepare owner-local melee metadata before this read-only replay'
 subprocess.run(['node','tests/combat/smoke_native_melee_reference.js',str(out/'reference.json')],cwd=ROOT,check=True)
 skeletal=(ROOT/'ios/App/NativeSkeletalActor.swift').read_text();source=skeletal[:skeletal.index('struct NativeSkinVertex')].replace('import Metal','')
 source+='\nfinal class NativeSkeletalActor {\n'+skeletal[skeletal.index('    struct OriginalAim {'):skeletal.index('    struct Pose {')]+'}\n'
 for name in ['NativeCombatEligibility','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativeFootLocomotion','NativeMelee','NativeMeleeInput']:
  source+='\n'+(ROOT/'ios/App'/f'{name}.swift').read_text()
 renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
 markers=['    private func combatEligibility(','    var canEmitFootWeaponShot:','    var canEmitFootCombatMarker:','    var hasNativeFootWeaponTiming:','    private var activeMeleeDefinition:','    var hasNativeFootMeleeTiming:','    var canNativeFootMeleeGuard:','    @discardableResult func requestFootMeleeAttack(','    private func meleeControls(','    private func advanceMelee(','    private func emitFootWeaponEvents(','    func cancelWeaponInput()']
 methods='\n'.join(function(renderer,x) for x in markers)
 source+='\n'+(ROOT/'tests/combat/smoke_native_melee.swift').read_text().replace('// ACTUAL_RENDERER_METHODS',methods)
 with tempfile.TemporaryDirectory(prefix='run-',dir=out) as temp:
  work=Path(temp);(work/'main.swift').write_text(source)
  subprocess.run(['swift','-module-cache-path','/private/tmp/zgta-macos-swift-modules',str(work/'main.swift'),str(ROOT),str(out/'reference.json')],check=True)
if __name__=='__main__':main()
