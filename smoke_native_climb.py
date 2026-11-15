#!/usr/bin/env python3
"""Replay exact archived climb functions against native controller and queries.

CPU-only. Game bundles/animation values and generated fixtures remain under
ignored local-only/. This is browser-reference verification, not retail proof.
"""
from pathlib import Path
import json,platform,subprocess,tempfile
import prepare_native_animations as archive
ROOT=Path(__file__).resolve().parent

def main():
 evidence=ROOT/'local-only/research/climbing'
 evidence.mkdir(parents=True,exist_ok=True)
 clips=archive.clips_from_anp3(ROOT/'local-only/site/game/world/pedanims.bin',('climb_jump','climb_pull','climb_stand','climb_jump_b'))
 durations={name:clips[clip][0] for name,clip in [('jump','climb_jump'),('pull','climb_pull'),('stand','climb_stand'),('vault','climb_jump_b')]}
 (evidence/'durations.json').write_text(json.dumps(durations))
 subprocess.run(['node',str(ROOT/'smoke_native_climb_reference.js'),str(evidence/'durations.json'),str(evidence/'reference.json')],cwd=ROOT,check=True)
 common=['swiftc','-whole-module-optimization','-Onone','-module-cache-path','/private/tmp/zgtasa-core-swift-modules']
 with tempfile.TemporaryDirectory(prefix='zgtasa-climb-') as temporary:
  executable=Path(temporary)/'controller'
  subprocess.run([*common,str(ROOT/'ios/App/NativeClimbController.swift'),str(ROOT/'smoke_native_climb.swift'),'-o',str(executable)],check=True)
  subprocess.run([str(executable),str(evidence/'reference.json')],check=True)
  geometry=Path(temporary)/'geometry'
  subprocess.run([*common,'-I',str(ROOT/'native-physics/include'),str(ROOT/'ios/App/SwiftRapierWorld.swift'),
   str(ROOT/'ios/App/NativeClimbController.swift'),str(ROOT/'ios/App/NativeRapierClimbQueries.swift'),str(ROOT/'smoke_native_climb_geometry.swift'),
   '-L',str(ROOT/f'local-only/native-physics/macos-{platform.machine()}'),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(geometry)],check=True)
  subprocess.run([str(geometry),str(evidence/'reference.json')],check=True)
if __name__=='__main__':main()
