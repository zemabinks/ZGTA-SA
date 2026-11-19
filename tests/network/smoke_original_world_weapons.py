#!/usr/bin/env python3
"""Actual NativeWeaponState policy isolation and original owner handoffs."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
def main():
 out=ROOT/'local-only/research/original-world-weapons';out.mkdir(parents=True,exist_ok=True)
 names=['ServerAddress','NativeInventoryPrediction','NativeOriginalWorldArsenal','NativeWeaponState']
 paths=['ios/App/'+n+'.swift'for n in names]+['tests/network/smoke_original_world_weapons.py','tests/network/smoke_original_world_weapons.swift']
 before={p:(ROOT/p).read_bytes()for p in paths}
 with tempfile.TemporaryDirectory(dir=out,prefix='verify-')as temp:
  w=Path(temp);(w/'main.swift').write_bytes(before['tests/network/smoke_original_world_weapons.swift'])
  result=subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(out/'modules'),*[str(ROOT/'ios/App'/ (n+'.swift'))for n in names],str(w/'main.swift'),'-o',str(w/'verify')],capture_output=True,text=True)
  (out/'compile.log').write_text(result.stdout+result.stderr)
  if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
  result=subprocess.run([str(w/'verify')],capture_output=True,text=True)
  same=all((ROOT/p).read_bytes()==v for p,v in before.items())
  report={'status':'PASS'if result.returncode==0 and same else'FAIL','sourceUnchanged':same,'sourceHashes':{p:hashlib.sha256(v).hexdigest()for p,v in before.items()},'output':result.stdout+result.stderr,'limits':['Actual shared NativeWeaponState production sources','Controlled original message inputs and clock; no authenticated live service gameplay claim','Independent ACK path remains strict; no fabricated nonce or revision']}
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert same
if __name__=='__main__':main()
