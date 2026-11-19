#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual native rider phase clock on invented CLP1 tracks; no Metal/network."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import tempfile
import time

ROOT=Path(__file__).resolve().parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--negative-source',type=Path,help='Optional historical independent Playback source; same assertions must fail.')
    parser.add_argument('--durations',type=Path,help='Optional bounded role-to-duration JSON metadata; tracks remain invented.')
    parser.add_argument('--out',type=Path,default=ROOT/'local-only/research/rider-clock-115')
    args=parser.parse_args()
    out=args.out.resolve()
    if ROOT/'local-only' not in out.parents:
        raise SystemExit('Keep test output under this checkout local-only directory.')
    out.mkdir(parents=True,exist_ok=True)
    sources=[ROOT/'ios/App'/name for name in ['NativeSkeletalActor.swift','NativeRiderAnimation.swift',
             'NativeBoardingAnimation.swift','NativeRiderPlayback.swift']]
    sources += [Path(__file__).resolve(),ROOT/'tests/vehicles/smoke_native_rider_clock.swift']
    before={str(p):sha(p) for p in sources}
    if args.negative_source:
        args.negative_source=args.negative_source.resolve()
        before[str(args.negative_source)]=sha(args.negative_source)
    if args.durations:
        args.durations=args.durations.resolve()
        if args.durations.stat().st_size>16384:raise SystemExit('Duration fixture exceeds16KiB.')
        before[str(args.durations)]=sha(args.durations)
    # The actual CPU CLP1 decoder precedes the Metal actor type. Preserve its
    # implementation literally; remove only the unused import of Metal.
    whole=sources[0].read_text()
    boundary=whole.index('struct NativeSkeletalLayer {')
    library=whole[:boundary].replace('import Metal\n','')
    assert 'final class NativeSkeletalAnimationLibrary' in library and 'MTL' not in library
    assert 'class NativeSkeletalActor' not in library
    results=[]
    with tempfile.TemporaryDirectory(prefix='snapshot-',dir=out) as temporary:
        work=Path(temporary)
        (work/'ActualClipLibrary.swift').write_text(library)
        for name,path in [('RiderAnimation.swift',sources[1]),('BoardingAnimation.swift',sources[2]),
                          ('Playback.swift',sources[3]),('ClockTests.swift',sources[-1])]:
            (work/name).write_bytes(path.read_bytes())
        def compile_and_run(label,playback):
            (work/'Playback.swift').write_bytes(playback.read_bytes())
            binary=work/('verify-'+label)
            command=['xcrun','swiftc','-Onone','-module-cache-path',str(out/'modules'),
                     *[str(work/name) for name in ['ActualClipLibrary.swift','RiderAnimation.swift',
                                                  'BoardingAnimation.swift','Playback.swift','ClockTests.swift']],
                     '-o',str(binary)]
            start=time.monotonic()
            built=subprocess.run(command,capture_output=True,text=True,timeout=180)
            (out/(label+'-compile.log')).write_text(built.stdout+built.stderr)
            if built.returncode:raise RuntimeError(label+' compile failed; see retained log')
            command=[str(binary)]+([str(args.durations)] if args.durations else [])
            ran=subprocess.run(command,capture_output=True,text=True,timeout=30)
            (out/(label+'-runtime.log')).write_text(ran.stdout+ran.stderr)
            data=json.loads(ran.stdout)
            row=dict(label=label,compileExit=0,runExit=ran.returncode,seconds=time.monotonic()-start,
                     sourceSHA256=sha(playback),result=data)
            results.append(row)
            return row
        if args.negative_source:
            negative=compile_and_run('historical-negative',args.negative_source)
            assert negative['runExit']!=0 and negative['result']['status']=='FAIL'
            assert negative['result']['failure'] in ['phase clock schedule dependence',
                'phase sample schedule dependence','phase sample elapsed lost','phase anchor schedule dependence',
                'phase serial schedule dependence','door owner schedule dependence','door elapsed schedule dependence',
                'transition elapsed schedule dependence'],negative
        positive=compile_and_run('current',sources[3])
        assert positive['runExit']==0 and positive['result']['status']=='PASS',positive
    after={p:sha(Path(p)) for p in before}
    assert before==after,'Scoped source/fixture changed during test'
    report=dict(status='PASS',sourceUnchanged=True,sourceHashes=before,results=results,
                boundary='Actual native CLP1 reader/planner/playback; synthetic tracks and authored definitions. Optional external metadata proves duration boundaries only.',
                noRenderedOrRetailAcceptance=True)
    (out/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
    print(json.dumps(report,indent=2,sort_keys=True))


if __name__=='__main__':
    main()
