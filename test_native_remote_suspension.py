#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Portable authored geometry tests; never loads/executes original browser code."""
from pathlib import Path
import hashlib,json,platform,subprocess
from smoke_native_climb_runtime import function
ROOT=Path(__file__).resolve().parent
OUT=ROOT/'local-only/research/remote-suspension-108/portable'
def main():
    OUT.mkdir(parents=True,exist_ok=True)
    renderer=(ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
    ground=(ROOT/'ios/App/NativeGroundVehicle.swift').read_text()
    fixture=(ROOT/'test_native_remote_suspension.swift').read_text().replace('// ACTUAL_CONTACT_METHOD',function(renderer,'    private func remoteSuspensionContact(')).replace('// ACTUAL_TRANSFORM_METHOD',function(ground,'    static func transform(position:'))
    (OUT/'main.swift').write_text(fixture)
    paths=[ROOT/'ios/App'/(n+'.swift') for n in ['NativeRemoteSuspension','NativeWorldRay','SwiftRapierWorld']]
    guarded=paths+[ROOT/'ios/App/NativeWorldRenderer.swift',ROOT/'ios/App/NativeGroundVehicle.swift',ROOT/'test_native_remote_suspension.swift',Path(__file__)]
    hashes={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()for p in guarded}
    with(OUT/'compile.log').open('w')as log:
        subprocess.run(['xcrun','swiftc','-Onone','-module-cache-path',str(OUT/'modules'),'-I',str(ROOT/'native-physics/include'),*[str(p)for p in paths],str(OUT/'main.swift'),'-L',str(ROOT/f'local-only/native-physics/macos-{platform.machine()}'),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(OUT/'native-tests')],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True,timeout=180)
    with(OUT/'runtime.log').open('w')as log:
        subprocess.run([str(OUT/'native-tests')],stdout=log,stderr=subprocess.STDOUT,check=True,timeout=60)
    after={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()for p in guarded}
    report={'status':'PASS'if hashes==after else'INVALIDATED','sourceUnchanged':hashes==after,'scope':'Authored synthetic geometry and independent contact conditions, actual native helper/Renderer contact/Rapier; no original game input','hashes':hashes,'result':(OUT/'runtime.log').read_text().strip()}
    (OUT/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(json.dumps(report));assert hashes==after
if __name__=='__main__':main()
