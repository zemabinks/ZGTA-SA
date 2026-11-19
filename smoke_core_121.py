#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Core121 source gates; SDK, reference assets and live play stay separate."""
from pathlib import Path
import os,subprocess,sys

root=Path(__file__).resolve().parent
os.setpriority(os.PRIO_PROCESS,0,15)
for command in [['python3','smoke_core_120.py',*sys.argv[1:]],
                ['python3','smoke_native_remote_foot_clock.py']]:
    subprocess.run(command,cwd=root,check=True)
print('PASS Core121 source gates; no retail1:1 or hardware claim')
