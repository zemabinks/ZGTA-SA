#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Imported-character scene fog and the existing selected gameplay chain."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];os.setpriority(os.PRIO_PROCESS,0,15)
args=sys.argv[1:];gpu=['--require-gpu']if '--require-gpu'in args else[]
for command in [['python3','tests/rendering/smoke_native_ped_environment.py',*gpu],
                ['python3','tests/core/smoke_core_150.py',*args]]:
    subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core151 selected source gates; ordinary raw-ped registration, original timecycle lighting, hardware and retail parity remain separate')
