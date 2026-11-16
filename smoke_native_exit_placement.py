#!/usr/bin/env python3
"""Archived exit-planner decisions against independent native candidate search."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
from smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parent
def main():
 out=ROOT/'local-only/native-physics/tests/exit-placement';out.mkdir(parents=True,exist_ok=True)
 paths=['ios/App/NativeGroundVehicle.swift','smoke_native_exit_placement.py','smoke_native_exit_placement.js','smoke_native_exit_placement.swift']
 before={p:(ROOT/p).read_bytes() for p in paths}
 with tempfile.TemporaryDirectory(prefix='snapshot-',dir=out) as temp:
  work=Path(temp);fixture=work/'reference.json'
  subprocess.run(['node',str(ROOT/'smoke_native_exit_placement.js'),str(fixture)],check=True)
  source='import Foundation\nimport simd\n'+function(before[paths[0]].decode(),'enum NativeVehicleExitPlanner {')+'\n'+before['smoke_native_exit_placement.swift'].decode()
  (work/'main.swift').write_text(source)
  result=subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(out/'modules'),str(work/'main.swift'),'-o',str(work/'verify')],capture_output=True,text=True)
  (out/'compile.log').write_text(result.stdout+result.stderr)
  if result.returncode: print(result.stdout+result.stderr);result.check_returncode()
  result=subprocess.run([str(work/'verify'),str(ROOT),str(fixture)],capture_output=True,text=True)
  unchanged=all((ROOT/p).read_bytes()==v for p,v in before.items())
  report={'status':'PASS' if result.returncode==0 and unchanged else 'FAIL','sourceUnchanged':unchanged,'sourceHashes':{p:hashlib.sha256(v).hexdigest() for p,v in before.items()},'output':result.stdout+result.stderr,'limits':['Actual archived planner with controlled query responses; imported geometry stays local','No retail runtime, actual native Rapier query integration, GPU scene or physical input acceptance in this gate']}
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
