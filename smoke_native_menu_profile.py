#!/usr/bin/env python3
"""Real menu client, saved guest helper and disposable self-hosted HTTP handlers."""
from pathlib import Path
import os
import hashlib
import json
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent
SWIFT = ROOT / "smoke_native_menu_profile.swift"
SERVER = ROOT / "smoke_native_menu_profile_server.js"
OUT = ROOT / 'local-only/native-physics/tests/menu-profile'


def main():
    OUT.mkdir(parents=True,exist_ok=True)
    files=['ios/App/HomeViewController.swift','ios/App/NativeMenuProfileClient.swift','ios/App/ServerAddress.swift',
           'selfhost_backend.js','optional_discord.js','weapon_inventory.js','world_collision.js','local_projectiles.js', 'player_placement.js',
           'smoke_native_menu_profile.swift','smoke_native_menu_profile_server.js','smoke_native_menu_profile.py']
    inputs={name:(ROOT/name).read_bytes() for name in files}
    with tempfile.TemporaryDirectory(prefix="zgta-menu-profile-") as folder:
        temp = Path(folder)
        for name in ["selfhost_backend.js", "optional_discord.js", "weapon_inventory.js",
                     "world_collision.js", "local_projectiles.js", "player_placement.js"]:
            (temp/name).write_bytes(inputs[name])
        data = temp / "local-only" / "selfhost"
        data.mkdir(parents=True)
        (data / "client-catalog.json").write_text('{"vehicles":[],"homes":[]}')
        (data / "weapon-catalog.json").write_text('{"items":[],"shops":[]}')
        source = inputs['ios/App/HomeViewController.swift'].decode()
        start = source.index("enum LocalGuestSession {")
        depth = 0
        finish = None
        for i in range(source.index("{", start), len(source)):
            depth += (source[i] == "{") - (source[i] == "}")
            if depth == 0:
                finish = i + 1
                break
        assert finish is not None
        guest = temp / "LocalGuestSession.swift"
        guest.write_text("import Foundation\nimport Security\n" + source[start:finish])
        entry = temp / "main.swift"
        entry.write_bytes(inputs['smoke_native_menu_profile.swift'])
        client=temp/'NativeMenuProfileClient.swift';client.write_bytes(inputs['ios/App/NativeMenuProfileClient.swift'])
        address=temp/'ServerAddress.swift';address.write_bytes(inputs['ios/App/ServerAddress.swift'])
        server=temp/'server.js';server.write_bytes(inputs['smoke_native_menu_profile_server.js'])
        executable = temp / "menu-profile"
        subprocess.run(["xcrun", "swiftc", "-module-cache-path", str(OUT/'module-cache'),
                        str(address), str(guest), str(client), str(entry),
                        "-o", str(executable)], check=True)
        environment = dict(os.environ, ZGTA_JOIN_CODE="", ZGTA_JOIN_CODE_FILE="",
                           ZGTA_DISCORD_CLIENT_ID="", ZGTA_DISCORD_CLIENT_SECRET="")
        result=subprocess.run(["node", str(server), str(temp), str(executable)],
                       capture_output=True,text=True,env=environment,timeout=60)
        print(result.stdout,end='');print(result.stderr,end='')
        (OUT/'runtime.log').write_text(result.stdout+result.stderr)
        (OUT/'report.json').write_text(json.dumps({'status':'PASS' if result.returncode==0 else 'FAIL',
            'coverage':['original25 management checks','fresh connection + saved per-server identity',
                        'actual authorized/join/auth cookie sequence','status schema and auth rejection',
                        'cross-port redirects blocked at status/join/auth','delayed status/auth cancellation + reconnect'],
            'sourceHashes':{p:hashlib.sha256(data).hexdigest() for p,data in inputs.items()},
            'liveFilesStillMatchSnapshot':{p:(ROOT/p).read_bytes()==data for p,data in inputs.items()},
            'limits':['HTTP is real loopback traffic to disposable backend copies, not a device/UI acceptance',
                      'Forwarded fixture header exercises the real remote-visitor authorization branch']},indent=2)+'\n')
        result.check_returncode()


if __name__ == "__main__":
    main()
