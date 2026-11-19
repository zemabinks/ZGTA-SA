#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Generated static-model CPU regressions plus optional native Metal readback.

No original assets, downloads, UIKit or Renderer modifications. If the Mac has no
Metal device the CPU results pass with an explicit GPU-unavailable result.
The exact checked-in .metal source is compiled through the native Metal API.
"""
import argparse
import hashlib
import json
import pathlib
import struct
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--module-cache', type=pathlib.Path, default=pathlib.Path('/private/tmp/zgtasa-core-swift-modules'))
parser.add_argument('--owner-corpus', type=pathlib.Path, help='read-only DFF/TXD folder for static-resource smoke test')
parser.add_argument('--cpu-only', action='store_true', help='skip Metal device creation and all GPU calls')
args = parser.parse_args()
output = ROOT / 'local-only/research/runtime-model'
output.mkdir(parents=True,exist_ok=True)
args.module_cache.mkdir(parents=True,exist_ok=True)
binary = output / 'model-tests'
source_hashes = {}
runtime_paths = [ROOT/'ios/App'/name for name in ['NativeRenderWareDFF.swift','NativeRenderWareTXD.swift','NativeRenderWareModel.swift','NativeRenderWareModel.metal']]
runtime_paths += [ROOT/'tests/renderware_model/main.swift',pathlib.Path(__file__).resolve()]
runtime_hashes = {str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in runtime_paths}
reference_rejections = []
if args.owner_corpus:
    # Reuse the separate DFF suite's raw/exporter oracle, not this Swift parser.
    # Original files with invalid chunks or NaN meaningful fields remain invalid.
    from smoke_native_renderware_dff import reference
    for path in sorted(args.owner_corpus.glob('*.dff')):
        source_hashes[path] = hashlib.sha256(path.read_bytes()).hexdigest()
        try:
            reference(path, False)
        except (AssertionError, ValueError, struct.error) as error:
            reference_rejections.append({'file': path.name,'referenceError': str(error)})
    if not source_hashes:
        raise SystemExit('No owner-local DFF corpus found')
rejections_path = output/'reference-rejections.json'
rejections_path.write_text(json.dumps([entry['file'] for entry in reference_rejections]))
(output/'reference-rejection-evidence.json').write_text(json.dumps(reference_rejections,indent=2)+'\n')
subprocess.run(['xcrun','swiftc','-swift-version','5','-whole-module-optimization','-num-threads','1','-O','-module-cache-path',str(args.module_cache),
                str(ROOT/'ios/App/NativeRenderWareDFF.swift'),str(ROOT/'ios/App/NativeRenderWareTXD.swift'),
                str(ROOT/'ios/App/NativeRenderWareModel.swift'),str(ROOT/'tests/renderware_model/main.swift'),
                '-o',str(binary)],check=True,cwd=ROOT)
command = [str(binary),str(ROOT/'ios/App/NativeRenderWareModel.metal')]
if args.owner_corpus:
    command.extend([str(args.owner_corpus.resolve()),str(rejections_path)])
if args.cpu_only:
    command.append('--cpu-only')
result = subprocess.run(command,capture_output=True,text=True,cwd=ROOT)
(output/'stdout.log').write_text(result.stdout)
(output/'stderr.log').write_text(result.stderr)
if result.returncode:
    try:
        (output/'failed-report.json').write_text(json.dumps(json.loads(result.stdout),indent=2,sort_keys=True)+'\n')
    except (ValueError, TypeError):
        pass
    raise SystemExit(result.stdout+result.stderr)
report = json.loads(result.stdout)
for path,digest in source_hashes.items():
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, 'Owner-local DFF source changed'
report['ownerSourceHashesUnchanged'] = True
assert all(hashlib.sha256((ROOT/name).read_bytes()).hexdigest() == digest for name,digest in runtime_hashes.items()), 'Runtime or test source changed'
report['runtimeAndTestSourceHashes'] = runtime_hashes
report['runtimeAndTestSourcesUnchanged'] = True
report['scope'] = ('static model CPU preparation only; Metal device creation explicitly disabled' if args.cpu_only else
                   'static model CPU/GPU loader only; not game-world integration or multiplayer custom-model parity')
(output/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print(json.dumps(report,indent=2,sort_keys=True))
