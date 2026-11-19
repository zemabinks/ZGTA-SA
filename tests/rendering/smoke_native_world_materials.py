#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual Metal shading and renderer material ownership on authored pixels."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--require-gpu', action='store_true')
    parser.add_argument('--shader-source', type=Path, default=ROOT/'ios/App/WorldShaders.metal')
    parser.add_argument('--renderer-source', type=Path, default=ROOT/'ios/App/NativeWorldRenderer.swift')
    args = parser.parse_args()
    os.setpriority(os.PRIO_PROCESS, 0, 15)
    output = ROOT/'local-only/research/world-materials-143'
    output.mkdir(parents=True, exist_ok=True)
    harness = Path(__file__).with_suffix('.swift')
    sources = [args.shader_source, args.renderer_source, harness, Path(__file__)]
    captured = {p.resolve(): p.read_bytes() for p in sources}
    renderer = captured[args.renderer_source.resolve()].decode()
    begin = renderer.index('        guard let device = preferredDevice,', renderer.index('    init?(preferredDevice:'))
    end = renderer.index('        descriptor.vertexFunction = library.makeFunction(name: "nativeDomeVertex")', begin)
    constructor = renderer[begin:end]
    declaration = '    private func drawWorldMeshes('
    if declaration in renderer:
        start = renderer.index('{', renderer.index(declaration)) + 1
        # Body is delimited by the next method, without rewriting its statements.
        end = renderer.index('\n    }', start)
        batch = renderer[start:end]
        assert 'drawWorldMeshes(matrix: matrix,encoder: encoder)' in renderer
    else:
        batch = '    fatalError("World material batch has not been integrated")\n'
    template = captured[harness.resolve()].decode()
    source = template.replace('    // PRODUCTION_CONSTRUCTOR', constructor).replace('    // PRODUCTION_WORLD_BATCH', batch)
    with tempfile.TemporaryDirectory(prefix='run-', dir=output) as folder:
        work = Path(folder); (work/'world.metal').write_bytes(captured[args.shader_source.resolve()])
        (work/'main.swift').write_text(source)
        records = []
        for stage, command, timeout in [
            ('compile', ['xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-j', '1', '-num-threads', '1',
                         '-module-cache-path', str(output/'modules'), str(work/'main.swift'), '-o', str(work/'gate')], 300),
            ('runtime', [str(work/'gate'), str(work/'world.metal'), str(work/'result.json'),
                         'require-gpu' if args.require_gpu else 'allow-no-gpu'], 180),
        ]:
            result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
            (output/(stage+'.log')).write_text(result.stdout+result.stderr)
            records.append(dict(stage=stage, exitCode=result.returncode))
            if result.returncode:
                print(result.stdout+result.stderr); break
        unchanged = all(p.read_bytes() == data for p, data in captured.items())
        native = json.loads((work/'result.json').read_text()) if (work/'result.json').exists() else None
        report = dict(status='PASS' if len(records)==2 and unchanged and all(r['exitCode']==0 for r in records) else 'FAIL',
                      records=records, native=native, sourceUnchanged=unchanged,
                      sourceHashes={str(p): hashlib.sha256(data).hexdigest() for p,data in captured.items()},
                      constructorSHA256=hashlib.sha256(constructor.encode()).hexdigest(),
                      batchSHA256=hashlib.sha256(batch.encode()).hexdigest(), originalAssetsUsed=False)
        (output/'report.json').write_text(json.dumps(report, indent=2)+'\n')
        print(json.dumps({k:report[k] for k in ['status','records','native','sourceUnchanged']}, indent=2))
        if report['status'] != 'PASS': raise SystemExit(1)


if __name__ == '__main__':
    main()
