#!/usr/bin/env python3
"""Real particle/fire/projectile reset proof; session routing has its own gate."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SWIFT = r'''
import Foundation
import simd
@main struct WorldResetCheck {
 static var checks=0
 static func check(_ value:Bool,_ label:String){checks+=1;precondition(value,label)}
 static func main() throws {
  let data=try Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1]))
  let document=try JSONSerialization.jsonObject(with:data) as! [String:Any]
  let systems=document["systems"] as! [String:[String:Any]]
  let textures=Set(systems.values.flatMap{($0["emitters"] as! [[String:Any]]).compactMap{$0["texture"] as? String}})
  for hz in [15,30,60,120,144] {
   let particles=try NativeParticleEffects(data:data,textures:textures,random:{0.5})
   var anchor:NativeParticleEffects.Anchor?=NativeParticleEffects.Anchor(SIMD3(1,2,3))
   weak var retainedAnchor=anchor
   particles.spawn("gunflash",at:.zero,velocity:.zero,count:3,options:.init(anchor:anchor))
   particles.play("explosion_small",at:.zero)
   for _ in 0..<3 {particles.update(delta:1.0/Double(hz))}
   check(!particles.shown.isEmpty,"actual owner effects did not seed particles")
   anchor=nil
   check(retainedAnchor != nil,"anchor fixture failed to retain live particle ownership")
   particles.clear()
   check(particles.particles.count==1120 && particles.shown.isEmpty,"reset changed fixed pool size or retained particles")
   check(retainedAnchor==nil,"inactive particles retained previous world anchor")
   for p in particles.particles {
    check(!p.on && p.emitter==nil && p.anchor==nil && p.position == .zero,"old emitter/position survived reset")
   }
   for _ in 0..<hz*2 {particles.update(delta:1.0/Double(hz));check(particles.shown.isEmpty,"queued old playing effect restarted after reset")}
   check(particles.has("gunflash") && particles.has("explosion_small"),"reset discarded reusable original definitions")
   particles.spawn("gunflash",at:SIMD3(4,5,6),velocity:.zero,count:1)
   check(particles.shown.count==1 && particles.particles[0].on,"reset failed to rebase ordinary particle ring")
   particles.clear();particles.clear();check(particles.shown.isEmpty,"repeated reset not idempotent")

   let effects=NativeWeaponEffects()
   effects.receiveBlast(weapon:18,position:.zero,owner:"previous-peer")
   _=effects.lob(weapon:16,from:SIMD3(1,2,3),direction:SIMD3(1,0,0))
   effects.stream(weapon:37,from:.zero,direction:SIMD3(1,0,0),delta:0.2)
   effects.advance(delta:1.0/120)
   check(!effects.fires.isEmpty && !effects.projectiles.isEmpty && !effects.streams.isEmpty,"old world fixture incomplete")
   effects.clear()
   check(effects.fires.isEmpty && effects.projectiles.isEmpty && effects.streams.isEmpty,"old fire/projectile/stream survived clear")
   for _ in 0..<hz {effects.advance(delta:1.0/Double(hz))}
   check(effects.fires.isEmpty && effects.projectiles.isEmpty && effects.streams.isEmpty,"old effect replayed after clear")
   effects.clear();_=effects.launch(weapon:35,from:SIMD3(1,2,3),direction:SIMD3(1,0,0))
   let start=effects.projectiles[0].position
   effects.advance(delta:1.0/120)
   check(effects.projectiles[0].position==start,"old fractional simulation clock leaked across clear")
   effects.advance(delta:1.0/120)
   check(effects.projectiles[0].position != start,"fresh projectile failed to advance")
   effects.stream(weapon:37,from:.zero,direction:SIMD3(1,0,0),delta:0.1)
   check(abs(effects.streams[0].held-0.1)<0.000001,"old held stream clock leaked across clear")
  }
  print("PASS world effects reset: \(checks) actual particle/fire/projectile checks at15/30/60/120/144Hz; no old anchors, emissions, stream timers or fractional simulation clock")
 }
}
'''


def main():
    out = ROOT / 'local-only/native-physics/tests/world-reset'
    out.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='world-reset-', dir=out) as directory:
        work = Path(directory)
        (work / 'verify.swift').write_text(SWIFT)
        subprocess.run(['xcrun', 'swiftc', '-O', '-module-cache-path', str(out / 'modules'),
                        str(ROOT / 'ios/App/NativeParticleEffects.swift'), str(ROOT / 'ios/App/NativeWeaponEffects.swift'),
                        str(work / 'verify.swift'), '-o', str(work / 'verify')], check=True)
        result = subprocess.run([str(work / 'verify'), str(ROOT / 'local-only/site/game/world/fx.json')],
                                check=True, capture_output=True, text=True)
        (out / 'result.log').write_text(result.stdout)
        print(result.stdout, end='')


if __name__ == '__main__':
    main()
