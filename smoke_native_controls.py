#!/usr/bin/env python3
"""Exercise the actual native input/clock/camera helpers without Simulator UI."""
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent

def main():
    output = ROOT / 'local-only/native-physics/tests/core-controls'
    output.mkdir(parents=True, exist_ok=True)
    metadata = ROOT / 'local-only/site/game/native/camera.json'
    if not metadata.is_file():
        raise SystemExit('Prepare the owner-provided native camera metadata before this test.')
    with tempfile.TemporaryDirectory(prefix='run-', dir=output) as temporary:
        snapshot = Path(temporary)
        shutil.copyfile(ROOT / 'smoke_native_controls.swift', snapshot / 'main.swift')
        sources = []
        for name in ['ServerAddress', 'NativeGameInput', 'NativeGameCamera']:
            path = snapshot / f'{name}.swift'
            shutil.copyfile(ROOT / 'ios/App' / path.name, path)
            sources.append(path)
        subprocess.run(['xcrun', 'swiftc', '-O', '-module-cache-path', str(output / 'modules'), *map(str, sources),
                        str(snapshot / 'main.swift'), '-o', str(snapshot / 'verify')], check=True)
        subprocess.run([str(snapshot / 'verify'), str(metadata)], check=True)

if __name__ == '__main__':
    main()
