#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Traffic materialization, actual contact replicas and retained source gates."""
from pathlib import Path
import os,subprocess,sys
ROOT=Path(__file__).resolve().parents[2];os.setpriority(os.PRIO_PROCESS,0,15)
commands=[['python3','tests/network/smoke_native_traffic_entry.py']]
if '--with-physics'in sys.argv:commands.append(['python3','tests/network/smoke_native_traffic_bodies.py'])
commands.append(['python3','tests/core/smoke_core_163.py',*sys.argv[1:]])
for command in commands:subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core164 selected source gates; full traffic transfer/driving, crews, AI, live-server and retail acceptance remain separate')
