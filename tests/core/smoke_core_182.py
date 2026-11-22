#!/usr/bin/env python3
# SPDX-License-Identifier: AGPL-3.0-only
"""Traffic-only touch entry and retained native gameplay regressions."""
from pathlib import Path
import os
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
os.setpriority(os.PRIO_PROCESS, 0, 15)
for command in [
    ['python3', 'tests/ui/smoke_native_traffic_entry_visibility.py'],
    ['python3', 'tests/core/smoke_core_181.py', *sys.argv[1:]],
]:
    subprocess.run(command, cwd=ROOT, check=True)
print('PASS Core182 selected source gates; actual touch/driver transfer, device and retail acceptance remain separate')
