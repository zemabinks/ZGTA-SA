#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Remote actor presentation, frame heat retirement and retained regressions."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
subprocess.run(['python3','tests/network/smoke_native_remote_life.py'],cwd=ROOT,check=True)
subprocess.run(['python3','tests/core/smoke_core_200.py',*sys.argv[1:]],cwd=ROOT,check=True)
print('PASS Core201 selected source chain; actual rendered flames and multiplayer require separate application evidence')
