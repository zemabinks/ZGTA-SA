#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Current vehicle shot bodies, actor lifetimes and retained gameplay checks."""
from pathlib import Path
import os, subprocess, sys
ROOT=Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS,0,15)
for command in [
    ['python3','tests/combat/smoke_native_shot_owner_lifetimes.py'],
    ['python3','tests/core/smoke_core_174.py',*sys.argv[1:]],
]:subprocess.run(command,cwd=ROOT,check=True)
print('PASS Core175 selected source checks; actual App, hardware and retail acceptance remain separate')
