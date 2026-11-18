#!/usr/bin/env python3
"""Production health prediction plus actual HTTP/WS/backend integration."""
from pathlib import Path
import hashlib
import json
import os
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
OUT = ROOT / 'local-only/native-physics/tests/health-ack'


def declaration(source, marker):
    start = source.index(marker)
    end = source.index('{', start) + 1
    depth = 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    names = ['ServerAddress', 'NativeConnectionRecovery', 'NativeInventoryPrediction',
             'NativeShotTargeting', 'NativeStreamShotClaims', 'NativeOriginalWorldProtocol',
             'NativeOriginalWorldCommands', 'NativeOriginalWorldVitals', 'NativeSAMPProtocol','NativeSAMPGameplayCommands', 'NativeSAMPLocalVitals','NativeMultiplayerClient']
    inputs = {name: (ROOT / 'ios/App' / (name + '.swift')).read_text() for name in names}
    prediction = declaration(inputs['NativeMultiplayerClient'], 'struct NativeHealthPrediction {')
    with tempfile.TemporaryDirectory(prefix='health-ack-', dir=OUT) as directory:
        work = Path(directory)
        pure = work / 'pure.swift'
        pure.write_text((ROOT / 'smoke_native_health.swift').read_text().replace('// HEALTH_PREDICTION', prediction))
        subprocess.run(['xcrun', 'swiftc', '-parse-as-library', '-O', '-module-cache-path', str(OUT / 'modules'),
                        str(pure), '-o', str(work / 'pure')], check=True)
        subprocess.run([str(work / 'pure')], check=True)
        # Compile the full native transport. Unrelated rendering is not linked.
        actor = (ROOT / 'ios/App/NativeActorAnimation.swift').read_text()
        actor = actor[actor.index('struct NativePedestrianMotion {'):actor.index('struct NativeWeaponAnimation {')]
        main = work / 'main.swift'
        main.write_text('\n'.join(inputs.values()) + '\n' + actor + '\n' +
                        (ROOT / 'smoke_native_health_wire.swift').read_text())
        subprocess.run(['xcrun', 'swiftc', '-O', '-module-cache-path', str(OUT / 'modules'),
                        str(main), '-o', str(work / 'client')], check=True)
        game = work / 'game'
        data = game / 'local-only/selfhost'
        data.mkdir(parents=True)
        for name in ['selfhost_backend.js', 'optional_discord.js', 'weapon_inventory.js', 'world_collision.js', 'local_projectiles.js', 'player_placement.js']:
            shutil.copyfile(ROOT / name, game / name)
        (data / 'client-catalog.json').write_text(json.dumps({'vehicles': [], 'homes': []}))
        (data / 'weapon-catalog.json').write_text(json.dumps({'items': [], 'shops': []}))
        environment = dict(os.environ, ZGTA_JOIN_CODE='', ZGTA_JOIN_CODE_FILE='',
                           ZGTA_DISCORD_CLIENT_ID='', ZGTA_DISCORD_CLIENT_SECRET='')
        run = subprocess.run(['node', str(ROOT / 'smoke_native_health_server.js'), str(game), str(work / 'client')],
                             capture_output=True, text=True, env=environment, timeout=90)
        print(run.stdout, end=''); print(run.stderr, end='')
        (OUT / 'wire.log').write_text(run.stdout + run.stderr)
        (OUT / 'report.json').write_text(json.dumps({'pass': run.returncode == 0,
            'sources': {name: hashlib.sha256(source.encode()).hexdigest() for name, source in inputs.items()},
            'scope': __doc__, 'output': run.stdout,
            'limits': ['Synthetic accounts and controlled server events; no retail runtime or production server']}, indent=2) + '\n')
        run.check_returncode()


if __name__ == '__main__':
    main()
