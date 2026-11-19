#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Rider presentation hitch ownership and the retained complete core chain."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];os.setpriority(os.PRIO_PROCESS,0,15)
for command in [['python3','tests/vehicles/smoke_native_rider_hitches.py'],['python3','tests/core/smoke_core_147.py',*sys.argv[1:]]]:subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core148 selected source gates; rendered, device and original-retail timing acceptance remain separate')
