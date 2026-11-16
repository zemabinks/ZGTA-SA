#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Compile the real actor/animation sources and test native custom-ped rendering.

Reads owner-local DFF/TXD/CLP1/SKN1 only. Fixtures, GPU readbacks and executables
stay under local-only/research/runtime-ped. The actual Renderer is not modified.
"""
import hashlib
import json
from pathlib import Path
import subprocess

from smoke_native_renderware_skeleton import fixture

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'local-only/research/runtime-ped'
SOURCES = ['NativeRenderWareDFF','NativeRenderWareTXD','NativeRenderWareModel','NativeRenderWareSkeleton',
           'NativeRenderWarePedModel','NativeActorAnimation','NativeFootAnimation','NativeGunAnimation',
           'NativeFlightAnimation','NativeSwimAnimation','NativeRiderAnimation','NativeSkeletalActor']


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    (OUT/'generated.dff').write_bytes(fixture())
    paths = [ROOT/'ios/App'/(name+'.swift') for name in SOURCES]
    frozen = {str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
    game = ROOT/'local-only/site/game'
    owned = [game/(name+suffix) for name in ['bmori','army','wmopj'] for suffix in ['.dff','.txd']]
    owned += [game/'native/models/animations.clips.bin']
    owned += [game/'native/models'/(name+'.skel.bin') for name in ['bmori','army','wmopj']]
    hashes = {str(path):hashlib.sha256(path.read_bytes()).hexdigest() for path in owned}
    binary = OUT/'ped-tests'
    build = subprocess.run(['xcrun','swiftc','-O','-module-cache-path',str(OUT/'module-cache'),
        *map(str,paths),str(ROOT/'smoke_native_renderware_ped.swift'),'-o',str(binary)],
        cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    (OUT/'build.log').write_text(build.stdout)
    assert build.returncode == 0,build.stdout
    run = subprocess.run([str(binary),str(ROOT),str(OUT)],cwd=ROOT,
        stdout=subprocess.PIPE,stderr=subprocess.STDOUT,text=True)
    (OUT/'run.log').write_text(run.stdout)
    assert run.returncode == 0,run.stdout
    for path,digest in {**frozen,**hashes}.items():
        assert hashlib.sha256(Path(path).read_bytes()).hexdigest()==digest,'input modified: '+path
    report=json.loads((OUT/'report.json').read_text())
    report.update(sourceFilesUnchanged=True,ownerSourcesUnchanged=True)
    (OUT/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps(report,indent=2,sort_keys=True))


if __name__=='__main__':
    main()
