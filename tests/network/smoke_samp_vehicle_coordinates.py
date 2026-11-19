#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Full-rotation protocol/model-origin boundary against actual native helpers."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,platform,subprocess,tempfile
from tests.movement.smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parents[2]
def main():
 out=ROOT/'local-only/research/vehicle-coordinates';out.mkdir(parents=True,exist_ok=True)
 names=['ios/App/SwiftRapierWorld.swift','ios/App/NativeSAMPVehicleCoordinates.swift','ios/App/NativeSAMPProtocol.swift','ios/App/NativeGroundVehicle.swift','tests/network/smoke_samp_vehicle_coordinates.py','tests/network/smoke_samp_vehicle_coordinates.swift']
 before={n:(ROOT/n).read_bytes()for n in names}
 with tempfile.TemporaryDirectory(dir=out,prefix='snapshot-')as tmp:
  work=Path(tmp);sources=[]
  for name in names[:3]:
   p=work/Path(name).name;p.write_bytes(before[name]);sources.append(str(p))
  source=before['ios/App/NativeGroundVehicle.swift'].decode()
  methods='\n'.join(function(source,m)for m in ['static func rotation(','static func modelOffset(','static func transform('])
  (work/'main.swift').write_text('import Foundation\nimport simd\nenum NativeGroundVehicle {\n'+methods+'\n}\n'+before['tests/network/smoke_samp_vehicle_coordinates.swift'].decode())
  built=subprocess.run(['xcrun','swiftc','-Onone','-module-cache-path','/private/tmp/zgtasa-core-swift-modules','-I',str(ROOT/'native-physics/include'),*sources,str(work/'main.swift'),'-L',str(ROOT/('local-only/native-physics/macos-'+platform.machine())),'-lzgtasa_native_physics','-framework','CoreFoundation','-framework','Security','-o',str(work/'verify')],capture_output=True,text=True)
  (out/'compile.log').write_text(built.stdout+built.stderr);built.check_returncode()
  run=subprocess.run([str(work/'verify'),str(ROOT)],capture_output=True,text=True);(out/'run.log').write_text(run.stdout+run.stderr)
  same=all((ROOT/n).read_bytes()==b for n,b in before.items());report={'status':'PASS'if run.returncode==0 and same else'FAIL','sourceUnchanged':same,'sourceHashes':{n:hashlib.sha256(b).hexdigest()for n,b in before.items()},'output':run.stdout+run.stderr,'limits':['Actual native rotation/model-offset/transform methods and original prepared model offsets; not a retail executable or actual network join','Protocol cache and actual server pose conversion are separate integration gates']};(out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(run.stdout+run.stderr,end='');run.check_returncode();assert same
if __name__=='__main__':main()
