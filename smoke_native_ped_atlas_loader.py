#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Real loader queue/task ownership with authored independent resource graphs."""
import hashlib,json,subprocess,tempfile
from pathlib import Path
from smoke_native_ped_atlas_support import family,write_family
ROOT=Path(__file__).resolve().parent

def main():
 out=ROOT/'local-only/research/ped-atlas-119/loader';out.mkdir(parents=True,exist_ok=True);work=Path(tempfile.mkdtemp(prefix='gate-',dir=out));files=work/'files';files.mkdir()
 (files/'fixtures.json').write_text(json.dumps([write_family(files,family(n,body=(128,256) if n.startswith('large') else (8,16))) for n in ['authored','largea','largeb']]))
 names=['WorldBinary','NativePedAtlasLayout','ServerAddress','NativePedAtlasLoader'];inputs={n:(ROOT/'ios/App'/f'{n}.swift').read_bytes() for n in names}
 tests=['smoke_native_ped_atlas_loader.py','smoke_native_ped_atlas_loader.swift','smoke_native_ped_atlas_support.py','smoke_native_ped_atlas_loader_server.js'];hashes={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in tests}
 sources=[]
 for n,data in inputs.items():p=work/f'{n}.swift';p.write_bytes(data);sources.append(str(p))
 (work/'main.swift').write_bytes((ROOT/'smoke_native_ped_atlas_loader.swift').read_bytes())
 cmd=['nice','-n','15','swiftc','-whole-module-optimization','-num-threads','1','-Onone','-swift-version','5','-module-cache-path',str(work/'modules'),*sources,str(work/'main.swift'),'-o',str(work/'verify')]
 c=subprocess.run(cmd,capture_output=True,text=True,timeout=180);(work/'compile.log').write_text(c.stdout+c.stderr)
 if c.returncode:print(c.stdout+c.stderr);c.check_returncode()
 peer=subprocess.Popen(['node',str(ROOT/'smoke_native_ped_atlas_loader_server.js'),str(files)],stdout=subprocess.PIPE,stderr=(work/'server.log').open('w'),text=True)
 try:
  port=json.loads(peer.stdout.readline())['port']
  result=subprocess.run([str(work/'verify'),str(files),'http://127.0.0.1:'+str(port)],capture_output=True,text=True,timeout=120)
 finally:
  peer.terminate()
  try:peer.wait(timeout=5)
  except subprocess.TimeoutExpired:peer.kill();peer.wait()
 unchanged=all((ROOT/'ios/App'/f'{n}.swift').read_bytes()==d for n,d in inputs.items()) and all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in hashes.items())
 report={'status':'PASS' if result.returncode==0 and unchanged else 'FAIL','output':result.stdout+result.stderr,'command':cmd,'sourceHashes':{n:hashlib.sha256(d).hexdigest() for n,d in inputs.items()},'testHashes':hashes,'sourceUnchanged':unchanged,'scope':'Actual Foundation queue/validation/task ownership with deterministic authored transfers AND actual production boundedURLSession to a disposable authored Node HTTP peer; no App/services/assets/GPU.'}
 (work/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out/'latest.json').write_text(json.dumps(report,indent=2)+'\n');print(result.stdout+result.stderr,end='');result.check_returncode();assert unchanged
if __name__=='__main__':main()
