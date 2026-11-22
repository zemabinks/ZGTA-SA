#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual parked condition and tyre-force owners; authored data, no game assets.

Requires the current prebuilt host physics archive. An optional historical root
must contain the preceding implementations of both parked owners; its failures
are verified separately from the current positive run.
"""
from pathlib import Path
import argparse
import hashlib
import json
import os
import platform
import runpy
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--historical-root', type=Path)
    parser.add_argument('--library', type=Path,
                        default=ROOT / 'local-only/native-physics' / ('macos-' + platform.machine()))
    args = parser.parse_args()
    os.setpriority(os.PRIO_PROCESS, 0, 15)
    library = args.library.resolve()
    archive = library / 'libzgtasa_native_physics.a'
    assert archive.is_file(), 'Build native-physics for this Mac first'
    names = runpy.run_path(str(ROOT / 'tests/vehicles/smoke_native_parked_phase.py'))['NAMES']
    owners = {'NativeOtherVehicles', 'NativeUnattendedVehicle'}
    variants = [('historical', args.historical_root.resolve())] if args.historical_root else []
    variants.append(('current', ROOT))
    paths = [ROOT / 'ios/App' / (name + '.swift') for name in names]
    paths += [Path(__file__).resolve(), Path(__file__).with_suffix('.swift'),
              ROOT / 'tests/vehicles/smoke_native_parked_phase.py',
              ROOT / 'native-physics/source_stamp.py', archive, library / 'source-stamp.json']
    if args.historical_root:
        paths += [args.historical_root.resolve() / 'ios/App' / (name + '.swift') for name in owners]
    sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    frozen = {str(path): sha(path) for path in paths}
    out = ROOT / 'local-only/research/parked-condition-test' / str(time.time_ns())
    out.mkdir(parents=True)
    report = dict(status='RUNNING', startedAt=time.time(), sourceHashes=frozen,
                  results=[], oneHeavyJob=True, actualNice=os.getpriority(os.PRIO_PROCESS, 0),
                  scope='Complete actual parked/damage/Rapier/force owners with authored vehicles. '
                        'Read-only reflection reaches standard damage operations and fire-clock state. '
                        'Fixed60Hz damage grid with15/30/60/120Hz metadata; actual car/bike tyre-force outputs. '
                        'No contact collision, App rendering, explosion delivery, hardware or retail claim.')

    def save():
        (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        (out.parent / 'latest.json').write_text(json.dumps(dict(path=str(out), status=report['status']), indent=2) + '\n')

    def execute(command, budget):
        process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE,
                                   stderr=subprocess.PIPE, text=True, start_new_session=True)
        report['activeOwnedProcessGroup'] = process.pid
        save()

        def stop():
            if process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=15)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()

        try:
            try:
                stdout, stderr = process.communicate(timeout=budget)
                code = process.returncode
            except subprocess.TimeoutExpired:
                stop()
                stdout, stderr = process.communicate()
                code = 124
                report.setdefault('timeouts', []).append(dict(command=command, budget=budget))
            return subprocess.CompletedProcess(command, code, stdout, stderr)
        except BaseException:
            stop()
            raise
        finally:
            report['activeOwnedProcessGroup'] = None
            save()

    save()
    try:
        checked = execute(['python3', 'native-physics/source_stamp.py', 'check', str(library)], 60)
        (out / 'archive-stamp.log').write_text(checked.stdout + checked.stderr)
        assert checked.returncode == 0, checked.stdout + checked.stderr
        for label, source_root in variants:
            work = out / label
            work.mkdir()
            sources = []
            for name in names:
                source = (source_root if name in owners else ROOT) / 'ios/App' / (name + '.swift')
                target = work / (name + '.swift')
                target.write_bytes(source.read_bytes())
                sources.append(str(target))
            gate = work / 'Gate.swift'
            gate.write_bytes(Path(__file__).with_suffix('.swift').read_bytes())
            sources.append(str(gate))
            command = ['xcrun', 'swiftc', '-parse-as-library', '-j', '1',
                       '-whole-module-optimization', '-num-threads', '1', '-Onone',
                       '-module-cache-path', str(out / 'modules'),
                       '-I', str(ROOT / 'native-physics/include'), *sources,
                       '-L', str(library), '-lzgtasa_native_physics',
                       '-framework', 'Security', '-framework', 'CoreFoundation',
                       '-o', str(work / 'gate')]
            row = dict(label=label, startedAt=time.time(), command=command, runtimeCases=[])
            report['results'].append(row)
            save()
            built = execute(command, 600)
            (work / 'compile.log').write_text(built.stdout + built.stderr)
            row['compileExit'] = built.returncode
            save()
            assert built.returncode == 0, built.stderr[-3000:]
            cases = [('metadata', []), ('fire', ['fire-only']), ('tyres', ['tyres-only'])] if label == 'historical' else [('all', [])]
            messages = {'metadata': 'metadata-only observation healed parked prediction',
                        'fire': 'pose observations restarted engine-fire clock',
                        'tyres': 'parked puncture never reached actual solver'}
            for case, options in cases:
                ran = execute([str(work / 'gate'), *options], 90)
                (work / (case + '-runtime.log')).write_text(ran.stdout + ran.stderr)
                row['runtimeCases'].append(dict(case=case, exitCode=ran.returncode, output=ran.stdout + ran.stderr))
                save()
                if label == 'historical':
                    assert ran.returncode == 42 and messages[case] in ran.stdout, ran.stdout + ran.stderr
                else:
                    assert ran.returncode == 0 and 'PASS' in ran.stdout, ran.stdout + ran.stderr
            row['seconds'] = time.time() - row['startedAt']
            save()
        assert all(sha(Path(path)) == digest for path, digest in frozen.items())
        report['status'] = 'PASS'
    except BaseException as error:
        report.update(status='FAIL', error=repr(error))
        raise
    finally:
        report.update(completedAt=time.time(), inputsHeld=all(sha(Path(path)) == digest for path, digest in frozen.items()))
        save()
        print(json.dumps(dict(status=report['status'], inputsHeld=report['inputsHeld'],
                              results=[{key: row[key] for key in ['label', 'compileExit', 'runtimeCases', 'seconds'] if key in row}
                                       for row in report['results']], output=str(out)), indent=2))


if __name__ == '__main__':
    main()
