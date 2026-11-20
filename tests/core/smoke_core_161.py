#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""NPC waiting/lifetime corrections and retained complete core source chain."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];os.setpriority(os.PRIO_PROCESS,0,15)
for command in [['python3','tests/network/smoke_native_ambient_waiting.py'],
                ['python3','tests/network/smoke_native_ambient_lifetime.py'],
                ['python3','tests/core/smoke_core_160.py',*sys.argv[1:]]]:
    subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core161 selected source gates; rendered waiting, complete NPC/traffic/police AI and retail parity remain separate')
