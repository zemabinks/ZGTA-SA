#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Original-size detailed-world image admission and complete previous core chain."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
args=sys.argv[1:]
subprocess.run(['python3','tests/resources/smoke_native_world_sharp.py'],cwd=ROOT,check=True)
subprocess.run(['python3','tests/rendering/smoke_native_world_sharp.py',*(['--require-gpu']if '--require-gpu'in args else[])],cwd=ROOT,check=True)
subprocess.run(['python3','tests/core/smoke_core_145.py',*args],cwd=ROOT,check=True)
print('PASS Core146 selected source gates; original retail, installed scene and physical-device acceptance remain separate')
