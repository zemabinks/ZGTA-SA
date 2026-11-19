#!/usr/bin/env python3
"""Native legacy codecs against actual licensed Go RPC codecs and native poses."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,os,random,shutil,subprocess,tempfile
from tests.movement.smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parents[2]

def main():
 out=ROOT/'local-only/research/samp-protocol';out.mkdir(parents=True,exist_ok=True)
 names=['ios/App/NativeSAMPProtocol.swift','ios/App/NativeSAMPAddress.swift','ios/App/NativeUnattendedVehicle.swift','tests/network/smoke_native_samp_protocol.py','tests/network/smoke_native_samp_protocol.swift']
 names += [str(p.relative_to(ROOT))for p in (ROOT/'native-samp/internal/raknet').glob('*.go')]
 before={p:(ROOT/p).read_bytes()for p in names}
 with tempfile.TemporaryDirectory(prefix='verify-',dir=out)as temp:
  w=Path(temp);mod=w/'go';(mod/'internal').mkdir(parents=True);shutil.copytree(ROOT/'native-samp/internal/raknet',mod/'internal/raknet')
  (mod/'go.mod').write_text('module zgtasa.local/native-samp\n\ngo 1.26.4\n')
  rng=random.Random(101);cases=[]
  import base64
  for count in list(range(65))+[127,128,255,256,511,512,1023,4096]:
   for remainder in (0,1,3,7):
    length=max(0,count*8-remainder);payload=bytes(rng.randrange(256)for _ in range(count));cases.append({'id':rng.randrange(256),'payload':base64.b64encode(payload).decode(),'bits':length})
  (w/'input.json').write_text(json.dumps(cases))
  (mod/'main.go').write_text('''package main
import("encoding/json";"os";"zgtasa.local/native-samp/internal/raknet")
type C struct{ID uint8 `json:"id"`;Payload []byte `json:"payload"`;Bits int `json:"bits"`;Packet []byte `json:"packet"`}
func main(){var rows []C;b,e:=os.ReadFile(os.Args[1]);if e!=nil{panic(e)};if e=json.Unmarshal(b,&rows);e!=nil{panic(e)};for i:=range rows{rows[i].Packet=raknet.EncodeRPC(rows[i].ID,rows[i].Payload,rows[i].Bits)};b,e=json.Marshal(rows);if e!=nil{panic(e)};if e=os.WriteFile(os.Args[2],b,0600);e!=nil{panic(e)}}
''')
  env=dict(os.environ,GOCACHE=str(out/'go-cache'))
  subprocess.run(['go','run','.',str(w/'input.json'),str(w/'goldens.json')],cwd=mod,env=env,check=True,capture_output=True)
  reference=before['ios/App/NativeUnattendedVehicle.swift'].decode()
  source='import simd\n'+before['ios/App/NativeSAMPProtocol.swift'].decode()+'\n'+before['ios/App/NativeSAMPAddress.swift'].decode()+'\nenum Reference {\n'+function(reference,'    static func rotation(')+'\n'+function(reference,'    static func euler(')+'\n}\n'+before['tests/network/smoke_native_samp_protocol.swift'].decode()
  (w/'main.swift').write_text(source)
  p=subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(out/'modules'),str(w/'main.swift'),'-o',str(w/'verify')],capture_output=True,text=True);(out/'compile.log').write_text(p.stdout+p.stderr)
  if p.returncode:print(p.stdout+p.stderr);p.check_returncode()
  p=subprocess.run([str(w/'verify'),str(w/'goldens.json')],capture_output=True,text=True)
  same=all((ROOT/n).read_bytes()==v for n,v in before.items())
  report={'status':'PASS'if p.returncode==0 and same else'FAIL','sourceUnchanged':same,'sourceHashes':{n:hashlib.sha256(v).hexdigest()for n,v in before.items()},'rpcCases':len(cases),'output':p.stdout+p.stderr,'limits':['Wire codec and actual native rotation conversion; not full game/RPC/retail acceptance','Actual open.mp joins and rendered iOS scene tests recorded separately']}
  (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(p.stdout+p.stderr,end='');p.check_returncode();assert same
if __name__=='__main__':main()
