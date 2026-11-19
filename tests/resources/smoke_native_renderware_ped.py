#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Compile the real actor/animation sources and test native custom-ped rendering.

Reads owner-local DFF/TXD/CLP1/SKN1 only. Fixtures, GPU readbacks and executables
stay under local-only/research/runtime-ped. The actual Renderer is not modified.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

import argparse
import hashlib
import json
from pathlib import Path
import re
import subprocess

from tests.resources.smoke_native_renderware_skeleton import fixture

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'local-only/research/runtime-ped'
SOURCES = ['NativeRenderWareDFF','NativeRenderWareTXD','NativeRenderWareModel','NativeRenderWareSkeleton',
           'NativeRenderWarePedModel','NativeActorAnimation','NativeFootAnimation','NativeGunAnimation',
           'NativeFlightAnimation','NativeSwimAnimation','NativeRiderAnimation','NativeSkeletalActor']


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--extra-model',action='append',default=[])
    parser.add_argument('--extra-skeleton-root',type=Path)
    parser.add_argument('--out',type=Path,default=OUT)
    args=parser.parse_args()
    out=args.out.resolve()
    assert (ROOT/'local-only').resolve() in out.parents,'GPU evidence must remain owner-local'
    names=['bmori','army','wmopj']
    for name in args.extra_model:
        assert re.fullmatch(r'[a-z0-9_]{1,40}',name),'invalid owner model name'
        assert name not in names,'duplicate owner model name'
        names.append(name)
    assert len(names)<=16,'bounded owner model count'
    out.mkdir(parents=True,exist_ok=True)
    (out/'generated.dff').write_bytes(fixture())
    paths = [ROOT/'ios/App'/(name+'.swift') for name in SOURCES]
    tracked=paths+[ROOT/'tests/resources/smoke_native_renderware_ped.py',ROOT/'tests/resources/smoke_native_renderware_ped.swift',
                   ROOT/'ios/App/NativeRenderWareModel.metal',ROOT/'ios/App/NativeRenderWarePedModel.metal']
    frozen = {str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in tracked}
    game = ROOT/'local-only/site/game'
    skeletons={name:str((args.extra_skeleton_root/(name+'.skel.bin')).resolve()
                       if name in args.extra_model and args.extra_skeleton_root else
                       game/'native/models'/(name+'.skel.bin')) for name in names}
    cases=out/'cases.json';cases.write_text(json.dumps({'models':names,'skeletons':skeletons}))
    owned = [game/(name+suffix) for name in names for suffix in ['.dff','.txd']]
    owned += [game/'native/models/animations.clips.bin']
    owned += list(map(Path,skeletons.values()))
    hashes = {str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in owned}
    binary = out/'ped-tests'
    build = subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(out/'module-cache'),
        *map(str,paths),str(ROOT/'tests/resources/smoke_native_renderware_ped.swift'),'-o',str(binary)],
        cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    (out/'build.log').write_text(build.stdout)
    assert build.returncode == 0,build.stdout
    run = subprocess.run([str(binary),str(ROOT),str(out),str(cases)],cwd=ROOT,
        stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    (out/'run.log').write_text(run.stdout)
    assert run.returncode == 0,run.stdout
    for path,digest in {**frozen,**hashes}.items():
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest,'input modified: '+path
    report=json.loads((out/'report.json').read_text())
    report.update(sourceFilesUnchanged=True,ownerSourcesUnchanged=True)
    (out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps(report,indent=2,sort_keys=True))


if __name__=='__main__':
    main()
