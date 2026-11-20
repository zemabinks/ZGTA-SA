#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Remote pedestrian world playback and retained gameplay gates."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];os.setpriority(os.PRIO_PROCESS,0,15)
subprocess.run(['python3','tests/network/smoke_native_remote_motion.py'],cwd=ROOT,check=True)
subprocess.run(['python3','tests/core/smoke_core_156.py',*sys.argv[1:]],cwd=ROOT,check=True)
print('PASS Core157 selected source gates; rendered multiplayer and retail acceptance remain separate')
