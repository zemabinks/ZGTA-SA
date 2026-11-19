#!/usr/bin/env python3
"""Replay owner-supplied real-world Ball records; no game data is published."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib,json,platform,shutil,subprocess,sys,tempfile
ROOT=Path(__file__).resolve().parents[2]

def main():
    if len(sys.argv)!=2:raise SystemExit('Usage: python3 tests/movement/smoke_native_sphere_world.py OWNER_REFERENCE_DIRECTORY')
    reference=Path(sys.argv[1]).resolve()/'world-trimesh-reference.json'
    if not reference.is_file():raise SystemExit('Missing owner-provided world-trimesh-reference.json')
    output=ROOT/'local-only/native-physics/tests/sphere-world';output.mkdir(parents=True,exist_ok=True)
    previous=sys.dont_write_bytecode;sys.dont_write_bytecode=True
    from tests.movement.smoke_native_climb_runtime import function
    sys.dont_write_bytecode=previous
    method=function((ROOT/'ios/App/NativeGroundVehicle.swift').read_text(),'func installCell(')
    host='arm64' if platform.machine()=='arm64' else 'x86_64'
    library=ROOT/'local-only/native-physics'/f'macos-{host}'
    subprocess.run(['python3',str(ROOT/'native-physics/source_stamp.py'),'check',str(library)],check=True)
    with tempfile.TemporaryDirectory(prefix='run-',dir=output) as temporary:
        snapshot=Path(temporary);shutil.copyfile(reference,snapshot/reference.name)
        source=(ROOT/'native-physics/tests/sphere_world.swift').read_text().replace('// ACTUAL_INSTALL_CELL',method)
        (snapshot/'main.swift').write_text(source)
        names=['SwiftRapierWorld','NativeClimbController','NativeRapierClimbQueries','NativeHeadingContinuity','NativeFootLocomotion']
        for name in names:shutil.copyfile(ROOT/'ios/App'/f'{name}.swift',snapshot/f'{name}.swift')
        shutil.copytree(ROOT/'native-physics/include',snapshot/'include')
        command=['xcrun','swiftc','-parse-as-library','-whole-module-optimization','-Onone','-module-cache-path',str(output/'modules'),'-I',str(snapshot/'include')]
        command += [str(snapshot/f'{name}.swift') for name in names]+[str(snapshot/'main.swift'),'-L',str(library),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(snapshot/'verify')]
        subprocess.run(command,check=True);subprocess.run([str(snapshot/'verify'),str(ROOT),str(snapshot)],check=True)
        report=json.loads((snapshot/'world-trimesh-report.json').read_text())
        report['referenceSHA256']=hashlib.sha256(reference.read_bytes()).hexdigest()
        report['installCellSHA256']=hashlib.sha256(method.encode()).hexdigest()
        (output/'report.json').write_text(json.dumps(report,indent=2)+'\n')
if __name__=='__main__':main()
