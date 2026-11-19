#!/usr/bin/env python3
"""Actual GameVC original-world dispatch/exit handoff with explicit UI carriers."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,subprocess,tempfile
from tests.movement.smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parents[2]
def main():
 out=ROOT/'local-only/research/original-gameplay';out.mkdir(parents=True,exist_ok=True)
 names=['NativeOriginalWorldCommands','NativeOriginalWorldVitals','NativeOriginalWorldEffects']
 paths=[f'ios/App/{name}.swift'for name in names]+['ios/App/NativeGameViewController.swift','tests/network/smoke_native_original_gameplay.py','tests/network/smoke_native_original_gameplay.swift']
 before={name:(ROOT/name).read_bytes()for name in paths};controller=before['ios/App/NativeGameViewController.swift'].decode()
 methods='\n'.join(function(controller,marker)for marker in ['    private func receiveOriginalHit(','    private func processOriginalFatal(','    private func originalStaffKill(','    private func leaveForOriginalTeleport(','    private func receiveOriginalEvent(','    private func stepOriginalGameplay('])
 source=before['tests/network/smoke_native_original_gameplay.swift'].decode().replace('// ACTUAL_METHODS',methods)
 with tempfile.TemporaryDirectory(dir=out,prefix='snapshot-')as temporary:
  work=Path(temporary);sources=[]
  for name in names:
   path=work/(name+'.swift');path.write_bytes(before[f'ios/App/{name}.swift']);sources.append(str(path))
  (work/'main.swift').write_text(source);sources.append(str(work/'main.swift'))
  result=subprocess.run(['xcrun','swiftc','-whole-module-optimization','-Onone','-num-threads','1','-module-cache-path',str(out/'modules'),*sources,'-o',str(work/'verify')],capture_output=True,text=True,timeout=900)
  (out/'compile.log').write_text(result.stdout+result.stderr)
  if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
  result=subprocess.run([str(work/'verify')],capture_output=True,text=True);same=all((ROOT/name).read_bytes()==data for name,data in before.items())
  report={'status':'PASS'if result.returncode==0 and same else'FAIL','sourceUnchanged':same,'sourceHashes':{name:hashlib.sha256(data).hexdigest()for name,data in before.items()},'output':result.stdout+result.stderr,'limits':['Actual extracted six GameVC methods with real fractional vitals, effect timers and typed command decoding','Network/UI/arsenal/renderer adapters are explicit carriers; real WebSocket, physical placement and arsenal FIFO have separate gates','No authenticated original-site join, rendered device acceptance or retail1:1 claim']}
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert same
if __name__=='__main__':main()
