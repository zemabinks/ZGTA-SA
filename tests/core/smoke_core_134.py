#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Browser compressed-radio HTTP coverage plus the existing native source gates."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import os, subprocess, sys

root = Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS, 0, 15)
for command in (['node', 'tests/audio/smoke_browser_radio.js'],
                ['node', 'tests/audio/smoke_browser_radio_http.js'],
                ['python3', 'tests/core/smoke_core_131.py', *sys.argv[1:]]):
    subprocess.run(command, cwd=root, check=True)
print('PASS Core134 selected source gates; audible output, physical controls and retail parity remain separate')
