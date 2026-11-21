#!/usr/bin/env python3
"""Actual native WebSocket skin publication/receipt against a disposable backend."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib
import json
import os
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'local-only/research/skin-identity-104/network'
APP = ['ServerAddress', 'NativeInventoryPrediction', 'NativeShotTargeting', 'NativeStreamShotClaims',
       'NativeConnectionRecovery', 'NativeOriginalWorldProtocol', 'NativeOriginalWorldCommands',
       'NativeOriginalWorldVitals', 'NativeSAMPProtocol', 'NativeSAMPGameplayCommands',
       'NativeSAMPLocalVitals', 'NativeAmbientPedestrianProtocol','NativeAmbientTrafficProtocol','NativeOrdinaryShot','NativeLocalShots','NativeLocalShotPackets','NativeMultiplayerClient', 'NativeGameplayClient']


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    overlay = ROOT / 'local-only/research/skin-identity-104/maccer-overlay/game/native'
    if not (overlay / 'models/index.json').is_file():
        raise FileNotFoundError('Prepare the separately verified owner-local skin overlay first')
    paths = [f'ios/App/{name}.swift' for name in APP] + ['ios/App/NativeActorAnimation.swift',
             'tests/network/test_native_skin_network.py', 'tests/network/test_native_skin_network.swift', 'tests/network/test_native_skin_network.js']
    before = {name: (ROOT / name).read_bytes() for name in paths}
    dependencies = {}

    def include(name):
        if name in dependencies:
            return
        path = ROOT / name
        data = path.read_bytes()
        dependencies[name] = data
        for relative in re.findall(r"require\(['\"]\./([^'\"]+)['\"]\)", data.decode()):
            target = relative if relative.endswith('.js') else relative + '.js'
            if '/' in target or '..' in target:
                raise ValueError('Unexpected backend dependency path')
            include(target)

    include('selfhost_backend.js')
    with tempfile.TemporaryDirectory(prefix='isolated-', dir=OUT) as directory:
        work = Path(directory)
        game = work / 'game'
        game.mkdir()
        for name, data in dependencies.items():
            (game / name).write_bytes(data)
        state = game / 'local-only/selfhost'
        state.mkdir(parents=True)
        (state / 'client-catalog.json').write_text('{"vehicles":[],"homes":[]}')
        (state / 'weapon-catalog.json').write_text(json.dumps({'items': [
            {'id': 22, 'name': 'Synthetic namespace fixture', 'ammo': 100, 'capacity': 17,
             'price': 0, 'slot': 2, 'fire': 'INSTANT_HIT', 'stats': {'loop': [0, 9, 0], 'range': 40}}
        ], 'shops': []}))
        sources = []
        for name in APP:
            path = work / (name + '.swift')
            path.write_bytes(before[f'ios/App/{name}.swift'])
            sources.append(str(path))
        actor = before['ios/App/NativeActorAnimation.swift'].decode()
        fragment = actor[actor.index('struct NativePedestrianMotion {'):actor.index('struct NativeWeaponAnimation {')]
        (work / 'PedestrianMotion.swift').write_text('import Foundation\nimport simd\n' + fragment)
        sources.append(str(work / 'PedestrianMotion.swift'))
        (work / 'main.swift').write_bytes(before['tests/network/test_native_skin_network.swift'])
        sources.append(str(work / 'main.swift'))
        executable = work / 'verify'
        compiled = subprocess.run(['xcrun', 'swiftc', '-Onone', '-module-cache-path', str(OUT / 'modules'),
                                   *sources, '-o', str(executable)], capture_output=True, text=True)
        (OUT / 'compile.log').write_text(compiled.stdout + compiled.stderr)
        if compiled.returncode:
            print(compiled.stdout + compiled.stderr)
        compiled.check_returncode()
        environment = dict(os.environ, ZGTA_JOIN_CODE='', ZGTA_JOIN_CODE_FILE='',
                           ZGTA_DISCORD_CLIENT_ID='', ZGTA_DISCORD_CLIENT_SECRET='')
        result = subprocess.run(['node', str(ROOT / 'tests/network/test_native_skin_network.js'), str(game),
                                 str(executable), str(overlay), str(ROOT), str(OUT / 'wire-report.json')],
                                capture_output=True, text=True, env=environment, timeout=90)
        (OUT / 'runtime.log').write_text(result.stdout + result.stderr)
        unchanged = all((ROOT / name).read_bytes() == data for name, data in before.items())
        unchanged = unchanged and all((ROOT / name).read_bytes() == data for name, data in dependencies.items())
        wire_report = json.loads((OUT / 'wire-report.json').read_text())
        completed = (result.returncode == 0 and wire_report.get('status') == 'PASS' and
                     wire_report.get('child') == {'code': 0, 'signal': None} and
                     wire_report.get('nativeEntryGrants') == 8 and wire_report.get('browserEntryGrants') == 8)
        report = {'status': 'PASS' if completed and unchanged else 'FAIL',
                  'sourceUnchanged': unchanged, 'output': result.stdout + result.stderr,
                  'sourceHashes': {name: hashlib.sha256(data).hexdigest() for name, data in
                                   {**before, **dependencies}.items()},
                  'limits': ['Actual NativeMultiplayerClient URLSession sendPosition/updateRows and real independent backend WebSockets',
                             'Second peer uses the exact pinned browser model lookup; it is a headless protocol peer, not rendered Chrome',
                             'Overlay metadata travels over fixture HTTP; production serve_local overlay adoption is separate',
                             'Synthetic peers/state and ephemeral loopback port only; no8803, device, browser, Discord or original-service action',
                             'Aliases149/293 are wire-tested but have no native OG Loc mesh; no SA-MP UDP or GPU acceptance claim']}
        (OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print(result.stdout + result.stderr, end='')
        result.check_returncode()
        assert completed, 'Actual native child and wire fixture did not both complete successfully'
        assert unchanged


if __name__ == '__main__':
    main()
