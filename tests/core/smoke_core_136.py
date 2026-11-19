#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Missing-water input-owner regression plus existing core source checks."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import os, subprocess, sys

root=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
subprocess.run(['python3','tests/movement/smoke_native_swim_retirement.py'],cwd=root,check=True)
subprocess.run(['python3','tests/core/smoke_core_134.py',*sys.argv[1:]],cwd=root,check=True)
print('PASS Core136 selected source gates; original timing, rendered and physical-device acceptance remain separate')
