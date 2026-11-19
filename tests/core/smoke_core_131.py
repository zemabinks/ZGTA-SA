#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core131 explicit archive-route fences plus the existing native core gates."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import os,subprocess,sys

root=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
subprocess.run(['node','tests/browser/smoke_browser_task_policy_http.js','--archive-alias'],cwd=root,check=True)
subprocess.run(['python3','tests/core/smoke_core_130.py',*sys.argv[1:]],cwd=root,check=True)
print('PASS Core131 selected source gates; live scenes and original-game parity remain separate')
