#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Native character material binding and verified stock rig acquisition."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];os.setpriority(os.PRIO_PROCESS,0,15)
args=sys.argv[1:];gpu=['--require-gpu']if '--require-gpu'in args else[]
for command in [['python3','tests/resources/smoke_native_stock_ped.py',*gpu],
                ['python3','tests/rendering/smoke_native_ped_materials.py',*gpu],
                ['python3','tests/core/smoke_core_149.py',*args]]:
    subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core150 selected source gates; ordinary raw-ped renderer registration, hardware and original-retail parity remain separate')
