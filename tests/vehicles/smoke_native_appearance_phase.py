#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual full-appearance observation and continuous physics lifetime owners.

Authored fixtures only. Requires the existing host physics archive. An optional
historical root verifies four preceding-source failures separately. The retained
Core196 helper fixture has only its entrypoint attribute removed for reuse;
production Swift files are copied unchanged.
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
    parser.add_argument('--historical-only', action='store_true')
    parser.add_argument('--library', type=Path, default=ROOT / 'local-only/native-physics' / ('macos-' + platform.machine()))
    args = parser.parse_args()
    assert not args.historical_only or args.historical_root, '--historical-only requires an explicit historical root'
    os.setpriority(os.PRIO_PROCESS, 0, 15)
    library = args.library.resolve()
    archive = library / 'libzgtasa_native_physics.a'
    assert archive.is_file(), 'Build native-physics for this Mac first'
    names = runpy.run_path(str(ROOT / 'tests/vehicles/smoke_native_parked_phase.py'))['NAMES']
    owners = {'NativeOtherVehicles', 'NativeVehicleDamage'}
    variants = [('historical', args.historical_root.resolve())] if args.historical_root else []
    if not args.historical_only:
        variants.append(('current', ROOT))
    paths = [ROOT / 'ios/App' / (name + '.swift') for name in names]
    paths += [Path(__file__).resolve(), Path(__file__).with_suffix('.swift'), ROOT / 'tests/vehicles/smoke_native_parked_phase.py', ROOT / 'tests/vehicles/smoke_native_parked_health.swift', ROOT / 'native-physics/source_stamp.py', archive, library / 'source-stamp.json']
    if args.historical_root:
        paths += [args.historical_root.resolve() / 'ios/App' / (name + '.swift') for name in owners]
    sha = lambda path: hashlib.sha256(path.read_bytes()).hexdigest()
    frozen = {str(path): sha(path) for path in paths}
    out = ROOT / 'local-only/research/appearance-phase-test' / str(time.time_ns())
    out.mkdir(parents=True)
    report = dict(status='RUNNING', startedAt=time.time(), sourceHashes=frozen, results=[], oneHeavyJob=True, actualNice=os.getpriority(os.PRIO_PROCESS, 0), scope='Complete actual parked/damage/force/Rapier classes. Authored full appearance snapshots, fixed60Hz damage and read-only introspection. Continuous fire/door/impact/upside state; retained initializer logical semantics and subsequent damage across authored profiles. No per-part ACK protocol, physical contact, App rendering, traffic collision response, parked explosion delivery or retail timing claim.')

    def save():
        (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        (out.parent / 'latest.json').write_text(json.dumps(dict(path=str(out), status=report['status']), indent=2) + '\n')

    def execute(command, budget):
        process = subprocess.Popen(command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, start_new_session=True)
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
            helper = ROOT / 'tests/vehicles/smoke_native_parked_health.swift'
            text = helper.read_text()
            assert text.count('@main enum ParkedHealthProbe') == 1
            reused = work / 'ParkedHealthProbe.swift'
            reused.write_text(text.replace('@main enum ParkedHealthProbe', 'enum ParkedHealthProbe', 1))
            sources.append(str(reused))
            gate = work / 'Gate.swift'
            gate.write_bytes(Path(__file__).with_suffix('.swift').read_bytes())
            command = ['xcrun', 'swiftc', '-parse-as-library', '-j', '1', '-whole-module-optimization', '-num-threads', '1', '-Onone', '-module-cache-path', str(out / 'modules'), *(['-D', 'HISTORICAL'] if label == 'historical' else []), '-I', str(ROOT / 'native-physics/include'), *sources, str(gate), '-L', str(library), '-lzgtasa_native_physics', '-framework', 'Security', '-framework', 'CoreFoundation', '-o', str(work / 'gate')]
            row = dict(label=label, startedAt=time.time(), command=command, runtimeCases=[])
            report['results'].append(row)
            save()
            built = execute(command, 600)
            (work / 'compile.log').write_text(built.stdout + built.stderr)
            row['compileExit'] = built.returncode
            save()
            assert built.returncode == 0, built.stderr[-4000:]
            messages = {'fire': 'appearance replacement restarted continuous burn phase', 'door': 'unchanged authoritative open door lost physical motion', 'impact': 'appearance replacement discarded pending physical impact', 'upside': 'appearance replacement restarted continuous inverted-body phase'}
            cases = [(name, [name]) for name in messages] if label == 'historical' else [('all', [])]
            for name, options in cases:
                ran = execute([str(work / 'gate'), *options], 90)
                (work / (name + '-runtime.log')).write_text(ran.stdout + ran.stderr)
                row['runtimeCases'].append(dict(case=name, exitCode=ran.returncode, output=ran.stdout + ran.stderr))
                save()
                if label == 'historical':
                    assert ran.returncode == 42 and messages[name] in ran.stdout, ran.stdout + ran.stderr
                else:
                    assert ran.returncode == 0 and 'PASS' in ran.stdout, ran.stdout + ran.stderr
            row['seconds'] = time.time() - row['startedAt']
            save()
        assert all(sha(Path(path)) == digest for path, digest in frozen.items())
        report['status'] = 'EXPECTED_HISTORICAL_FAILURES_ONLY' if args.historical_only else 'PASS'
    except BaseException as error:
        report.update(status='FAIL', error=repr(error))
        raise
    finally:
        report.update(completedAt=time.time(), inputsHeld=all(sha(Path(path)) == digest for path, digest in frozen.items()))
        save()
        print(json.dumps(dict(status=report['status'], inputsHeld=report['inputsHeld'], results=[{key: row[key] for key in ['label', 'compileExit', 'runtimeCases', 'seconds'] if key in row} for row in report['results']], output=str(out)), indent=2))


if __name__ == '__main__':
    main()
