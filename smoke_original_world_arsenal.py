#!/usr/bin/env python3
"""Actual archived local arsenal and carried-total protocol regression."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
def main():
 out=ROOT/'local-only/research/original-world-arsenal';out.mkdir(parents=True,exist_ok=True)
 paths=['ios/App/NativeOriginalWorldArsenal.swift','smoke_original_world_arsenal.js','smoke_original_world_arsenal.swift','smoke_original_world_arsenal.py']
 before={p:(ROOT/p).read_bytes()for p in paths}
 subprocess.run(['node',str(ROOT/'smoke_original_world_arsenal.js'),str(out/'goldens.json')],check=True)
 with tempfile.TemporaryDirectory(dir=out,prefix='verify-')as temp:
  w=Path(temp);(w/'main.swift').write_bytes(before['smoke_original_world_arsenal.swift'])
  result=subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(out/'modules'),str(ROOT/'ios/App/NativeOriginalWorldArsenal.swift'),str(w/'main.swift'),'-o',str(w/'verify')],capture_output=True,text=True)
  (out/'compile.log').write_text(result.stdout+result.stderr)
  if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
  result=subprocess.run([str(w/'verify'),str(out/'goldens.json')],capture_output=True,text=True)
  same=all((ROOT/p).read_bytes()==v for p,v in before.items())
  report={'status':'PASS'if result.returncode==0 and same else'FAIL','sourceUnchanged':same,'sourceHashes':{p:hashlib.sha256(v).hexdigest()for p,v in before.items()},'output':result.stdout+result.stderr,'limits':['Actual owner-local browser arsenal and carried-total synchronizer with original injected weapon definitions','No original authenticated server or rendered scene/controller acceptance','Reload animation scheduling remains owned by existing native animator; this helper matches local rounds/timers and wire cadence','Malformed inputs are bounded; original unsafe inputs not reproduced']}
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert same
if __name__=='__main__':main()
