#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Traffic foundations, population resource recovery and retained core gates."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];os.setpriority(os.PRIO_PROCESS,0,15)
for command in [
    ['python3','tests/network/smoke_native_traffic_protocol.py'],
    ['python3','tests/network/smoke_native_traffic_roads.py'],
    ['python3','tests/network/smoke_native_traffic_state.py'],
    ['python3','tests/network/smoke_native_traffic_motion.py'],
    ['python3','tests/network/smoke_native_population_loading.py'],
    ['python3','tests/resources/test_traffic_roads.py'],
    ['python3','tests/core/smoke_core_161.py',*sys.argv[1:]],
]:subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core162 selected source gates; traffic scene/server integration, complete ambient AI and retail parity remain separate')
