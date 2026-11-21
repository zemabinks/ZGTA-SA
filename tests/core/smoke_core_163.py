#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Traffic scene ownership, body presentation and retained native regressions."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];os.setpriority(os.PRIO_PROCESS,0,15)
for command in [
    ['python3','tests/network/smoke_native_traffic_presentation.py'],
    ['python3','tests/network/smoke_native_traffic_scene.py'],
    ['python3','tests/core/smoke_core_162.py',*sys.argv[1:]],
]:subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core163 selected source gates; traffic GPU, occupancy, physics, AI and retail verification remain separate')
