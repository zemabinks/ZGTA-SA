#!/usr/bin/env python3
"""Verify gameplay's display-sleep lease without changing the host's sleep policy.

The controller shutdown boundary is exercised by smoke_native_connection_owners.
Actual UIKit lifecycle compilation and physical idle-time acceptance are separate.
"""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import hashlib
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / 'local-only/native-physics/tests/gameplay-idle'


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    paths = [ROOT / 'ios/App/NativeGameplayIdleTimer.swift', ROOT / 'tests/gameplay_idle/main.swift']
    before = {str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in paths}
    with tempfile.TemporaryDirectory(prefix='zgta-gameplay-idle-') as directory:
        binary = Path(directory) / 'verify'
        subprocess.run(['xcrun', 'swiftc', '-O', '-module-cache-path', str(OUT / 'modules'),
                        *map(str, paths), '-o', str(binary)], check=True)
        result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
    unchanged = all(hashlib.sha256((ROOT / name).read_bytes()).hexdigest() == value for name, value in before.items())
    report = {'pass': unchanged, 'sourceUnchanged': unchanged, 'sources': before,
              'scope': __doc__, 'output': result.stdout}
    (OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print(result.stdout, end='')
    if not unchanged:
        raise SystemExit('Gameplay idle sources changed during the test')


if __name__ == '__main__':
    main()
