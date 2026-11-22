#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Independent road traffic authority and retained native gameplay gates."""
from pathlib import Path
import os
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
for command in [
    ['node','tests/server/smoke_traffic_roads.js'],
    ['node','tests/server/smoke_traffic_tasks.js'],
    ['python3','tests/resources/test_traffic_population.py'],
    ['node','tests/server/smoke_traffic_loader.js'],
    ['node','tests/server/smoke_traffic_backend.js'],
    ['python3','tests/core/smoke_core_179.py',*sys.argv[1:]],
]:
    subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core180 selected source/transport and retained regressions; original traffic AI, rendered native/browser, device and retail acceptance remain separate')
