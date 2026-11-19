#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
def main():
 out=ROOT/'local-only/research/samp-input';out.mkdir(parents=True,exist_ok=True)
 names=['ios/App/NativeSAMPInput.swift','ios/App/NativeSAMPProtocol.swift','tests/network/smoke_samp_input.swift','tests/network/smoke_samp_input.py'];before={n:(ROOT/n).read_bytes()for n in names}
 with tempfile.TemporaryDirectory(dir=out,prefix='snapshot-')as temp:
  work=Path(temp)
  for name in names[:2]:(work/Path(name).name).write_bytes(before[name])
  (work/'main.swift').write_bytes(before['tests/network/smoke_samp_input.swift'])
  result=subprocess.run(['xcrun','swiftc','-Onone','-module-cache-path','/private/tmp/zgtasa-core-swift-modules',str(work/'NativeSAMPInput.swift'),str(work/'NativeSAMPProtocol.swift'),str(work/'main.swift'),'-o',str(work/'verify')],capture_output=True,text=True)
  (out/'compile.log').write_text(result.stdout+result.stderr)
  if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
  result=subprocess.run([str(work/'verify')],capture_output=True,text=True);unchanged=all((ROOT/n).read_bytes()==data for n,data in before.items())
  (out/'report.json').write_text(json.dumps({'status':'PASS'if result.returncode==0 and unchanged else'FAIL','sourceUnchanged':unchanged,'hashes':{n:hashlib.sha256(data).hexdigest()for n,data in before.items()},'output':result.stdout+result.stderr,'limits':['Published key/wire layouts and native semantic mapping; actual hardware, adapter and owned-server callbacks are separate gates']},indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
