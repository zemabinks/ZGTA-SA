#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Actual backend-produced NPC hits through the native decoder and pose owner."""
from pathlib import Path
import hashlib
import json
import os
import signal
import subprocess
import time

ROOT = Path(__file__).resolve().parents[2]


def main():
    os.setpriority(os.PRIO_PROCESS, 0, 15)
    out = ROOT / 'local-only/research/native-population-hit-piece' / str(time.time_ns())
    out.mkdir(parents=True)
    names = ['NativeSkeletalActor', 'NativeGunAnimation', 'NativeSwimAnimation', 'NativeFlightAnimation',
             'NativeFootAnimation', 'NativePedestrianReaction', 'NativeAmbientPedestrianProtocol', 'NativeAmbientPedestrianAnimation']
    paths = [ROOT / 'ios/App' / (name + '.swift') for name in names]
    paths += [Path(__file__), Path(__file__).with_suffix('.swift'), Path(__file__).with_name('smoke_population_hit_piece.js'),
              ROOT / 'tests/network/smoke_native_ambient_animation.swift']
    paths += [ROOT / name for name in ['selfhost_backend.js', 'optional_discord.js', 'weapon_inventory.js',
              'world_collision.js', 'local_projectiles.js', 'player_placement.js',
              'server/population/pedestrians.js', 'server/population/pedestrian_protocol.js']]
    frozen = {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths}
    actor = paths[0].read_text()
    common = actor[:actor.index('struct NativeSkinVertex')].replace('import Metal', '')
    common += '\nfinal class NativeSkeletalActor {\n' + actor[actor.index('    struct OriginalAim {'):actor.index('    struct Pose {')] + '}\n'
    common += '\n'.join(path.read_text() for path in paths[1:6])
    (out / 'Common.swift').write_text(common)
    fixture = paths[11].read_text()
    assert fixture.count('@main enum NPCAnimationCandidateTests') == 1
    (out / 'AuthoredClips.swift').write_text(fixture.replace('@main enum NPCAnimationCandidateTests', 'enum NPCAnimationCandidateTests'))
    report = dict(status='RUNNING', startedAt=time.time(), sourceHashes=frozen,
                  scope='Actual backend handlers/inventory/population binary producer, complete native typed decoder and common pose owner. Authored catalog, graph, geometry/transport boundaries and CLP tracks; type-only skeletal/Metal boundary. No socket, GPU, rendered App, original assets or retail comparison.')

    def save():
        (out / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        (out.parent / 'latest.json').write_text(json.dumps(dict(path=str(out), **report), indent=2) + '\n')

    def run(command, name, budget):
        with (out / (name + '.log')).open('x') as log:
            process = subprocess.Popen(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
            try:
                return process.wait(timeout=budget)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait()
                return 124

    save()
    try:
        report['producerExit'] = run(['node', str(paths[10]), str(ROOT), str(out / 'backend.json')], 'producer', 20)
        save()
        assert report['producerExit'] == 0, (out / 'producer.log').read_text()[-5000:]
        command = ['xcrun', 'swiftc', '-parse-as-library', '-Onone', '-whole-module-optimization', '-j', '1', '-num-threads', '1',
                   '-module-cache-path', str(out / 'modules'), str(out / 'Common.swift'), *map(str, paths[6:8]),
                   str(out / 'AuthoredClips.swift'), str(paths[9]), '-o', str(out / 'verify')]
        report['compileExit'] = run(command, 'compile', 240)
        save()
        assert report['compileExit'] == 0, (out / 'compile.log').read_text()[-6500:]
        report['runtimeExit'] = run([str(out / 'verify'), str(out / 'backend.json')], 'runtime', 90)
        report['output'] = (out / 'runtime.log').read_text()
        assert report['runtimeExit'] == 0, report['output']
        report['status'] = 'PASS'
    except BaseException as error:
        report.update(status='FAIL', error=repr(error))
        raise
    finally:
        report.update(completedAt=time.time(), sourcesHeld=all(hashlib.sha256(Path(path).read_bytes()).hexdigest() == digest for path, digest in frozen.items()))
        save()
        print(json.dumps({key: value for key, value in report.items() if key != 'sourceHashes'}, indent=2))
    assert report['sourcesHeld']


if __name__ == '__main__':
    main()
