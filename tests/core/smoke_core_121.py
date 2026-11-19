#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core121 source gates; SDK, reference assets and live play stay separate."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import os,subprocess,sys

root=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
for command in [['python3','tests/core/smoke_core_120.py',*sys.argv[1:]],
                ['python3','tests/movement/smoke_native_remote_foot_clock.py']]:
    subprocess.run(command,cwd=root,check=True)
print('PASS Core121 source gates; no retail1:1 or hardware claim')
