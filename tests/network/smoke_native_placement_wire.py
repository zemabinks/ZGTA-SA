#!/usr/bin/env python3
"""Actual URLSession placement negotiation, all me producers and callback ownership."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

# SPDX-License-Identifier: AGPL-3.0-only
from pathlib import Path
import hashlib,json,re,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/research/native-placement-114'
NAMES=['NativeConnectionRecovery','ServerAddress','NativeInventoryPrediction','NativeShotTargeting','NativeStreamShotClaims','NativeOriginalWorldProtocol','NativeOriginalWorldCommands','NativeOriginalWorldVitals','NativeSAMPProtocol','NativeSAMPGameplayCommands','NativeSAMPLocalVitals','NativeAmbientPedestrianProtocol','NativeAmbientTrafficProtocol','NativeOrdinaryShot','NativeLocalShots','NativeLocalShotPackets','NativeMultiplayerClient']
def main():
 OUT.mkdir(parents=True,exist_ok=True)
 paths=[f'ios/App/{n}.swift'for n in NAMES]+['ios/App/NativeActorAnimation.swift','tests/network/smoke_native_placement_wire.py','tests/network/smoke_native_placement_wire.js','tests/network/smoke_native_placement_wire.swift']
 inputs={name:(ROOT/name).read_bytes()for name in paths}
 with tempfile.TemporaryDirectory(prefix='wire-',dir=OUT)as directory:
  work=Path(directory);actor=inputs['ios/App/NativeActorAnimation.swift'].decode();actor=actor[actor.index('struct NativePedestrianMotion {'):actor.index('struct NativeWeaponAnimation {')]
  source='\n'.join(inputs[f'ios/App/{n}.swift'].decode()for n in NAMES)+'\n'+actor+'\n'+inputs[paths[-1]].decode()
  (work/'main.swift').write_text(source)
  compiled=subprocess.run(['xcrun','swiftc','-module-cache-path',str(OUT/'modules'),str(work/'main.swift'),'-o',str(work/'client')],capture_output=True,text=True)
  (OUT/'wire-compile.log').write_text(compiled.stdout+compiled.stderr)
  if compiled.returncode:print(compiled.stdout+compiled.stderr);compiled.check_returncode()
  (work/'peer.js').write_bytes(inputs['tests/network/smoke_native_placement_wire.js'])
  run=subprocess.run(['node',str(work/'peer.js'),str(work/'client')],capture_output=True,text=True,timeout=65)
  output=run.stdout+run.stderr;(OUT/'wire-runtime.log').write_text(output)
  checks=re.search(r'PASS actual NativeMP placement wire: (\d+) checks',output)
  report={'status':'PASS'if run.returncode==0 else'FAIL','checks':int(checks[1])if checks else None,
   'sourceHashes':{name:hashlib.sha256(value).hexdigest()for name,value in inputs.items()},
   'liveInputsMatchSnapshot':all((ROOT/name).read_bytes()==value for name,value in inputs.items()),
   'limits':['Real Foundation URLSession with a disposable authored protocol peer, not the production backend authority.',
             'Callbacks intentionally attempt production sendPosition/sendExit/passenger methods during placement; no UIKit or physical runtime.',
             'Same-file test extension invokes actual private parser/send boundaries for stale transport and forged producer controls.',
             'GVC/Renderer cleanup and real backend persistence are separate gates; no physical Home/foreground acceptance.']}
  (OUT/'wire-report.json').write_text(json.dumps(report,indent=2)+'\n');print(output,end='');run.check_returncode()
if __name__=='__main__':main()
