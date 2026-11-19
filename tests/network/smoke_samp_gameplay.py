#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Official command layouts and actual Client/adapter/NMP authority callbacks."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,platform,subprocess,tempfile
from tests.network.smoke_samp_controls import NAMES
ROOT=Path(__file__).resolve().parents[2]
def main():
 out=ROOT/'local-only/research/samp-gameplay';out.mkdir(parents=True,exist_ok=True)
 paths=[f'ios/App/{n}.swift'for n in NAMES]+['ios/App/NativeActorAnimation.swift','tests/network/smoke_samp_gameplay.py','tests/network/smoke_samp_gameplay.swift']
 before={p:(ROOT/p).read_bytes()for p in paths}
 with tempfile.TemporaryDirectory(dir=out,prefix='snapshot-')as tmp:
  work=Path(tmp);sources=[]
  for n in NAMES:
   data=before[f'ios/App/{n}.swift'].decode()
   if n=='NativeSAMPClient':
    marker='    private func receive(_ data:Data)throws{';assert data.count(marker)==1;data=data.replace(marker,'    func receive(_ data:Data)throws{',1)
   p=work/(n+'.swift');p.write_text(data);sources.append(str(p))
  actor=before['ios/App/NativeActorAnimation.swift'].decode();motion=actor[actor.index('struct NativePedestrianMotion {'):actor.index('struct NativeWeaponAnimation {')]
  (work/'PedestrianMotion.swift').write_text('import Foundation\nimport simd\n'+motion);sources.append(str(work/'PedestrianMotion.swift'))
  (work/'main.swift').write_bytes(before['tests/network/smoke_samp_gameplay.swift'])
  result=subprocess.run(['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),'-I',str(ROOT/'native-samp/include'),*sources,str(work/'main.swift'),'-L',str(ROOT/('local-only/native-samp/macos-'+platform.machine())),'-lzgtasa_samp','-lresolv','-framework','CoreFoundation','-framework','Security','-o',str(work/'verify')],capture_output=True,text=True,timeout=240)
  (out/'compile.log').write_text(result.stdout+result.stderr)
  if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
  result=subprocess.run([str(work/'verify')],capture_output=True,text=True);same=all((ROOT/p).read_bytes()==b for p,b in before.items())
  report={'status':'PASS'if result.returncode==0 and same else'FAIL','sourceUnchanged':same,'sourceHashes':{p:hashlib.sha256(b).hexdigest()for p,b in before.items()},'output':result.stdout+result.stderr,'primaryReference':'https://github.com/openmultiplayer/open.mp/blob/2b4a69dd606dc2f93e98b0f1ffe8801cc01633f5/Shared/NetCode/core.hpp','testVisibilityChange':'Private receive becomes internal only in isolated compiled snapshot; no behavior replaced','limits':['Direct command field/bit goldens and actual native authority callback ownership; no live join or rendered camera claim','Actual server freeze/camera/spectator operations have separate owned-server fixture; native rendered interpolation curve is not retail verified']}
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert same
if __name__=='__main__':main()
