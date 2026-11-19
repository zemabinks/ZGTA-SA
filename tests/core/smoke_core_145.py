#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Native-size vehicle textures and the complete prior selected core chain."""
from pathlib import Path
import os, subprocess, sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
arguments=sys.argv[1:]
subprocess.run(['python3','tests/resources/test_native_vehicle_textures.py',*(['--require-gpu'] if '--require-gpu' in arguments else [])],cwd=ROOT,check=True)
subprocess.run(['python3','tests/core/smoke_core_144.py',*arguments],cwd=ROOT,check=True)
print('PASS Core145 selected source gates; installed resource/gameplay and retail acceptance remain separate')
