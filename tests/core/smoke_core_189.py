#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Native NPC observation transitions and retained core regressions."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS, 0, 15)
for command in [
    ['python3', 'tests/network/smoke_native_npc_transitions.py'],
    ['python3', 'tests/core/smoke_core_188.py', *sys.argv[1:]],
]:
    subprocess.run(command, cwd=ROOT, check=True)
print('PASS Core189 native NPC observation transitions and selected source chain; rendered/hardware/retail accuracy remain separate')
