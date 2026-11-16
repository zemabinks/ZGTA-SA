#!/usr/bin/env python3
"""Exercise current Renderer climb/foot methods with real animation/native core."""
from pathlib import Path
import hashlib,platform,subprocess,tempfile
ROOT=Path(__file__).resolve().parent

def function(source,marker):
 start=source.index(marker)
 opening=source.index('{',start)
 depth=0;quote=False;escape=False
 for index in range(opening,len(source)):
  char=source[index]
  if quote:
   if escape:escape=False
   elif char=='\\':escape=True
   elif char=='"':quote=False
   continue
  if char=='"':quote=True;continue
  if char=='{':depth+=1
  elif char=='}':
   depth-=1
   if depth==0:return source[start:index+1]
 raise RuntimeError('Unbalanced Swift method: '+marker)

def main():
 renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
 methods=['private func combatEligibility(','var canEmitFootWeaponShot:','var canEmitFootCombatMarker:','var hasNativeFootWeaponTiming:','private func footMotion(','private func beginClimb(','private func climbingMotion(',
          'private func emitFootWeaponEvents(','func cancelWeaponInput(','func cancelGameplayInput(','func letGoOfLedge(',
          'private var activeMeleeDefinition:','var hasNativeFootMeleeTiming:','var canNativeFootMeleeGuard:',
          'private func meleeControls(','private func advanceMelee(']
 extracted='\n\n'.join(function(renderer,marker) for marker in methods)
 shot_feet=renderer[renderer.index('    private var weaponEventFeet:'):renderer.index('    func weaponMuzzle(',renderer.index('    private var weaponEventFeet:'))]
 extracted=shot_feet+'\n'+extracted
 skeletal=(ROOT/'ios/App/NativeSkeletalActor.swift').read_text()
 library=skeletal[:skeletal.index('struct NativeSkinVertex')].replace('import Metal','')
 aim=skeletal[skeletal.index('    struct OriginalAim {'):skeletal.index('    struct Pose {')]
 source=library+'\nfinal class NativeSkeletalActor {\n'+aim+'}\n'
 names=['NativeCombatEligibility','NativeGunAnimation','NativeSwimAnimation','NativeFlightAnimation','NativeFootAnimation','NativePersonalFlightController',
        'NativeFootLocomotion','NativeHeadingContinuity','NativeSprintController','NativeMelee','NativeMeleeInput','NativeFallDamage']
 for name in names:source+='\n'+(ROOT/'ios/App'/f'{name}.swift').read_text()
 source+='\n'+(ROOT/'smoke_native_climb_runtime.swift').read_text().replace('// ACTUAL_RENDERER_METHODS',extracted)
 evidence_directory=ROOT/'local-only/research/climbing'
 evidence_directory.mkdir(parents=True,exist_ok=True)
 subprocess.run(['node',str(ROOT/'smoke_native_climb_entry.js'),str(evidence_directory/'entry-reference.json')],cwd=ROOT,check=True)
 (evidence_directory/'runtime-source.swift').write_text(source)
 with tempfile.TemporaryDirectory(prefix='zgtasa-climb-runtime-') as temporary:
  work=Path(temporary);(work/'main.swift').write_text(source)
  command=['swiftc','-parse-as-library','-whole-module-optimization','-Onone','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',
    '-I',str(ROOT/'native-physics/include'),str(ROOT/'ios/App/SwiftRapierWorld.swift'),str(ROOT/'ios/App/NativeCharacterMotor.swift'),
    str(ROOT/'ios/App/NativeRapierCharacterQueries.swift'),str(ROOT/'ios/App/NativeCharacterController.swift'),
    str(ROOT/'ios/App/NativeClimbController.swift'),str(ROOT/'ios/App/NativeRapierClimbQueries.swift'),str(work/'main.swift'),
    '-L',str(ROOT/f'local-only/native-physics/macos-{platform.machine()}'),'-lzgtasa_native_physics',
    '-framework','Security','-framework','CoreFoundation','-o',str(work/'verify')]
  subprocess.run(command,check=True)
  subprocess.run([str(work/'verify'),str(ROOT)],check=True)
 evidence=ROOT/'local-only/research/climbing/runtime-methods.sha256'
 evidence.write_text(hashlib.sha256(extracted.encode()).hexdigest()+'\n')
if __name__=='__main__':main()
