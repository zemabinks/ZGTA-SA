#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core127 browser task-policy HTTP gate and prior native/source checks."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import os,subprocess,sys

root=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
subprocess.run(['node','tests/browser/smoke_browser_task_policy_http.js'],cwd=root,check=True)
subprocess.run(['python3','tests/core/smoke_core_126.py',*sys.argv[1:]],cwd=root,check=True)
print('PASS Core127 selected source checks; live scenes and retail parity remain separate')
