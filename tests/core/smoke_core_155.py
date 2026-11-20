#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Bounded visual city preparation and the existing selected gameplay gates."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];os.setpriority(os.PRIO_PROCESS,0,15)
args=sys.argv[1:];gpu=['--require-gpu'] if '--require-gpu' in args else []
subprocess.run(['python3','tests/resources/smoke_native_world_streaming.py',*gpu],cwd=ROOT,check=True)
subprocess.run(['python3','tests/core/smoke_core_154.py',*args],cwd=ROOT,check=True)
print('PASS Core155 selected source gates; normal installed gameplay, hardware and original-retail acceptance remain separate')
