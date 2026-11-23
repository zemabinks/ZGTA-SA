#!/usr/bin/env python3
"""Actual GameVC constructor, muzzle/emit, reload and cycle policy dispatch."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,subprocess,tempfile
from tests.movement.smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parents[2]
NAMES=['ServerAddress','NativeInventoryPrediction','NativeOriginalWorldArsenal','NativeWeaponState','NativeWeaponShotDelivery','NativeShotTargeting','NativeStreamShotClaims','NativeGameBindings','NativeAmbientPedestrianProtocol','NativeAmbientTrafficProtocol','NativeOrdinaryShot','NativeLocalShots']
def main():
 out=ROOT/'local-only/research/original-controller';out.mkdir(parents=True,exist_ok=True)
 paths=['ios/App/'+n+'.swift'for n in NAMES]+['ios/App/NativeGameViewController.swift','ios/App/NativeWorldRenderer.swift','ios/App/NativeActorAnimation.swift','tests/ui/smoke_native_original_controller.py','tests/ui/smoke_native_original_controller.swift']
 before={p:(ROOT/p).read_bytes()for p in paths};vc=before['ios/App/NativeGameViewController.swift'].decode();actor=before['ios/App/NativeActorAnimation.swift'].decode()
 constructor=function(vc,'    init(server: ServerAddress, settings:')
 methods='\n'.join(function(vc,m).replace('@objc ','').replace('private ','')for m in ['    private struct CapturedWeaponShot {','    private func consumeFootWeaponShot(','    private func currentShotRay(','    private func emitWeaponShot(','    @objc private func reload()','    private func cycleWeapon(','    private func sendWeaponSelection('])
 animation=function(actor,'struct NativeWeaponAnimation {')
 admission=(function(before['ios/App/NativeWorldRenderer.swift'].decode(),'var nonPassiveRemotePlayers:')+'\n'+function(before['ios/App/NativeWorldRenderer.swift'].decode(),'var livingRemotePlayers:')).replace('[RemotePlayer]','[HarnessPlayer]')
 harness=before['tests/ui/smoke_native_original_controller.swift'].decode().replace('// ACTUAL_CONSTRUCTOR',constructor).replace('// ACTUAL_METHODS',methods).replace('// ACTUAL_PASSIVE_ADMISSION',admission).replace('&&!',' && !')
 with tempfile.TemporaryDirectory(dir=out,prefix='verify-')as temp:
  w=Path(temp);(w/'main.swift').write_text('\n'.join(before['ios/App/'+n+'.swift'].decode()for n in NAMES)+'\n'+animation+'\n'+harness)
  result=subprocess.run(['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-O','-module-cache-path',str(out/'modules'),str(w/'main.swift'),'-o',str(w/'verify')],capture_output=True,text=True)
  (out/'compile.log').write_text(result.stdout+result.stderr)
  if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
  result=subprocess.run([str(w/'verify')],capture_output=True,text=True)
  same=all((ROOT/p).read_bytes()==v for p,v in before.items())
  report={'status':'PASS'if result.returncode==0 and same else'FAIL','sourceUnchanged':same,'sourceHashes':{p:hashlib.sha256(v).hexdigest()for p,v in before.items()},'output':result.stdout+result.stderr,'limits':['Actual GameVC constructor and six gameplay methods plus actual inventory/prediction/shot-delivery/ray/bindings sources','Renderer, button, audio, gameplay HTTP and network objects are explicit carriers; real URLSession original/default wire acceptance is separate','One-slot source behavior and guard matrix, not UIKit/device/controller or original-live-service gameplay verification']}
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert same
if __name__=='__main__':main()
