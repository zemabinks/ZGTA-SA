#!/usr/bin/env python3
"""Actual Foundation placement owner: parsing, barriers, commit and stale callback guards."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

# SPDX-License-Identifier: AGPL-3.0-only
from pathlib import Path
import hashlib,json,re,subprocess,tempfile
ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/research/native-placement-114'
def declaration(source,marker):
 start=source.index(marker);end=source.index('{',start)+1;depth=1
 while depth:
  depth+=(source[end]=='{')-(source[end]=='}');end+=1
 return source[start:end]
def main():
 OUT.mkdir(parents=True,exist_ok=True)
 paths=['ios/App/NativeMultiplayerClient.swift','tests/network/smoke_native_placement.py','tests/network/smoke_native_placement.swift']
 inputs={name:(ROOT/name).read_bytes()for name in paths}
 session=declaration(inputs[paths[0]].decode(),'struct NativePlacementSession {')
 with tempfile.TemporaryDirectory(prefix='pure-',dir=OUT)as directory:
  work=Path(directory);source=inputs[paths[2]].decode().replace('// PLACEMENT_SESSION',session).replace('// SEAT_SESSION',declaration(inputs[paths[0]].decode(),'struct NativeVehicleSeatSession {'))
  (work/'main.swift').write_text(source)
  compiled=subprocess.run(['xcrun','swiftc','-parse-as-library','-module-cache-path',str(OUT/'modules'),str(work/'main.swift'),'-o',str(work/'pure')],capture_output=True,text=True)
  (OUT/'pure-compile.log').write_text(compiled.stdout+compiled.stderr)
  if compiled.returncode:print(compiled.stdout+compiled.stderr);compiled.check_returncode()
  run=subprocess.run([str(work/'pure')],capture_output=True,text=True)
  output=run.stdout+run.stderr;(OUT/'pure-runtime.log').write_text(output)
  checks=re.search(r'PASS placement session: (\d+) checks',output)
  report={'status':'PASS'if run.returncode==0 else'FAIL','checks':int(checks[1])if checks else None,
   'sourceHashes':{name:hashlib.sha256(value).hexdigest()for name,value in inputs.items()},
   'liveInputsMatchSnapshot':all((ROOT/name).read_bytes()==value for name,value in inputs.items()),
   'limits':['Executes the actual extracted Foundation owner with authored messages; no App or physical runtime.',
             'URLSession/callback integration is a separate focused gate.']}
  if 'DRAFT_SAME_PEER_RESET_ALIAS prior=1 replacement=1 delayedOldAccepted=true' in output:
   (OUT/'draft-same-peer-reset-negative.json').write_text(json.dumps({
    'status':'DRAFT_ALIAS_REPRODUCED','classification':'Initial114 adapter draft misuse; not historical113 behavior',
    'method':'Execute the actual seat owner, full reset on the same peer, new request, delayed old positive ACK',
    'priorRequest':1,'replacementRequest':1,'delayedOldAccepted':True,
    'productionRepair':'clearOccupancy preserves issued counter for TP; full reset remains for a new connection',
    'NativeMultiplayerClientSHA256':report['sourceHashes']['ios/App/NativeMultiplayerClient.swift']},indent=2)+'\n')
  (OUT/'pure-report.json').write_text(json.dumps(report,indent=2)+'\n');print(output,end='');run.check_returncode()
if __name__=='__main__':main()
