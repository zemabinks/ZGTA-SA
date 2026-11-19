#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Real native Rapier authored-COL lifecycle and parented-mesh regression.

Requires a freshly built, source-stamped Core102 native host library. Does not
build or change native platform libraries, target directories or owner assets.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess

ROOT=Path(__file__).resolve().parents[2]
OUT=ROOT/'local-only/research/runtime-collision-world'


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--library',type=Path,default=ROOT/'local-only/native-physics'/('macos-arm64'if platform.machine()=='arm64'else'macos-x86_64'))
    args=parser.parse_args();OUT.mkdir(parents=True,exist_ok=True)
    stamp=subprocess.run(['python3',str(ROOT/'native-physics/source_stamp.py'),'check',str(args.library)],cwd=ROOT)
    if stamp.returncode:raise SystemExit('Native library source stamp is stale; build the owned Core102 host library before this regression.')
    files=[ROOT/'ios/App'/n for n in['SwiftRapierWorld.swift','NativeRenderWareCollision.swift','NativeRenderWareCollisionWorld.swift']]
    inputs=files+[ROOT/'native-physics/src/lib.rs',ROOT/'native-physics/include/ZGTARapier.h']
    inputs+=list((ROOT/'local-only/site/game').glob('*.dff'))
    hashes={str(p):hashlib.sha256(p.read_bytes()).hexdigest()for p in inputs}
    binary=OUT/'world-tests'
    compile_=subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(OUT/'module-cache'),
        '-I',str(ROOT/'native-physics/include'),*map(str,files),str(ROOT/'tests/resources/smoke_native_renderware_collision_world.swift'),
        '-L',str(args.library),'-lzgtasa_native_physics','-framework','Security','-framework','CoreFoundation','-o',str(binary)],
        cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    (OUT/'build.log').write_text(compile_.stdout);assert compile_.returncode==0,compile_.stdout
    run=subprocess.run([str(binary),str(ROOT),str(OUT)],cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    (OUT/'run.log').write_text(run.stdout);assert run.returncode==0,run.stdout
    for path,digest in hashes.items():assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest,'test input modified: '+path
    report=json.loads((OUT/'report.json').read_text());report.update(sourceAndOwnerInputsUnchanged=True,sourceStampVerified=True)
    (OUT/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n');print(json.dumps(report,indent=2,sort_keys=True))


if __name__=='__main__':main()
