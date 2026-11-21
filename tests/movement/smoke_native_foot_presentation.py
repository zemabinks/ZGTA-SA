#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual coordinator and renderer getters with authored deterministic motor boundaries."""
from pathlib import Path
import argparse, hashlib, json, os, subprocess, time
ROOT = Path(__file__).resolve().parents[2]
def declaration(source, marker):
    start = source.index(marker)
    brace = source.index('{', start)
    depth, end = 1, brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--controller', type=Path, default=ROOT/'ios/App/NativeCharacterController.swift')
    parser.add_argument('--renderer', type=Path, default=ROOT/'ios/App/NativeWorldRenderer.swift')
    args = parser.parse_args()
    assert os.getpriority(os.PRIO_PROCESS, 0) == 15
    controller, renderer = args.controller.read_text(), args.renderer.read_text()
    previous = 'var presentationFeet:' not in controller
    # Compatibility adapter exposes exactly the old committed state boundary.
    # It does not replace or reimplement the old coordinator update/state code.
    if previous:
        controller += '\nextension NativeCharacterController { var presentationFeet:SIMD3<Float>{state.feet} }\n'
    getter = declaration(renderer, 'private var footPresentationPosition:') if 'private var footPresentationPosition:' in renderer else 'private var footPresentationPosition:SIMD3<Float>{camera}'
    getters = '\n'.join([getter, declaration(renderer, 'var position: SIMD3<Float>'), declaration(renderer, 'var shotFeet:')])
    main_source = (ROOT/'tests/movement/smoke_native_foot_presentation.swift').read_text().replace('// ACTUAL_RENDERER_GETTERS', getters)
    out = ROOT/'local-only/research/foot-presentation-179'/str(time.time_ns()); out.mkdir(parents=True)
    (out/'Controller.swift').write_text(controller); (out/'main.swift').write_text(main_source)
    paths = [args.controller, args.renderer, Path(__file__), ROOT/'tests/movement/smoke_native_foot_presentation.swift']
    frozen = {str(p.resolve()):hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    report = dict(status='RUNNING', previousCommittedBoundary=previous, sources=frozen,
                  scope='Actual whole fixed coordinator and renderer publication getters; authored motor/query boundaries, not real physics or App/retail acceptance')
    started = time.time()
    with (out/'compile.log').open('x') as log:
        result = subprocess.run(['xcrun','swiftc','-j','1','-whole-module-optimization','-num-threads','1','-Onone','-module-cache-path',str(out/'modules'),str(out/'Controller.swift'),str(out/'main.swift'),'-o',str(out/'verify')], stdout=log, stderr=subprocess.STDOUT, timeout=180)
    report['compilerExitCode'] = result.returncode
    if result.returncode == 0:
        result = subprocess.run([str(out/'verify')], capture_output=True, text=True, timeout=60)
        (out/'runtime.log').write_text(result.stdout+result.stderr)
        report.update(exitCode=result.returncode, output=result.stdout+result.stderr)
    report.update(status='PASS' if result.returncode == 0 else 'FAIL', seconds=time.time()-started,
                  sourcesHeld=all(hashlib.sha256(Path(n).read_bytes()).hexdigest() == h for n,h in frozen.items()))
    (out/'report.json').write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps(dict(path=str(out),**report)))
    raise SystemExit(result.returncode or (0 if report['sourcesHeld'] else 2))
if __name__ == '__main__':
    main()
