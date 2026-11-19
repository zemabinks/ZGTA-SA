#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Compile the real navigation reader and exercise isolated authored raw stores."""
from pathlib import Path
import hashlib
import json
import os
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))
from tests.resources.native_raw_test_support import pinned_host_archive


def main():
    os.setpriority(os.PRIO_PROCESS, 0, 15)
    output = ROOT / 'local-only/research/original-navigation-142'
    output.mkdir(parents=True, exist_ok=True)
    archive = pinned_host_archive(os.environ.get('ZGTA_RAW_TEST_ARCHIVE'))
    names = ['NativeResourceManifest', 'NativeResourceStore', 'NativeRawResourceLease',
             'NativeRawResourceStore', 'NativeGameSourceInspector', 'NativeOriginalPathQuery',
             'NativeOriginalNavigationLoader', 'NativeGameFilesCoordinator']
    sources = [ROOT / 'ios/App' / (name + '.swift') for name in names]
    sources += [ROOT / 'native-installer/swift' / (name + '.swift') for name in
                ['NativeISOExtraction', 'NativeRawResourceSelection']]
    tests = [ROOT / 'tests/resources' / name for name in
             ['smoke_native_original_paths.swift', 'smoke_native_original_navigation.swift']]
    captured = {path: path.read_bytes() for path in sources + tests + [Path(__file__)]}
    records = []
    with tempfile.TemporaryDirectory(prefix='run-', dir=output) as folder:
        work = Path(folder)
        for path, data in captured.items():
            (work / path.name).write_bytes(data)
        for name, selected, test in [
            ('paths', [sources[names.index('NativeOriginalPathQuery')]], tests[0]),
            ('loader', sources, tests[1]),
        ]:
            executable = work / name
            command = ['xcrun', 'swiftc', '-swift-version', '5', '-parse-as-library',
                       '-j', '1', '-num-threads', '1', '-module-cache-path', str(output / 'modules'),
                       '-I', str(ROOT / 'native-installer/include'),
                       *[str(work / path.name) for path in selected], str(work / test.name),
                       *([str(archive), '-lz'] if name == 'loader' else []), '-o', str(executable)]
            for stage, argv, timeout in [('compile', command, 300),
                                          ('runtime', [str(executable), str(work / 'fixture')], 180)]:
                result = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
                log = output / (name + '-' + stage + '.log')
                log.write_text(result.stdout + result.stderr)
                records.append(dict(name=name, stage=stage, exitCode=result.returncode, log=str(log)))
                if result.returncode:
                    print(log.read_text())
                    break
            if records[-1]['exitCode']:
                break
        unchanged = all(path.read_bytes() == data for path, data in captured.items())
        report = dict(status='PASS' if len(records) == 4 and unchanged and
                      all(row['exitCode'] == 0 for row in records) else 'FAIL', records=records,
                      sourceHashes={str(path.relative_to(ROOT)): hashlib.sha256(data).hexdigest()
                                    for path, data in captured.items()}, sourceUnchanged=unchanged,
                      limits=['Authored DAT fixtures and real raw-store/lease/coordinator APIs.',
                              'Generic geometric routes; no original AI, population or retail parity claim.',
                              'No original files, installed app, renderer or network world operated.'])
        (output / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print(json.dumps(dict(status=report['status'], records=records), indent=2))
        if report['status'] != 'PASS':
            raise SystemExit(1)


if __name__ == '__main__':
    main()
