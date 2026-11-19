#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Pure actual family/layout parser with independently authored resource bytes."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import hashlib,json,subprocess,tempfile
from pathlib import Path
from tests.resources.smoke_native_ped_atlas_support import family,write_family
ROOT=Path(__file__).resolve().parents[2]

def main():
 out=ROOT/'local-only/research/ped-atlas-120/layout';out.mkdir(parents=True,exist_ok=True)
 work=Path(tempfile.mkdtemp(prefix='gate-',dir=out));fixtures=work/'files';fixtures.mkdir()
 cases=[family('vertical'),family('horizontal',body=(16,8)),family('mixed',mixed=True),family('untextured',body=(1,1),txd=False)]
 cases += [family('v2mixed',mixed=True,version=2),family('v2untextured',txd=False,version=2)]
 cases += [family('v2size'+str(w)+'x'+str(h),body=(w,h),version=2,filters=(f,)) for w,h in [(64,64),(128,64),(64,128),(128,128),(128,256),(256,128)] for f in [1,2,6]]
 (fixtures/'fixtures.json').write_text(json.dumps([write_family(fixtures,x) for x in cases]))
 names=['WorldBinary','NativePedAtlasLayout','ServerAddress','NativePedAtlasLoader'];inputs={n:(ROOT/'ios/App'/f'{n}.swift').read_bytes() for n in names}
 test_names=['tests/resources/smoke_native_ped_atlas_layout.py','tests/resources/smoke_native_ped_atlas_layout.swift','tests/resources/smoke_native_ped_atlas_support.py']
 test_hashes={n:hashlib.sha256((ROOT/n).read_bytes()).hexdigest() for n in test_names}
 sources=[]
 for n,data in inputs.items():p=work/f'{n}.swift';p.write_bytes(data);sources.append(str(p))
 (work/'main.swift').write_bytes((ROOT/'tests/resources/smoke_native_ped_atlas_layout.swift').read_bytes())
 command=['nice','-n','15','swiftc','-whole-module-optimization','-num-threads','1','-Onone','-swift-version','5','-module-cache-path',str(work/'modules'),*sources,str(work/'main.swift'),'-o',str(work/'verify')]
 result=subprocess.run(command,capture_output=True,text=True,timeout=180);(work/'compile.log').write_text(result.stdout+result.stderr)
 if result.returncode:print(result.stdout+result.stderr);result.check_returncode()
 run=subprocess.run([str(work/'verify'),str(fixtures)],capture_output=True,text=True,timeout=30)
 unchanged=all((ROOT/'ios/App'/f'{n}.swift').read_bytes()==data for n,data in inputs.items()) and all(hashlib.sha256((ROOT/n).read_bytes()).hexdigest()==h for n,h in test_hashes.items())
 report={'status':'PASS' if run.returncode==0 and unchanged else 'FAIL','output':run.stdout+run.stderr,'sourceHashes':{n:hashlib.sha256(d).hexdigest() for n,d in inputs.items()},'testHashes':test_hashes,'sourceUnchanged':unchanged,'command':command,'originalDataUsed':False}
 (work/'report.json').write_text(json.dumps(report,indent=2)+'\n');(out/'latest.json').write_text(json.dumps(report,indent=2)+'\n');print(run.stdout+run.stderr,end='');run.check_returncode();assert unchanged
if __name__=='__main__':main()
