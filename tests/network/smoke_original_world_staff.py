#!/usr/bin/env python3
"""Actual archived onStaff and shared production inventory ownership regression."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
def main():
 out=ROOT/'local-only/research/original-world-staff';out.mkdir(parents=True,exist_ok=True)
 names=['ServerAddress','NativeInventoryPrediction','NativeOriginalWorldArsenal','NativeWeaponState']
 paths=['ios/App/'+n+'.swift'for n in names]+['tests/network/smoke_original_world_staff.py','tests/network/smoke_original_world_staff.js','tests/network/smoke_original_world_staff.swift']
 before={p:(ROOT/p).read_bytes()for p in paths}
 subprocess.run(['node',str(ROOT/'tests/network/smoke_original_world_staff.js'),str(out/'goldens.json')],check=True)
 with tempfile.TemporaryDirectory(dir=out,prefix='verify-')as temp:
  w=Path(temp);(w/'main.swift').write_bytes(before['tests/network/smoke_original_world_staff.swift'])
  result=subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(out/'modules'),*[str(ROOT/'ios/App'/(n+'.swift'))for n in names],str(w/'main.swift'),'-o',str(w/'verify')],capture_output=True,text=True)
  (out/'compile.log').write_text(result.stdout+result.stderr)
  if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
  result=subprocess.run([str(w/'verify'),str(out/'goldens.json')],capture_output=True,text=True)
  same=all((ROOT/p).read_bytes()==v for p,v in before.items())
  report={'status':'PASS'if result.returncode==0 and same else'FAIL','sourceUnchanged':same,'sourceHashes':{p:hashlib.sha256(v).hexdigest()for p,v in before.items()},'output':result.stdout+result.stderr,'limits':['Actual owner-local archived onStaff callback, arsenal and carried-state synchronizer executed offline','Actual shared NativeWeaponState source, including default/legacy policy isolation and asynchronous metadata FIFO','No authenticated service join or rendered gameplay claim','Only weapon fields tested; health, freeze, skin and respawn belong to their separate owners','Malformed arm lists are bounded to128 entries']}
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert same
if __name__=='__main__':main()
