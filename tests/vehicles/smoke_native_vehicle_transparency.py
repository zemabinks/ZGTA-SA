#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Authored material/sort/actual encoder regression; no assets, GPU or UI needed."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import hashlib,json,subprocess,time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]

def block(s,marker):
 a=s.index(marker);b=s.index('{',a);level=1;c=b+1
 while level:level+=(s[c]=='{')-(s[c]=='}');c+=1
 return s[a:c]
def main():
 out=ROOT/'local-only/research/vehicle-transparency-110'/str(time.time_ns());out.mkdir(parents=True)
 names=['NativeVehicleRig.swift','NativeVehiclePaint.swift'];files=[ROOT/'ios/App'/p for p in names]+[ROOT/'ios/App/NativeWorldRenderer.swift',ROOT/'tests/vehicles/smoke_native_vehicle_transparency.swift',Path(__file__)]
 before={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()for p in files}
 renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text();source=(ROOT/'tests/vehicles/smoke_native_vehicle_transparency.swift').read_text().replace('// ACTUAL_UNIFORMS',block(renderer,'    private struct Uniforms {')).replace('// ACTUAL_ENCODER',block(renderer,'    private func encodeTransparentVehicles('))
 assert 'let frame=completeFrame.opaque'in renderer and 'for part in completeFrame.transparent {'in renderer
 assert renderer.index('encodeTransparentVehicles(transparentVehicleDraws,encoder:encoder)')>renderer.index('let heldWeapon = NativeWeaponAttachment.selectedWeapon')
 paths=[]
 for n in names:p=out/n;p.write_bytes((ROOT/'ios/App'/n).read_bytes());paths.append(p)
 mainfile=out/'main.swift';mainfile.write_text(source)
 with(out/'compile.log').open('w')as log:subprocess.run(['xcrun','swiftc','-parse-as-library','-j','1','-num-threads','1','-whole-module-optimization','-Onone','-module-cache-path',str(out/'modules'),*map(str,paths),str(mainfile),'-o',str(out/'verify')],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=600)
 result=subprocess.run([str(out/'verify')],capture_output=True,text=True,check=True,timeout=30);(out/'runtime.log').write_text(result.stdout+result.stderr)
 assert all(hashlib.sha256((ROOT/p).read_bytes()).hexdigest()==sha for p,sha in before.items())
 report={'status':'PASS','sourceUnchanged':True,'sourceHashes':before,'output':result.stdout.strip(),'originalDataUsed':False,'runtimeGPUOrUIUsed':False}
 (out/'report.json').write_text(json.dumps(report,indent=2)+'\n');print(json.dumps(report,indent=2))
if __name__=='__main__':main()
