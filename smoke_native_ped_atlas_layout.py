#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Pure actual family/layout parser with independently authored resource bytes."""
import hashlib,json,subprocess,tempfile
from pathlib import Path
from smoke_native_ped_atlas_support import family,write_family
ROOT=Path(__file__).resolve().parent

def main():
 out=ROOT/'local-only/research/ped-atlas-119/layout';out.mkdir(parents=True,exist_ok=True)
 work=Path(tempfile.mkdtemp(prefix='gate-',dir=out));fixtures=work/'files';fixtures.mkdir()
 cases=[family('vertical'),family('horizontal',body=(16,8)),family('mixed',mixed=True),family('untextured',body=(1,1),txd=False)]
 (fixtures/'fixtures.json').write_text(json.dumps([write_family(fixtures,x) for x in cases]))
 names=['WorldBinary','NativePedAtlasLayout','ServerAddress','NativePedAtlasLoader'];inputs={n:(ROOT/'ios/App'/f'{n}.swift').read_bytes() for n in names}
 test_names=['smoke_native_ped_atlas_layout.py','smoke_native_ped_atlas_layout.swift','smoke_native_ped_atlas_support.py']
 test_hashes={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in test_names}
 sources=[]
 for n,data in inputs.items():p=work/f'{n}.swift';p.write_bytes(data);sources.append(str(p))
 (work/'main.swift').write_bytes((ROOT/'smoke_native_ped_atlas_layout.swift').read_bytes())
 command=['nice','-n','15','swiftc','-whole-module-optimization','-num-threads','1','-Onone','-swift-version','5','-module-cache-path',str(work/'modules'),*sources,str(work/'main.swift'),'-o',str(work/'verify')]
 result=subprocess.run(command,capture_output=True,text=True,timeout=180);(work/'compile.log').write_text(result.stdout+result.stderr)
 if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
 run=subprocess.run([str(work/'verify'),str(fixtures)],capture_output=True,text=True,timeout=30)
 unchanged=all((ROOT/'ios/App'/f'{n}.swift').read_bytes()==data for n,data in inputs.items()) and all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in test_hashes.items())
 report={'status':'PASS' if run.returncode==0 and unchanged else 'FAIL','output':run.stdout+run.stderr,'sourceHashes':{n:hashlib.sha256(d).hexdigest() for n,d in inputs.items()},'testHashes':test_hashes,'sourceUnchanged':unchanged,'command':command,'originalDataUsed':False}
 (work/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out/'latest.json').write_text(json.dumps(report,indent=2)+'\n');print(run.stdout+run.stderr,end='');run.check_returncode();assert unchanged
if __name__=='__main__':main()
