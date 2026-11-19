#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core124 original-first landing gate and prior source regressions."""
from pathlib import Path
import os,subprocess,sys

root=Path(__file__).resolve().parent
os.setpriority(os.PRIO_PROCESS,0,15)
subprocess.run(['python3','smoke_native_landing_gait.py'],cwd=root,check=True)
subprocess.run(['python3','smoke_core_123.py',*sys.argv[1:]],cwd=root,check=True)
print('PASS Core124 source gates; rendered, physical-device and retail acceptance remains separate')
