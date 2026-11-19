#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Breathing lifetimes/ACK ownership plus the complete prior source chain."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
for command in [['python3','tests/ui/smoke_native_breath_ownership.py'],
                ['python3','tests/core/smoke_core_136.py',*sys.argv[1:]]]:
 subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core140 source gates; real-time, rendered, physical-device and retail parity remain separate')
