#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core123 source gates; optional actual Metal output needs a native device."""

import sys as _zgta_sys
from pathlib import Path as _zgta_Path
_ZGTA_ROOT = _zgta_Path(__file__).resolve().parents[2]
if str(_ZGTA_ROOT) not in _zgta_sys.path: _zgta_sys.path.insert(0, str(_ZGTA_ROOT))

from pathlib import Path
import argparse,os,subprocess

root=Path(__file__).resolve().parents[2]
p=argparse.ArgumentParser(description=__doc__,add_help=False)
p.add_argument('--with-model-metal',action='store_true')
args,prior=p.parse_known_args()
os.setpriority(os.PRIO_PROCESS,0,15)
subprocess.run(['python3','tests/core/smoke_core_122.py',*prior],cwd=root,check=True)
subprocess.run(['python3','tests/resources/test_native_renderware_model.py',
                '--require-metal' if args.with_model_metal else '--cpu-only'],cwd=root,check=True)
print('PASS Core123 selected source gates; game-world/device/retail acceptance remains separate')
