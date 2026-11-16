#!/usr/bin/env python3
"""Original-service protocol helper vs actual owner-local archived decoder."""
from pathlib import Path
import hashlib,json,subprocess,tempfile
ROOT=Path(__file__).resolve().parent
def main():
 out=ROOT/'local-only/research/original-world-protocol';out.mkdir(parents=True,exist_ok=True)
 paths=['ios/App/NativeOriginalWorldProtocol.swift','smoke_original_world_protocol.js','smoke_original_world_protocol.swift','smoke_original_world_protocol.py']
 before={p:(ROOT/p).read_bytes()for p in paths}
 subprocess.run(['node',str(ROOT/'smoke_original_world_protocol.js'),str(out/'goldens.json')],check=True)
 with tempfile.TemporaryDirectory(dir=out,prefix='verify-')as temp:
  w=Path(temp);(w/'main.swift').write_bytes(before['smoke_original_world_protocol.swift'])
  result=subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(out/'modules'),str(ROOT/'ios/App/NativeOriginalWorldProtocol.swift'),str(w/'main.swift'),'-o',str(w/'verify')],capture_output=True,text=True)
  (out/'compile.log').write_text(result.stdout+result.stderr)
  if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
  result=subprocess.run([str(w/'verify'),str(out/'goldens.json')],capture_output=True,text=True)
  same=all((ROOT/p).read_bytes()==v for p,v in before.items())
  report={'status':'PASS'if result.returncode==0 and same else'FAIL','sourceUnchanged':same,'sourceHashes':{p:hashlib.sha256(v).hexdigest()for p,v in before.items()},'output':result.stdout+result.stderr,'limits':['Actual archived protocol38 byte-decoder golden; no current authenticated server session','Player rows and shot records implemented; traffic/pedestrian/extension records surfaced as typed bytes for separate adapters','Explicit original-site app login still required; no other app session credentials read','Malformed records discarded atomically; limits intentionally stricter than archived unsafe DataView reads']}
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert same
if __name__=='__main__':main()
