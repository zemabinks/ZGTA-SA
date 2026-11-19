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
import re
import struct
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--module-cache', type=pathlib.Path, default=pathlib.Path('/private/tmp/zgtasa-core-swift-modules'))
parser.add_argument('--owner-corpus', type=pathlib.Path, help='read-only DFF/TXD folder for static-resource smoke test')
parser.add_argument('--cpu-only', action='store_true', help='skip Metal device creation and all GPU calls')
parser.add_argument('--metal-source', type=pathlib.Path, help='explicit alternate shader for a labelled historical negative; current Swift model stays unchanged')
parser.add_argument('--require-metal', action='store_true', help='fail instead of accepting an unavailable Metal device')
parser.add_argument('--output', type=pathlib.Path, help='separate ignored output directory for a retained attempt')
parser.add_argument('--validate-config', action='store_true', help='source/argument checks only; no compiler, device or GPU calls')
args = parser.parse_args()
if args.cpu_only and (args.require_metal or args.metal_source):
    parser.error('--cpu-only cannot exercise --require-metal or an alternate Metal shader')
output = (args.output or ROOT / 'local-only/research/runtime-model').resolve()
binary = output / 'model-tests'
metal_source = (args.metal_source or ROOT/'ios/App/NativeRenderWareModel.metal').resolve(strict=True)
assert metal_source.is_file() and metal_source.stat().st_size <= 2*1024*1024, 'Bounded shader source required'
shader_hash = hashlib.sha256(metal_source.read_bytes()).hexdigest()
source_hashes = {}
runtime_paths = [ROOT/'ios/App'/name for name in ['NativeRenderWareDFF.swift','NativeRenderWareTXD.swift','NativeRenderWareModel.swift','NativeRenderWareModel.metal']]
runtime_paths += [ROOT/'ios/App'/name for name in ['NativeSAMPStockAssetLoader.swift','NativeWorldRenderer.swift']]
runtime_paths += [ROOT/'tests/renderware_model/main.swift',pathlib.Path(__file__).resolve()]
runtime_hashes = {str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in runtime_paths}
# This is deliberately labelled source-contract coverage, not a substitute for
# real StockAssetLoader/Artwork transfer tests. No new missing-name admission.
stock_source = (ROOT/'ios/App/NativeSAMPStockAssetLoader.swift').read_text()
renderer_source = (ROOT/'ios/App/NativeWorldRenderer.swift').read_text()
custom_start = renderer_source.index('for diagnostic in plan.resources.diagnostics {')
custom_end = renderer_source.index('let collision=model.type',custom_start)
custom_diagnostics = renderer_source[custom_start:custom_end]
admission_checks = {
    'stockMissingRequiredFilesRejected': bool(re.search(r'guard\s+missing\.isEmpty\s+else\s*\{\s*throw\s+Failure\.missingAssets\(',stock_source)),
    'stockMissingReferencedNamesRejected': bool(re.search(r'guard\s+missing\.isEmpty\s+else\s*\{\s*throw\s+Loader\.Failure\.unresolvedTextures\(',stock_source)),
    'stockUsesActualBoundedTXDDecoder': 'NativeRenderWareTXD.decode(data,limits:budget)' in stock_source,
    'customOnlyOmittedMipTailIsAllowed': re.findall(r'(?m)^\s*case\s+([^:]+):',custom_diagnostics) == ['.omittedMipTail'],
    'customOtherResourceDiagnosticsThrow': bool(re.search(r'default\s*:\s*throw\s+NativeRenderWareModel\.Failure\.unsupported\(',custom_diagnostics)),
}
assert all(admission_checks.values()), 'Strict stock/custom admission source contract changed: '+str(admission_checks)
if args.validate_config:
    print(json.dumps({'status':'PREPARE_ONLY_SOURCE_CONFIG_VALIDATED','noCompilerOrGPU':True,
        'runtimeAndTestSourceHashes':runtime_hashes,'strictAdmissionSourceChecks':admission_checks,
        'shaderSource':str(metal_source),'shaderSHA256':shader_hash,'output':str(output)},indent=2,sort_keys=True))
    raise SystemExit(0)
output.mkdir(parents=True,exist_ok=True)
args.module_cache.mkdir(parents=True,exist_ok=True)
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
command = [str(binary),str(metal_source)]
if args.owner_corpus:
    command.extend([str(args.owner_corpus.resolve()),str(rejections_path)])
if args.cpu_only:
    command.append('--cpu-only')
result = subprocess.run(command,capture_output=True,text=True,cwd=ROOT)
(output/'stdout.log').write_text(result.stdout)
(output/'stderr.log').write_text(result.stderr)
(output/'attempt.json').write_text(json.dumps({
    'status':'runtime-passed' if result.returncode == 0 else 'runtime-failed',
    'returnCode':result.returncode,'signal':-result.returncode if result.returncode < 0 else None,
    'shaderSource':str(metal_source),'shaderSHA256':shader_hash,
    'runtimeAndTestSourceHashes':runtime_hashes,
    'runtimeAndTestSourcesUnchanged':all(hashlib.sha256((ROOT/name).read_bytes()).hexdigest() == digest for name,digest in runtime_hashes.items()),
    'selectedShaderUnchanged':hashlib.sha256(metal_source.read_bytes()).hexdigest() == shader_hash,
    'specificNoMapContractSeenInStderr':'no-map border sampling bypass preserves the material' in result.stderr,
    'alternateShaderIsHistoricalOrAuthoredControl':args.metal_source is not None,
},indent=2,sort_keys=True)+'\n')
if result.returncode:
    try:
        (output/'failed-report.json').write_text(json.dumps(json.loads(result.stdout),indent=2,sort_keys=True)+'\n')
    except (ValueError, TypeError):
        pass
    raise SystemExit(result.stdout+result.stderr)
report = json.loads(result.stdout)
assert not args.require_metal or report.get('metal') == 'passed-offscreen-4x4-rgba-and-mip-readback', 'Actual Metal device/readback is required'
for path,digest in source_hashes.items():
    assert hashlib.sha256(path.read_bytes()).hexdigest() == digest, 'Owner-local DFF source changed'
report['ownerSourceHashesUnchanged'] = True
assert all(hashlib.sha256((ROOT/name).read_bytes()).hexdigest() == digest for name,digest in runtime_hashes.items()), 'Runtime or test source changed'
report['runtimeAndTestSourceHashes'] = runtime_hashes
report['runtimeAndTestSourcesUnchanged'] = True
assert hashlib.sha256(metal_source.read_bytes()).hexdigest() == shader_hash, 'Selected shader source changed'
report['shaderSource'] = str(metal_source)
report['shaderSourceSHA256'] = shader_hash
report['alternateShaderIsHistoricalOrAuthoredControl'] = args.metal_source is not None
report['strictAdmissionSourceChecks'] = admission_checks
report['strictAdmissionCoverage'] = 'actual current-source predicates only; no StockAssetLoader/Artwork runtime execution in this carrier'
report['scope'] = ('static model CPU preparation only; Metal device creation explicitly disabled' if args.cpu_only else
                   'static model CPU/GPU loader only; not game-world integration or multiplayer custom-model parity')
(output/'report.json').write_text(json.dumps(report,indent=2,sort_keys=True)+'\n')
print(json.dumps(report,indent=2,sort_keys=True))
