#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Traffic spawn clearance, observation lifetimes and retained regressions."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
for command in [['python3','tests/ui/test_xctest_outcome.py'],['node','tests/server/smoke_traffic_spawn_clearance.js'],['node','tests/server/smoke_traffic_observation.js'],['python3','tests/core/smoke_core_180.py',*sys.argv[1:]]]:
    subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core181 selected source gates; native App, traffic AI completeness and retail parity remain separate')
