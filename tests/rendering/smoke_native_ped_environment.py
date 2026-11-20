#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual imported-character Metal fog, material ordering and scene isolation."""
from pathlib import Path
import argparse
import hashlib
import json
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))
from tests.resources.smoke_native_stock_ped import textured_ped, txd


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require-gpu', action='store_true')
    parser.add_argument('--historical-root', type=Path,
                        help='Run the actual earlier renderer/shaders; only the test scene binding is adapted.')
    args = parser.parse_args()
    source = (args.historical_root or ROOT).resolve()
    out = ROOT / 'local-only/research/ped-environment-151' / str(time.time_ns())
    out.mkdir(parents=True)
    (out / 'authored.dff').write_bytes(textured_ped())
    (out / 'authored.txd').write_bytes(txd([(255, 0, 0, 255)] * 3))
    names = ['NativeRenderWareDFF', 'NativeRenderWareTXD', 'NativeRenderWareModel',
             'NativeRenderWareSkeleton', 'NativeRenderWarePedModel', 'NativeActorAnimation',
             'NativeFootAnimation', 'NativeGunAnimation', 'NativeFlightAnimation',
             'NativeSwimAnimation', 'NativeRiderAnimation', 'NativeSkeletalActor']
    paths = [source / 'ios/App' / (name + '.swift') for name in names]
    paths.append(Path(__file__).with_suffix('.swift'))
    shaders = [source / 'ios/App' / (name + '.metal')
               for name in ['NativeRenderWareModel', 'NativeRenderWarePedModel']]
    frozen = {str(p): hashlib.sha256(p.read_bytes()).hexdigest()
              for p in [*paths, *shaders, Path(__file__) ]}
    (out / 'actual.metal').write_text('\n'.join(p.read_text() for p in shaders))
    command = ['xcrun', 'swiftc', '-j', '1', '-whole-module-optimization', '-num-threads', '1',
               '-Onone', '-module-cache-path', str(out / 'modules')]
    if args.historical_root:
        command += ['-D', 'HISTORICAL_PED_SCENE']
    command += [*map(str, paths), '-o', str(out / 'environment')]
    with (out / 'compile.log').open('x') as log:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT, timeout=300)
    if result.returncode:
        print((out / 'compile.log').read_text()[-4000:])
        result.check_returncode()
    result = subprocess.run([str(out / 'environment'), str(out),
                             *(['--require-gpu'] if args.require_gpu else [])],
                            capture_output=True, text=True, timeout=120)
    (out / 'runtime.log').write_text(result.stdout + result.stderr)
    report = dict(status=('SKIP_GPU' if result.stdout.startswith('SKIP') else 'PASS')
                  if result.returncode == 0 else 'FAIL', exitCode=result.returncode,
                  output=result.stdout + result.stderr, sourceSHA256=frozen,
                  sourcesHeld=all(hashlib.sha256(Path(p).read_bytes()).hexdigest() == h
                                  for p, h in frozen.items()), originalFilesUsed=False,
                  historical=bool(args.historical_root),
                  scope='Actual skinned encoder/shaders and authored rig/image/CLP1; '
                        'independent pixel oracle for the existing native clip-W fog policy. '
                        'No original-retail, device or timecycle-lighting claim.')
    (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    (out.parent / 'latest.json').write_text(json.dumps(dict(path=str(out), **report), indent=2) + '\n')
    print(json.dumps({k: report[k] for k in ['status', 'exitCode', 'sourcesHeld', 'historical']}), str(out))
    if result.returncode:
        print((result.stdout + result.stderr)[:1800])
    else:
        print(result.stdout.strip())
    result.check_returncode()
    assert report['sourcesHeld']


if __name__ == '__main__':
    main()
