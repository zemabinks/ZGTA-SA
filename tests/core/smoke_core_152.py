#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Original pedestrian admission, rig compatibility and existing gameplay chain."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];os.setpriority(os.PRIO_PROCESS,0,15)
args=sys.argv[1:];gpu=['--require-gpu']if '--require-gpu'in args else[]
for command in [['python3','tests/resources/smoke_native_stock_ped_runtime.py',*gpu],
                ['python3','tests/resources/smoke_native_rig_compatibility.py',*gpu],
                ['python3','tests/core/smoke_core_151.py',*args]]:
    subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core152 selected source gates; ordinary installed original-pedestrian use, hardware and retail acceptance remain separate')
